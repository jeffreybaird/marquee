defmodule MarqueeWeb.Plugs.MemberPreview do
  @moduledoc """
  Persists an authorized, tenant-scoped member preview across viewer navigation.
  Returning to the admin dashboard ends preview mode. No viewer account is created.
  """

  import Plug.Conn

  alias Marquee.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    scope = conn.assigns[:current_scope]
    org = conn.assigns[:organization] || (scope && scope.organization)

    cond do
      String.starts_with?(conn.request_path, "/admin") ->
        clear_preview(conn)

      conn.query_params["preview"] == "member" && authorized?(scope, org) ->
        conn
        |> put_session(:member_preview_org_id, org.id)
        |> put_session(:member_preview_viewer_id, Ecto.UUID.generate())

      preview_invalid?(conn, scope, org) ->
        clear_preview(conn)

      true ->
        conn
    end
  end

  @doc """
  Checks whether an operator can preview the resolved organization.

      iex> MarqueeWeb.Plugs.MemberPreview.authorized?(nil, nil)
      false
  """
  def authorized?(%{user: %{is_super_admin: true}}, %{id: _}), do: true

  def authorized?(%{user: user}, %{id: _} = org) when not is_nil(user) do
    case Accounts.get_membership(org, user) do
      nil -> false
      membership -> Accounts.role_at_least?(membership, :admin)
    end
  end

  def authorized?(_, _), do: false

  @doc """
  Resolves a read-only preview identity after checking the current operator's access.

      iex> MarqueeWeb.Plugs.MemberPreview.viewer(%{}, nil, nil)
      nil
  """
  def viewer(session, scope, org) do
    if org && session["member_preview_org_id"] == org.id &&
         is_binary(session["member_preview_viewer_id"]) && authorized?(scope, org) do
      %Marquee.Viewers.Viewer{
        id: session["member_preview_viewer_id"],
        organization_id: org.id,
        email: scope.user.email,
        display_name: "Member preview",
        subscription_status: "active",
        __impersonating__: true,
        __preview__: true
      }
    end
  end

  defp preview_invalid?(conn, scope, org) do
    preview_org_id = get_session(conn, :member_preview_org_id)
    preview_org_id && (!authorized?(scope, org) || preview_org_id != org.id)
  end

  defp clear_preview(conn) do
    conn
    |> delete_session(:member_preview_org_id)
    |> delete_session(:member_preview_viewer_id)
  end
end
