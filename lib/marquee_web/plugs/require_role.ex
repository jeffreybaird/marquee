defmodule MarqueeWeb.Plugs.RequireRole do
  @moduledoc """
  Plug that enforces a minimum role for the current user's membership.

  Reads the minimum required role from plug options:

      plug MarqueeWeb.Plugs.RequireRole, minimum_role: :editor

  Redirects to `/admin` with an error flash if the role check fails.
  Redirects to `/users/log-in` with an error flash if not authenticated.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  alias Marquee.Accounts

  def init(opts), do: opts

  def call(conn, minimum_role: role) do
    scope = conn.assigns[:current_scope]

    cond do
      is_nil(scope) or is_nil(scope.user) ->
        conn
        |> put_flash(:error, "You must be logged in to access this page.")
        |> redirect(to: "/")
        |> halt()

      # Super admins bypass role checks — they can access any org's admin pages
      scope.user.is_super_admin ->
        conn

      is_nil(scope.membership) ->
        conn
        |> put_flash(:error, "You must be logged in to access this page.")
        |> redirect(to: "/")
        |> halt()

      Accounts.role_at_least?(scope.membership, role) ->
        conn

      true ->
        conn
        |> put_flash(:error, "You don't have permission to access this page.")
        |> redirect(to: "/admin")
        |> halt()
    end
  end
end
