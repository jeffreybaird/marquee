defmodule MarqueeWeb.Hooks.RequireSuperAdmin do
  @moduledoc """
  LiveView `on_mount` hook that enforces super admin access.

  Checks `current_scope.user.is_super_admin`. Halts with a redirect to `/`
  if the user is not authenticated or not a super admin.

  ## Usage

      live_session :super_admin,
        on_mount: [
          {MarqueeWeb.UserAuth, :require_authenticated},
          {MarqueeWeb.Hooks.RequireSuperAdmin, :require_super_admin}
        ] do
        live "/super", MarqueeWeb.Super.DashboardLive
      end

  """

  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:require_super_admin, _params, _session, socket) do
    scope = socket.assigns[:current_scope]

    if scope && scope.user && scope.user.is_super_admin do
      {:cont, assign(socket, :page_title, "Super Admin")}
    else
      {:halt,
       socket
       |> put_flash(:error, "Access denied.")
       |> redirect(to: "/")}
    end
  end
end
