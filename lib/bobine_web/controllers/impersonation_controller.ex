defmodule BobineWeb.ImpersonationController do
  @moduledoc """
  Handles super admin impersonation of tenant organizations.

  Start impersonation by storing the target org ID in the session.
  Stop impersonation by clearing it. The SetOrganization plug and
  AssignScope hook read the session to resolve the impersonated org.
  """

  use BobineWeb, :controller

  alias Bobine.Admin

  def start(conn, %{"id" => org_id}) do
    scope = conn.assigns[:current_scope]

    if scope && scope.user && scope.user.is_super_admin do
      org = Admin.get_organization!(org_id)

      conn
      |> put_session(:impersonated_org_id, org.id)
      |> put_flash(:info, "You are now viewing #{org.name} as a super admin.")
      |> redirect(to: ~p"/admin")
    else
      conn
      |> put_flash(:error, "Access denied.")
      |> redirect(to: ~p"/")
    end
  end

  def stop(conn, _params) do
    conn
    |> delete_session(:impersonated_org_id)
    |> put_flash(:info, "Stopped impersonating.")
    |> redirect(to: ~p"/super/organizations")
  end
end
