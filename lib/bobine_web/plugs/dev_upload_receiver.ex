defmodule BobineWeb.Plugs.DevUploadReceiver do
  @moduledoc """
  Dev-only endpoint plug that receives browser PUTs at `/dev/uploads/<key>`
  and writes the body to `priv/static/uploads/<key>`.

  Mounted above `Plug.Parsers` in the endpoint so the raw binary body is
  not consumed by the webhook body reader. Halts the pipeline with a
  200 response on success; requests that don't match the upload path are
  passed through untouched.

  Only compiled into the endpoint when `config :bobine, :dev_routes` is
  set (dev env).
  """

  @behaviour Plug

  import Plug.Conn

  @prefix "/dev/uploads/"
  @max_bytes 25_000_000

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "OPTIONS", request_path: path} = conn, _opts) do
    if String.starts_with?(path, @prefix) do
      conn
      |> put_cors_headers()
      |> send_resp(204, "")
      |> halt()
    else
      conn
    end
  end

  def call(%Plug.Conn{method: "PUT", request_path: path} = conn, _opts) do
    if String.starts_with?(path, @prefix) do
      conn
      |> put_cors_headers()
      |> store(String.trim_leading(path, @prefix))
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  defp store(conn, "") do
    conn |> send_resp(400, "missing key") |> halt()
  end

  defp store(conn, key) do
    case read_all_body(conn) do
      {:ok, body, conn} ->
        write_file!(key, body)

        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(200, Jason.encode!(%{key: key, size: byte_size(body)}))
        |> halt()

      {:too_large, conn} ->
        conn |> send_resp(413, "payload too large") |> halt()

      {:error, reason, conn} ->
        conn |> send_resp(500, "read error: #{inspect(reason)}") |> halt()
    end
  end

  defp write_file!(key, body) do
    full_path = Path.join(Bobine.Storage.LocalClient.upload_dir(), key)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, body)
  end

  defp read_all_body(conn) do
    case read_body(conn, length: @max_bytes + 1) do
      {:ok, body, conn} when byte_size(body) <= @max_bytes -> {:ok, body, conn}
      {:ok, _body, conn} -> {:too_large, conn}
      {:more, _body, conn} -> {:too_large, conn}
      {:error, reason} -> {:error, reason, conn}
    end
  end

  defp put_cors_headers(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "PUT, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type, x-amz-acl")
  end
end
