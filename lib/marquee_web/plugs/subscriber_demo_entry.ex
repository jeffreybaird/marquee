defmodule MarqueeWeb.Plugs.SubscriberDemoEntry do
  @moduledoc "Keeps subscriber demo navigation private; identities are created only by explicit POST entry."
  @behaviour Plug

  import Plug.Conn

  alias Marquee.{SubscriberDemo, Viewers}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    org = conn.assigns[:organization]

    if navigation?(conn) and SubscriberDemo.enabled?(org) and not operator_session?(conn) do
      private_demo_navigation(conn)
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

  defp private_demo_navigation(conn) do
    token = get_session(conn, :viewer_token)
    viewer = token && Viewers.get_viewer_by_session_token(token)

    if viewer && not SubscriberDemo.demo_viewer?(viewer),
      do: conn,
      else: private_response(conn)
  end

  defp private_response(conn), do: put_resp_header(conn, "cache-control", "private, no-store")
end
