defmodule MarqueeWeb.Plugs.AdminDemoAccess do
  @moduledoc "Resolves private admin capabilities only on the dedicated host, without replacing ordinary auth."
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]
  alias Marquee.AdminDemo

  def init(opts), do: opts

  def call(conn, _opts) do
    if AdminDemo.host?(conn.host), do: dedicated(conn), else: conn
  end

  defp dedicated(conn) do
    conn = put_resp_header(conn, "cache-control", "private, no-store")

    if String.starts_with?(conn.request_path, "/demo/admin"),
      do: conn,
      else: resolve_capability(conn)
  end

  defp admin_path_allowed?(path) do
    path in ~w(/admin /admin/content /admin/collections /admin/series /admin/tags /admin/catalog /admin/analytics /admin/branding /admin/appearance /admin/settings/billing /admin/demo/library /admin/demo/restricted) or
      Regex.match?(~r{^/admin/series/[^/]+/seasons/[^/]+$}, path) or
      Regex.match?(~r{^/admin/analytics/(videos|series)/[^/]+(?:/seasons/[^/]+)?$}, path)
  end

  defp viewer_path_allowed?(path),
    do:
      path == "/" or
        Enum.any?(["/watch/", "/collections/", "/series/"], &String.starts_with?(path, &1))

  defp resolve_capability(conn) do
    case AdminDemo.get_session(get_session(conn, :admin_demo_token)) do
      {:ok, %{scope: scope, session: session}} ->
        conn =
          conn
          |> assign(:admin_demo_scope, scope)
          |> assign(:current_scope, scope)
          |> assign(:organization, scope.organization)

        cond do
          admin_path_allowed?(conn.request_path) ->
            conn

          String.starts_with?(conn.request_path, "/admin") ->
            conn |> redirect(to: "/admin/demo/restricted") |> halt()

          viewer_path_allowed?(conn.request_path) ->
            conn
            |> put_session(:member_preview_org_id, scope.organization.id)
            |> put_session(:member_preview_viewer_id, session.generation)

          true ->
            conn |> redirect(to: "/admin/demo/restricted") |> halt()
        end

      _ ->
        conn |> redirect(to: "/demo/admin") |> halt()
    end
  end
end
