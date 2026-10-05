defmodule MarqueeWeb.SubscriberDemoController do
  @moduledoc "Starts a private subscriber demo using the ordinary signed viewer session."
  use MarqueeWeb, :controller

  alias Marquee.{SubscriberDemo, Viewers}
  alias MarqueeWeb.OrgURL

  @doc "Starts or resumes the resolved tenant's demo without replacing a real viewer."
  def create(conn, _params) do
    conn = put_resp_header(conn, "cache-control", "private, no-store")
    org = request_organization(conn)
    token = get_session(conn, :viewer_token)
    viewer = token && Viewers.get_viewer_by_session_token(token)

    cond do
      not SubscriberDemo.enabled?(org) ->
        send_resp(conn, 403, "Subscriber demo is not available for this organization.")

      viewer && not SubscriberDemo.demo_viewer?(viewer) ->
        redirect(conn, to: ~p"/")

      viewer && viewer.organization_id == org.id ->
        conn |> clear_preview() |> redirect(to: home_path(conn, org))

      true ->
        start_demo(conn, org)
    end
  end

  defp request_organization(conn) do
    assigned = conn.assigns[:organization] || conn.assigns.current_scope.organization

    # A stale dev session slug must not let a POST on a different tenant host
    # create or reuse a Workshop identity. Explicit development org signals
    # retain the resolver's documented precedence.
    if conn.query_params["org"] || get_req_header(conn, "x-marquee-org") != [] do
      assigned
    else
      with {:error, :not_found} <- Marquee.Accounts.get_organization_by_custom_domain(conn.host),
           {:error, :not_found} <-
             Marquee.Accounts.get_organization_by_slug(conn.host |> String.split(".") |> hd()) do
        assigned
      else
        {:ok, org} -> org
      end
    end
  end

  defp start_demo(conn, org) do
    case SubscriberDemo.start_session(org) do
      {:ok, %{token: token}} ->
        conn
        |> configure_session(renew: true)
        |> clear_preview()
        |> put_session(:viewer_token, token)
        |> put_session(:live_socket_id, "viewers_sessions:#{Base.url_encode64(token)}")
        |> redirect(to: home_path(conn, org))

      {:error, :demo_unavailable} ->
        conn
        |> put_resp_header("retry-after", "60")
        |> send_resp(503, "The subscriber demo is being prepared. Please try again shortly.")

      {:error, :forbidden} ->
        send_resp(conn, 403, "Subscriber demo is not available for this organization.")
    end
  end

  defp home_path(conn, org) do
    if conn.host == MarqueeWeb.Endpoint.config(:url)[:host],
      do: OrgURL.org_url("/", org),
      else: ~p"/"
  end

  defp clear_preview(conn) do
    conn
    |> delete_session(:member_preview_org_id)
    |> delete_session(:member_preview_viewer_id)
    |> delete_session(:impersonating_viewer_id)
    |> delete_session(:impersonating_admin_user_id)
    |> delete_session(:impersonating_return_path)
    |> delete_session(:impersonation_started_at)
  end
end
