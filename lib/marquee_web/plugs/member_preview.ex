defmodule MarqueeWeb.Plugs.MemberPreview do
  @moduledoc """
  Persists an authorized, tenant-scoped member preview across viewer navigation.
  Returning to the admin dashboard ends preview mode. No viewer account is created.

  Opening the appearance editor (`/admin/appearance`) also starts an
  *appearance preview session*: the session carries an `:appearance_preview_id`
  under which the editor stores its unsaved draft (see
  `Marquee.Branding.put_theme_preview/3`). While it is active the operator
  browses the viewer site as a member preview that renders the draft, and the
  plug exposes that draft as `conn.assigns.theme_preview` so dead-rendered
  pages and the root layout can use it. Any other `/admin*` request ends it.
  """

  import Plug.Conn

  alias Marquee.Accounts
  alias Marquee.Branding

  @appearance_editor_path "/admin/appearance"

  def init(opts), do: opts

  def call(conn, _opts) do
    scope = conn.assigns[:current_scope]
    org = conn.assigns[:organization] || (scope && scope.organization)

    cond do
      String.starts_with?(conn.request_path, "/admin") ->
        handle_admin_request(conn, scope, org)

      conn.query_params["preview"] == "member" && authorized?(scope, org) ->
        conn
        |> put_session(:member_preview_org_id, org.id)
        |> put_session(:member_preview_viewer_id, Ecto.UUID.generate())
        |> assign_theme_preview(scope, org)

      preview_invalid?(conn, scope, org) ->
        clear_preview(conn)

      true ->
        assign_theme_preview(conn, scope, org)
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

  @doc """
  Resolves the operator's unsaved appearance draft for the resolved organization.

  Returns the draft map stored by `Marquee.Branding.put_theme_preview/3` only
  when the session carries an appearance preview id and the current operator
  may preview `org`; otherwise `nil`.

      iex> MarqueeWeb.Plugs.MemberPreview.theme_preview(%{}, nil, nil)
      nil
  """
  def theme_preview(session, scope, org) do
    preview_id = session["appearance_preview_id"]

    if org && is_binary(preview_id) && authorized?(scope, org) do
      Branding.get_theme_preview(org, preview_id)
    end
  end

  # Opening the appearance editor starts (or keeps) an appearance preview
  # session; every other admin page ends it.
  defp handle_admin_request(%{request_path: @appearance_editor_path} = conn, scope, org) do
    if authorized?(scope, org), do: start_appearance_preview(conn, org), else: clear_preview(conn)
  end

  defp handle_admin_request(conn, _scope, _org), do: clear_preview(conn)

  defp start_appearance_preview(conn, org) do
    conn
    |> put_session(
      :appearance_preview_id,
      get_session(conn, :appearance_preview_id) || Ecto.UUID.generate()
    )
    |> put_session(:member_preview_viewer_id, member_preview_viewer_id(conn, org))
    |> put_session(:member_preview_org_id, org.id)
  end

  # Keep the operator's existing preview identity when it already targets this
  # organization so repeat editor visits do not look like a new viewer.
  defp member_preview_viewer_id(conn, org) do
    existing = get_session(conn, :member_preview_viewer_id)

    if get_session(conn, :member_preview_org_id) == org.id && is_binary(existing) do
      existing
    else
      Ecto.UUID.generate()
    end
  end

  defp assign_theme_preview(conn, scope, org) do
    case theme_preview(get_session(conn), scope, org) do
      nil -> conn
      draft -> assign(conn, :theme_preview, draft)
    end
  end

  defp preview_invalid?(conn, scope, org) do
    preview_org_id = get_session(conn, :member_preview_org_id)
    preview_org_id && (!authorized?(scope, org) || preview_org_id != org.id)
  end

  defp clear_preview(conn) do
    conn
    |> delete_session(:appearance_preview_id)
    |> delete_session(:member_preview_org_id)
    |> delete_session(:member_preview_viewer_id)
  end
end
