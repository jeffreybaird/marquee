defmodule MarqueeWeb.Plugs.SubscriberDemoEntry do
  @moduledoc "Starts an isolated subscriber demo on an eligible tenant's first home-page navigation."
  @behaviour Plug

  import Plug.Conn

  alias Marquee.{SubscriberDemo, Viewers}
  alias MarqueeWeb.Plugs.RateLimit

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    org = conn.assigns[:organization]

    if navigation?(conn) and SubscriberDemo.enabled?(org) and not operator_session?(conn) do
      enter_demo(conn, org)
    else
      conn
    end
  end

  defp navigation?(conn) do
    original_method = conn.private[:original_request_method] || conn.method
    original_method == "GET" and conn.request_path == "/" and not prefetch?(conn)
  end

  defp prefetch?(conn) do
    Enum.any?(["purpose", "sec-purpose"], fn header ->
      conn
      |> get_req_header(header)
      |> Enum.any?(&String.contains?(String.downcase(&1), "prefetch"))
    end)
  end

  defp operator_session?(conn) do
    scope = conn.assigns[:current_scope]

    not is_nil(scope && scope.user) or
      not is_nil(get_session(conn, :member_preview_org_id)) or
      not is_nil(get_session(conn, :impersonating_viewer_id)) or
      not is_nil(get_session(conn, :impersonating_admin_user_id))
  end

  defp enter_demo(conn, org) do
    token = get_session(conn, :viewer_token)
    viewer = token && Viewers.get_viewer_by_session_token(token)

    cond do
      viewer && not SubscriberDemo.demo_viewer?(viewer) ->
        conn

      viewer && viewer.organization_id == org.id ->
        private_response(conn)

      true ->
        conn |> private_response() |> limit_allocation() |> start_demo(org)
    end
  end

  defp private_response(conn), do: put_resp_header(conn, "cache-control", "private, no-store")

  defp limit_allocation(conn) do
    conn = RateLimit.call(conn, bucket: :tenant_pages, limit: 300, key: :organization_id)

    if conn.halted,
      do: conn,
      else: RateLimit.call(conn, bucket: :auth, limit: 10, key: :ip)
  end

  defp start_demo(%{halted: true} = conn, _org), do: conn

  defp start_demo(conn, org) do
    case SubscriberDemo.start_session(org) do
      {:ok, %{token: token}} ->
        conn
        |> configure_session(renew: true)
        |> put_session(:viewer_token, token)
        |> put_session(:live_socket_id, "viewers_sessions:#{Base.url_encode64(token)}")

      {:error, _reason} ->
        conn
        |> put_resp_header("retry-after", "60")
        |> send_resp(503, "The subscriber demo is being prepared. Please try again shortly.")
        |> halt()
    end
  end
end
