defmodule Bobine.Admin do
  @moduledoc """
  Platform-level admin context.

  Functions in this module intentionally query across all tenants. They are only
  callable from super admin interfaces and must never be exposed through
  tenant-scoped APIs.
  """

  import Ecto.Query, warn: false

  alias Bobine.Repo
  alias Bobine.Accounts.{Organization, User, Membership}
  alias Bobine.Branding
  alias Bobine.Content.Video
  alias Bobine.Billing.Subscription

  ## Organizations

  @doc """
  Lists all organizations across all tenants.

  Cross-tenant query — intentional. Supports optional filters:
  - `:search` — filters by name or slug (case-insensitive substring match)
  - `:order_by` — `:name` (default) or `:inserted_at`

  Exempt from doctest — hits the database.
  """
  def list_organizations(opts \\ []) do
    search = Keyword.get(opts, :search)
    order = Keyword.get(opts, :order_by, :name)

    Organization
    |> apply_org_search(search)
    |> apply_org_order(order)
    |> Repo.all()
  end

  defp apply_org_search(query, nil), do: query

  defp apply_org_search(query, term) do
    pattern = "%#{term}%"
    where(query, [o], ilike(o.name, ^pattern) or ilike(o.slug, ^pattern))
  end

  defp apply_org_order(query, :inserted_at), do: order_by(query, desc: :inserted_at)
  defp apply_org_order(query, _), do: order_by(query, asc: :name)

  @doc """
  Gets a single organization by ID with theme preloaded.

  Raises `Ecto.NoResultsError` if no organization exists with the given ID.

  Cross-tenant query — intentional.

  Exempt from doctest — hits the database.
  """
  def get_organization!(id) do
    Organization
    |> Repo.get!(id)
    |> Repo.preload(:themes)
  end

  @doc """
  Creates a new organization and a default theme for it.

  Returns `{:ok, organization}` or `{:error, changeset}`.

  Cross-tenant write — intentional.

  Exempt from doctest — hits the database.
  """
  def create_organization(attrs) do
    Repo.transaction(fn ->
      changeset = Organization.changeset(%Organization{}, attrs)

      case Repo.insert(changeset) do
        {:ok, org} ->
          {:ok, _theme} =
            Branding.create_theme(%{
              organization_id: org.id,
              background: "#0f0f0f",
              surface: "#1c1c1c",
              text_primary: "#ffffff",
              text_secondary: "#aaaaaa",
              brand_primary: "#1a73e8",
              brand_secondary: "#174ea6",
              accent: "#e8a21a",
              font_heading: "Inter",
              font_body: "Inter",
              border_radius: "0.5rem",
              card_border_radius: "0.75rem"
            })

          org

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Updates an organization.

  Returns `{:ok, organization}` or `{:error, changeset}`.

  Cross-tenant write — intentional.

  Exempt from doctest — hits the database.
  """
  def update_organization(%Organization{} = organization, attrs) do
    organization
    |> Organization.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an organization.

  Foreign key cascades handle associated data cleanup via `on_delete: :delete_all`.

  Returns `{:ok, organization}` or `{:error, changeset}`.

  Cross-tenant write — intentional.

  Exempt from doctest — hits the database.
  """
  def delete_organization(%Organization{} = organization) do
    Repo.delete(organization)
  end

  ## Memberships

  @doc """
  Creates an owner membership for a user in an organization.

  Returns `{:ok, membership}` or `{:error, :already_has_owner}` if the org
  already has an owner, or `{:error, changeset}` on validation failure.

  Cross-tenant write — intentional.

  Exempt from doctest — hits the database.
  """
  def create_owner_membership(%Organization{} = organization, %User{} = user) do
    if owner_exists?(organization) do
      {:error, :already_has_owner}
    else
      %Membership{}
      |> Membership.changeset(%{
        user_id: user.id,
        organization_id: organization.id,
        role: :owner
      })
      |> Repo.insert()
    end
  end

  defp owner_exists?(%Organization{id: org_id}) do
    Repo.exists?(from m in Membership, where: m.organization_id == ^org_id and m.role == :owner)
  end

  ## Users

  @doc """
  Lists all users with super admin status.

  Cross-tenant query — intentional.

  Exempt from doctest — hits the database.
  """
  def list_super_admins do
    User
    |> where(is_super_admin: true)
    |> Repo.all()
  end

  @doc """
  Lists all users across the platform with their membership counts.

  Cross-tenant query — intentional.

  Exempt from doctest — hits the database.
  """
  def list_users(opts \\ []) do
    search = Keyword.get(opts, :search)

    User
    |> apply_user_search(search)
    |> order_by(asc: :email)
    |> Repo.all()
  end

  defp apply_user_search(query, nil), do: query

  defp apply_user_search(query, term) do
    pattern = "%#{term}%"
    where(query, [u], ilike(u.email, ^pattern))
  end

  @doc """
  Grants super admin status to a user.

  Returns `{:ok, user}` or `{:error, changeset}`.

  Exempt from doctest — hits the database.
  """
  def grant_super_admin(%User{} = user) do
    user
    |> User.admin_changeset(%{is_super_admin: true})
    |> Repo.update()
  end

  @doc """
  Revokes super admin status from a user.

  Returns `{:ok, user}` or `{:error, changeset}`.

  Exempt from doctest — hits the database.
  """
  def revoke_super_admin(%User{} = user) do
    user
    |> User.admin_changeset(%{is_super_admin: false})
    |> Repo.update()
  end

  ## Platform stats

  @doc """
  Returns platform-wide summary stats across all tenants.

  Cross-tenant aggregation — intentional.

  Exempt from doctest — hits the database.
  """
  def platform_stats do
    %{
      total_organizations: Repo.aggregate(Organization, :count),
      total_users: Repo.aggregate(User, :count),
      total_videos: Repo.aggregate(Video, :count),
      total_subscribers: active_subscriber_count()
    }
  end

  defp active_subscriber_count do
    Subscription
    |> where(status: :active)
    |> Repo.aggregate(:count)
  end

  ## Membership queries for show page

  @doc """
  Lists all memberships for an organization with users preloaded.

  Cross-tenant query — intentional (called from super admin show page).

  Exempt from doctest — hits the database.
  """
  def list_memberships(%Organization{id: org_id}) do
    Membership
    |> where(organization_id: ^org_id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Returns the count of videos for an organization.

  Cross-tenant query — intentional.

  Exempt from doctest — hits the database.
  """
  def video_count(%Organization{id: org_id}) do
    Video
    |> where(organization_id: ^org_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns the count of active subscribers for an organization.

  Cross-tenant query — intentional.

  Exempt from doctest — hits the database.
  """
  def subscriber_count(%Organization{id: org_id}) do
    Subscription
    |> where(organization_id: ^org_id, status: :active)
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns the membership count for an organization.

  Cross-tenant query — intentional.

  Exempt from doctest — hits the database.
  """
  def member_count(%Organization{id: org_id}) do
    Membership
    |> where(organization_id: ^org_id)
    |> Repo.aggregate(:count)
  end
end
