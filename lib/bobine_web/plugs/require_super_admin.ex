defmodule BobineWeb.Plugs.RequireSuperAdmin do
  @moduledoc """
  Plug that enforces super admin access.

  Checks `current_scope.user.is_super_admin`. Does NOT check organization or
  membership — super admin routes operate above the tenant layer.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    scope = conn.assigns[:current_scope]

    cond do
      is_nil(scope) or is_nil(scope.user) ->
        conn
        |> put_flash(:error, "You must be logged in.")
        |> redirect(to: "/")
        |> halt()

      scope.user.is_super_admin ->
        conn

      true ->
        conn
        |> put_flash(:error, "Access denied.")
        |> redirect(to: "/")
        |> halt()
    end
  end
end
