defmodule MarqueeFeatures.UploadStubServer do
  @moduledoc """
  Local stand-in for the direct-upload targets the browser PUTs bytes to:
  Mux direct-upload URLs and presigned DigitalOcean Spaces URLs.

  Not a step module (it exports no `__cucumberex_steps__`), so Cucumberex
  compiles it but never registers it. Cucumberex compiles these files one
  at a time in path order, so the leading underscore in the file name puts
  this module ahead of the step modules that call it. Step definitions start one server per
  scenario, hand its URLs to the `MockMuxClient` / `MockSpacesClient` stubs,
  and assert on the messages it sends back. No request ever leaves the
  machine, so real Mux and Spaces are never contacted.

  Every received PUT is reported to `owner` as

      {:upload_stub_received, handler_pid, request_path, body}

  With `hold: true` the handler keeps the HTTP response open until the
  owner sends `{:upload_stub_release, handler_pid}` (or 30 s pass), so a
  step can observe the in-flight upload UI before letting it finish.

  Cross-origin PUTs from the app page trigger a CORS preflight, which is
  answered permissively.
  """

  @behaviour Plug

  import Plug.Conn

  @hold_timeout_ms 30_000

  @doc """
  Starts a stub server on a random loopback port, unlinked from the caller.

  Returns `%{pid: pid, base_url: "http://127.0.0.1:<port>"}`.
  """
  def start(owner, opts \\ []) do
    config = %{owner: owner, hold: Keyword.get(opts, :hold, false)}

    {:ok, pid} =
      Bandit.start_link(
        plug: {__MODULE__, config},
        ip: :loopback,
        port: 0,
        startup_log: false
      )

    Process.unlink(pid)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    %{pid: pid, base_url: "http://127.0.0.1:#{port}"}
  end

  @doc """
  Stops a server returned by `start/2`.
  """
  def stop(%{pid: pid}) do
    if Process.alive?(pid), do: Supervisor.stop(pid, :normal)
    :ok
  end

  @doc """
  Releases a held upload so the browser receives its 200 response.
  """
  def release(handler_pid), do: send(handler_pid, {:upload_stub_release, handler_pid})

  @impl Plug
  def init(config), do: config

  @impl Plug
  def call(%Plug.Conn{method: "OPTIONS"} = conn, _config) do
    conn
    |> put_cors_headers()
    |> send_resp(204, "")
  end

  def call(%Plug.Conn{method: "PUT"} = conn, %{owner: owner, hold: hold}) do
    {conn, body} = read_full_body(conn, "")
    send(owner, {:upload_stub_received, self(), conn.request_path, body})
    if hold, do: await_release()

    conn
    |> put_cors_headers()
    |> send_resp(200, "")
  end

  def call(conn, _config) do
    conn
    |> put_cors_headers()
    |> send_resp(405, "")
  end

  defp await_release do
    me = self()

    receive do
      {:upload_stub_release, ^me} -> :ok
    after
      @hold_timeout_ms -> :ok
    end
  end

  defp read_full_body(conn, acc) do
    case read_body(conn) do
      {:ok, chunk, conn} -> {conn, acc <> chunk}
      {:more, chunk, conn} -> read_full_body(conn, acc <> chunk)
    end
  end

  defp put_cors_headers(conn) do
    requested_headers =
      conn
      |> get_req_header("access-control-request-headers")
      |> List.first("content-type")

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "PUT, OPTIONS")
    |> put_resp_header("access-control-allow-headers", requested_headers)
    |> put_resp_header("access-control-max-age", "600")
  end
end
