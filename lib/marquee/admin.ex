defmodule Marquee.Admin do
  @moduledoc """
  Platform-level admin context.

  Functions in this module intentionally query across all tenants. They are only
  callable from super admin interfaces, except explicit public demo discovery
  and platform maintenance dispatch. They must never expose another tenant's
  private data through tenant-scoped APIs.
  """

  import Ecto.Query, warn: false

  alias Marquee.Events
  alias Marquee.Pagination
  alias Marquee.Repo

  require Marquee.Otel
  alias Marquee.Accounts.{Membership, Organization, User}
  alias Marquee.Analytics.Event, as: AnalyticsEvent
  alias Marquee.Audit.Log, as: AuditLog

  alias Marquee.Billing.{
    Plan,
    PlatformPlan,
    PlatformSubscription,
    Subscription,
    ViewerSubscription
  }

  alias Marquee.Branding
  alias Marquee.Branding.Theme
  alias Marquee.Catalog
  alias Marquee.Catalog.HeroSlide
  alias Marquee.Catalog.Presets
  alias Marquee.Catalog.Row
  alias Marquee.Content.{Collection, CollectionItem, Episode, Season, Series, Tag, Video}
  alias Marquee.Engagement.{Favorite, Progress, WatchHistory, WatchlistItem}
  alias Marquee.Notifications.Notification
  alias Marquee.Streaming.LiveEvent
  alias Marquee.Viewers.{Viewer, ViewerToken}
  alias Marquee.Webhooks.Endpoint, as: WebhookEndpoint

  ## Organizations

  @doc """
  Finds the first active organization explicitly offering a public subscriber demo.

  Cross-tenant public discovery is intentional. Selection is deterministic by
  creation time and ID. Exempt from doctest — hits the database.
  """
  def get_subscriber_demo_organization do
    Organization
    |> where([org], is_nil(org.deleted_at))
    |> where([org], fragment("?->'subscriber_demo' = 'true'::jsonb", org.features))
    |> order_by([org], asc: org.inserted_at, asc: org.id)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  @doc """
  Lists a bounded page of organization IDs with synthetic demo viewers.

  Cross-tenant maintenance discovery is intentional. Includes disabled demo
  organizations so their ephemeral data is still cleaned up. Supports
  `:after_id` keyset pagination and `:per_page` (default and maximum 100).
  Exempt from doctest — hits the database.
  """
  def list_subscriber_demo_cleanup_organization_ids(opts \\ []) do
    limit = opts |> Keyword.get(:per_page, 100) |> max(1) |> min(100)

    query =
      Viewer
      |> where([viewer], fragment("?->'subscriber_demo' = 'true'::jsonb", viewer.metadata))
      |> select([viewer], viewer.organization_id)
      |> distinct(true)
      |> order_by([viewer], asc: viewer.organization_id)
      |> limit(^limit)

    query =
      case Keyword.get(opts, :after_id) do
        nil -> query
        id -> where(query, [viewer], viewer.organization_id > ^id)
      end

    Repo.all(query)
  end

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
    include_deleted = Keyword.get(opts, :include_deleted, false)

    Organization
    |> where([o], is_nil(o.demo_kind))
    |> apply_soft_delete_filter(include_deleted)
    |> apply_org_search(search)
    |> apply_org_order(order)
    |> Pagination.paginate(opts)
  end

  @doc "System maintenance: returns a bounded keyset page of active organizations for a reviewed hostname snapshot. Requires database access."
  def tenant_domain_candidates(cutoff, opts \\ []) do
    size = opts |> Keyword.get(:per_page, 100) |> min(100) |> max(1)

    query =
      from o in Organization,
        where: is_nil(o.deleted_at) and is_nil(o.demo_kind),
        where: o.inserted_at < ^cutoff,
        order_by: [asc: o.inserted_at, asc: o.id]

    query =
      case Keyword.get(opts, :slugs) do
        nil -> query
        slugs -> where(query, [o], o.slug in ^slugs)
      end

    query =
      case Keyword.get(opts, :after) do
        nil ->
          query

        {time, id} ->
          where(query, [o], o.inserted_at > ^time or (o.inserted_at == ^time and o.id > ^id))
      end

    {results, rest} = query |> limit(^(size + 1)) |> Repo.all() |> Enum.split(size)
    last = List.last(results)
    %{results: results, next_cursor: if(rest != [], do: {last.inserted_at, last.id})}
  end

  defp apply_soft_delete_filter(query, true), do: query
  defp apply_soft_delete_filter(query, false), do: where(query, [o], is_nil(o.deleted_at))

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

  Accepts an optional scope so the broadcast + audit subscriber can
  attribute the action to the acting super admin. Platform-level
  mutation: the scope has no organization.

  Returns `{:ok, organization}` or `{:error, :validation, changeset}`.

  Cross-tenant write — intentional.

  Exempt from doctest — hits the database.
  """
  def create_organization(scope \\ nil, attrs) do
    Marquee.Otel.with_span "marquee.admin.create_organization" do
      preset_name =
        Map.get(attrs, "preset_name") || Map.get(attrs, :preset_name) || "catalog_cinema"

      result =
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

              seed_catalog_defaults(org, preset_name)

              Events.broadcast_platform(scope, {:organization_created, org})
              org

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)

      case result do
        {:ok, org} -> {:ok, org}
        {:error, changeset} -> {:error, :validation, changeset}
      end
    end
  end

  # Seed a Layout and default Row records for a freshly-created org so
  # the viewer homepage has something to render from day one. Unknown
  # presets fall back to catalog_cinema; seed errors are swallowed so a
  # bad preset can't roll back the org create.
  defp seed_catalog_defaults(org, preset_name) do
    name =
      case Presets.get(preset_name) do
        {:ok, _} -> preset_name
        {:error, :not_found} -> "catalog_cinema"
      end

    {:ok, _layout} = Catalog.get_or_create_layout(%{org | preset_name: name})

    scope = %Marquee.Accounts.Scope{organization: org}
    _ = Catalog.seed_rows_from_preset_if_empty(scope, name)

    :ok
  end

  @doc """
  Updates an organization.

  Returns `{:ok, organization}` or `{:error, changeset}`.

  Cross-tenant write — intentional.

  Exempt from doctest — hits the database.
  """
  def update_organization(%Organization{} = organization, attrs) do
    case organization |> Organization.changeset(attrs) |> Repo.update() do
      {:ok, org} -> {:ok, org}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Deletes an organization.

  Foreign key cascades handle associated data cleanup via `on_delete: :delete_all`.

  Returns `{:ok, organization}` or `{:error, changeset}`.

  Cross-tenant write — intentional.

  Exempt from doctest — hits the database.
  """
  def delete_organization(%Organization{} = organization) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case organization |> Ecto.Changeset.change(deleted_at: now) |> Repo.update() do
      {:ok, org} -> {:ok, org}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Restores a soft-deleted organization by clearing `deleted_at`.

  Returns `{:ok, organization}` or `{:error, changeset}`.

  Cross-tenant write — intentional.

  Exempt from doctest — hits the database.
  """
  def restore_organization(%Organization{} = organization) do
    case organization |> Ecto.Changeset.change(deleted_at: nil) |> Repo.update() do
      {:ok, org} -> {:ok, org}
      {:error, changeset} -> {:error, :validation, changeset}
    end
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
      case %Membership{}
           |> Membership.changeset(%{
             user_id: user.id,
             organization_id: organization.id,
             role: :owner
           })
           |> Repo.insert() do
        {:ok, membership} -> {:ok, membership}
        {:error, changeset} -> {:error, :validation, changeset}
      end
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
    |> where([u], is_nil(u.demo_kind))
    |> apply_user_search(search)
    |> order_by(asc: :email)
    |> Pagination.paginate(opts)
  end

  defp apply_user_search(query, nil), do: query

  defp apply_user_search(query, term) do
    pattern = "%#{term}%"
    where(query, [u], ilike(u.email, ^pattern))
  end

  @doc """
  Grants super admin status to a user.

  Accepts an optional scope so the broadcast + audit subscriber can
  attribute the action to the acting super admin. Platform-level
  mutation: the scope has no organization.

  Returns `{:ok, user}` or `{:error, changeset}`.

  Exempt from doctest — hits the database.
  """
  def grant_super_admin(scope \\ nil, %User{} = user) do
    with {:ok, user} <- user |> User.admin_changeset(%{is_super_admin: true}) |> Repo.update() do
      Events.broadcast_platform(scope, {:super_admin_granted, user})
      {:ok, user}
    end
  end

  @doc """
  Revokes super admin status from a user.

  Accepts an optional scope so the broadcast + audit subscriber can
  attribute the action to the acting super admin. Platform-level
  mutation: the scope has no organization.

  Returns `{:ok, user}` or `{:error, changeset}`.

  Exempt from doctest — hits the database.
  """
  def revoke_super_admin(scope \\ nil, %User{} = user) do
    with {:ok, user} <- user |> User.admin_changeset(%{is_super_admin: false}) |> Repo.update() do
      Events.broadcast_platform(scope, {:super_admin_revoked, user})
      {:ok, user}
    end
  end

  ## Platform stats

  @doc """
  Returns platform-wide summary stats across all tenants.

  Cross-tenant aggregation — intentional.

  Exempt from doctest — hits the database.
  """
  def platform_stats do
    %{
      total_organizations:
        Repo.aggregate(from(o in Organization, where: is_nil(o.demo_kind)), :count),
      total_users: Repo.aggregate(from(u in User, where: is_nil(u.demo_kind)), :count),
      total_videos:
        Repo.aggregate(
          from(v in Video,
            join: o in Organization,
            on: o.id == v.organization_id,
            where: is_nil(o.demo_kind)
          ),
          :count
        ),
      total_subscribers: active_subscriber_count()
    }
  end

  defp active_subscriber_count do
    Viewer
    |> join(:inner, [v], o in Organization, on: o.id == v.organization_id)
    |> where([v, o], v.subscription_status in ["active", "trial"] and is_nil(o.demo_kind))
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
  Returns the count of live events for an organization.

  Cross-tenant query — intentional.

  Exempt from doctest — hits the database.
  """
  def live_event_count(%Organization{id: org_id}) do
    LiveEvent
    |> where(organization_id: ^org_id)
    |> where([e], is_nil(e.deleted_at))
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

  ## Analytics

  @doc """
  System-level: crosses tenants.

  Returns platform-wide financial and viewer overview stats across all tenants.

  Platform MRR is the sum of active PlatformSubscription plan amounts.
  Viewer fee revenue is the sum across all active ViewerSubscriptions of
  `plan.amount * application_fee_percent / 100`.

  Exempt from doctest — hits the database.
  """
  def platform_overview do
    Marquee.Otel.with_span "marquee.admin.platform_overview" do
      total_orgs =
        Repo.aggregate(
          from(o in Organization, where: is_nil(o.deleted_at) and is_nil(o.demo_kind)),
          :count
        )

      total_viewers =
        Repo.aggregate(
          from(v in Viewer,
            join: o in Organization,
            on: o.id == v.organization_id,
            where: is_nil(o.demo_kind)
          ),
          :count
        )

      platform_mrr_cents = compute_platform_mrr()
      viewer_fee_revenue_cents = compute_viewer_fee_revenue()

      %{
        total_orgs: total_orgs,
        total_viewers: total_viewers,
        platform_mrr_cents: platform_mrr_cents,
        viewer_fee_revenue_cents: viewer_fee_revenue_cents
      }
    end
  end

  defp compute_platform_mrr do
    from(ps in PlatformSubscription,
      join: pp in PlatformPlan,
      on: ps.platform_plan_id == pp.id,
      where: ps.status == :active,
      select: sum(pp.amount)
    )
    |> Repo.one() || 0
  end

  defp compute_viewer_fee_revenue do
    from(vs in ViewerSubscription,
      join: p in Plan,
      on: vs.plan_id == p.id,
      where: vs.status == "active",
      select: sum(fragment("? * ? / 100.0", p.amount, vs.application_fee_percent))
    )
    |> Repo.one()
    |> case do
      nil -> 0
      val -> val |> Decimal.to_integer()
    end
  end

  @doc """
  System-level: crosses tenants.

  Returns paginated organizations with health metrics for the super admin dashboard.

  Each result is a map:
  `%{id, name, platform_plan_name, subscriber_count, mrr_cents, video_count, active_viewers_last_7d, status}`

  Options:
  - `:page` — page number (default 1)
  - `:per_page` — results per page (default 25, max 100)
  - `:search` — ILIKE filter on org name
  - `:sort_by` — `:name | :mrr | :subscribers | :videos` (default `:name`)
  - `:sort_dir` — `:asc | :desc` (default `:asc`)

  Exempt from doctest — hits the database.
  """
  def list_organizations_with_health(opts \\ []) do
    Marquee.Otel.with_span "marquee.admin.list_organizations_with_health" do
      search = Keyword.get(opts, :search)
      sort_by = Keyword.get(opts, :sort_by, :name)
      sort_dir = Keyword.get(opts, :sort_dir, :asc)
      {page, per_page} = Pagination.normalize_opts(opts)

      seven_days_ago = DateTime.utc_now() |> DateTime.add(-7, :day)

      base_query =
        from o in Organization,
          as: :org,
          where: is_nil(o.deleted_at) and is_nil(o.demo_kind),
          left_join: ps in PlatformSubscription,
          as: :platform_sub,
          on: ps.organization_id == o.id and ps.status == :active,
          left_join: pp in PlatformPlan,
          as: :platform_plan,
          on: pp.id == ps.platform_plan_id,
          left_join: sub in Viewer,
          as: :subscription,
          on:
            sub.organization_id == o.id and
              sub.subscription_status in ["active", "trial"],
          left_join: v in Video,
          as: :video,
          on: v.organization_id == o.id,
          left_join: p in Progress,
          as: :progress,
          on: p.organization_id == o.id and p.updated_at >= ^seven_days_ago,
          group_by: [o.id, o.name, pp.id, pp.name, pp.amount, ps.status],
          select: %{
            id: o.id,
            name: o.name,
            inserted_at: o.inserted_at,
            platform_plan_name: pp.name,
            subscriber_count: count(sub.id, :distinct),
            mrr_cents: coalesce(pp.amount, 0),
            video_count: count(v.id, :distinct),
            active_viewers_last_7d: count(p.viewer_id, :distinct),
            status: ps.status
          }

      filtered_query = apply_health_search(base_query, search)
      sorted_query = apply_health_sort(filtered_query, sort_by, sort_dir)

      count_query =
        from o in Organization,
          where: is_nil(o.deleted_at) and is_nil(o.demo_kind),
          select: count()

      count_query = apply_org_search_simple(count_query, search)
      total = Repo.one(count_query) || 0

      results =
        sorted_query
        |> limit(^per_page)
        |> offset(^((page - 1) * per_page))
        |> Repo.all()

      %{
        results: results,
        page: page,
        per_page: per_page,
        total: total,
        total_pages: max(ceil(total / per_page), 1)
      }
    end
  end

  defp apply_health_search(query, nil), do: query

  defp apply_health_search(query, term) do
    pattern = "%#{term}%"
    where(query, [o], ilike(o.name, ^pattern))
  end

  defp apply_org_search_simple(query, nil), do: query

  defp apply_org_search_simple(query, term) do
    pattern = "%#{term}%"
    where(query, [o], ilike(o.name, ^pattern))
  end

  defp apply_health_sort(query, :name, :asc),
    do: order_by(query, [org: o], asc: o.name)

  defp apply_health_sort(query, :name, :desc),
    do: order_by(query, [org: o], desc: o.name)

  defp apply_health_sort(query, :mrr, dir) do
    order_by(query, [platform_plan: pp], [{^dir, coalesce(pp.amount, 0)}])
  end

  defp apply_health_sort(query, :subscribers, dir) do
    order_by(query, [subscription: sub], [{^dir, count(sub.id, :distinct)}])
  end

  defp apply_health_sort(query, :videos, dir) do
    order_by(query, [video: v], [{^dir, count(v.id, :distinct)}])
  end

  defp apply_health_sort(query, _, _), do: order_by(query, [org: o], asc: o.name)

  @doc """
  System-level: crosses tenants.

  Returns a daily series of total platform MRR (in cents) between two dates,
  inclusive. Each entry is `%{date: ~D[...], mrr_cents: integer}`.

  MRR is computed as the sum of active PlatformSubscription plan amounts on
  each day — a subscription is counted for a day if its `inserted_at` is on
  or before that day and it has not been canceled before that day.

  Exempt from doctest — hits the database.
  """
  def list_daily_platform_mrr(from_date, to_date) do
    Marquee.Otel.with_span "marquee.admin.list_daily_platform_mrr" do
      dates = date_range(from_date, to_date)

      subscriptions =
        from(ps in PlatformSubscription,
          join: pp in PlatformPlan,
          on: pp.id == ps.platform_plan_id,
          where: ps.status == :active,
          select: %{amount: pp.amount, inserted_at: ps.inserted_at, canceled_at: ps.canceled_at}
        )
        |> Repo.all()

      Enum.map(dates, fn date ->
        %{date: date, mrr_cents: mrr_for_day(subscriptions, date)}
      end)
    end
  end

  defp mrr_for_day(subscriptions, date) do
    day_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

    Enum.reduce(subscriptions, 0, fn sub, acc ->
      if subscription_active_on?(sub, day_start), do: acc + sub.amount, else: acc
    end)
  end

  defp subscription_active_on?(sub, day_start) do
    DateTime.compare(sub.inserted_at, day_start) != :gt and
      (is_nil(sub.canceled_at) or DateTime.compare(sub.canceled_at, day_start) == :gt)
  end

  @doc """
  System-level: crosses tenants.

  Returns a daily count of new organization signups between two dates, inclusive.
  Each entry is `%{date: ~D[...], count: integer}`.

  Exempt from doctest — hits the database.
  """
  def list_new_org_signups(from_date, to_date) do
    Marquee.Otel.with_span "marquee.admin.list_new_org_signups" do
      from_dt = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")
      to_dt = DateTime.new!(to_date, ~T[23:59:59], "Etc/UTC")

      rows =
        from(o in Organization,
          where: o.inserted_at >= ^from_dt and o.inserted_at <= ^to_dt,
          group_by: fragment("DATE(? AT TIME ZONE 'UTC')", o.inserted_at),
          select: {fragment("DATE(? AT TIME ZONE 'UTC')", o.inserted_at), count()}
        )
        |> Repo.all()
        |> Map.new()

      date_range(from_date, to_date)
      |> Enum.map(fn date ->
        %{date: date, count: Map.get(rows, date, 0)}
      end)
    end
  end

  defp date_range(from_date, to_date) do
    Date.range(from_date, to_date) |> Enum.to_list()
  end

  ## Data export

  @doc """
  Exports all tenant-scoped data for an organization.

  Returns a map with all records including soft-deleted ones.
  Intentionally does NOT filter by `deleted_at` — exports include everything.

  Cross-tenant query — intentional.

  Exempt from doctest — hits the database.
  """
  def export_organization_data(%Organization{} = organization) do
    Marquee.Otel.with_span "marquee.admin.export_organization_data",
                           %{"marquee.org.id" => organization.id} do
      org_id = organization.id

      %{
        organization: organization,
        tenant_domain: Marquee.TenantDomains.get_domain(organization),
        memberships:
          Repo.all(from(m in Membership, where: m.organization_id == ^org_id, preload: [:user])),
        videos: Repo.all(from(v in Video, where: v.organization_id == ^org_id)),
        collections: Repo.all(from(c in Collection, where: c.organization_id == ^org_id)),
        collection_items:
          Repo.all(from(ci in CollectionItem, where: ci.organization_id == ^org_id)),
        tags: Repo.all(from(t in Tag, where: t.organization_id == ^org_id)),
        rows: Repo.all(from(r in Row, where: r.organization_id == ^org_id)),
        hero_slides: Repo.all(from(hs in HeroSlide, where: hs.organization_id == ^org_id)),
        plans: Repo.all(from(p in Plan, where: p.organization_id == ^org_id)),
        subscriptions: Repo.all(from(s in Subscription, where: s.organization_id == ^org_id)),
        theme: Repo.get_by(Theme, organization_id: org_id),
        webhook_endpoints:
          Repo.all(from(w in WebhookEndpoint, where: w.organization_id == ^org_id)),
        notifications: Repo.all(from(n in Notification, where: n.organization_id == ^org_id)),
        audit_logs: Repo.all(from(a in AuditLog, where: a.organization_id == ^org_id)),
        watchlist_items: Repo.all(from(w in WatchlistItem, where: w.organization_id == ^org_id)),
        favorites: Repo.all(from(f in Favorite, where: f.organization_id == ^org_id)),
        watch_histories: Repo.all(from(w in WatchHistory, where: w.organization_id == ^org_id)),
        progresses: Repo.all(from(p in Progress, where: p.organization_id == ^org_id)),
        analytics_events:
          Repo.all(from(e in AnalyticsEvent, where: e.organization_id == ^org_id)),
        viewers: Repo.all(from(v in Viewer, where: v.organization_id == ^org_id)),
        viewer_tokens:
          Repo.all(
            from(t in ViewerToken,
              join: v in Viewer,
              on: t.viewer_id == v.id,
              where: v.organization_id == ^org_id
            )
          ),
        series: Repo.all(from(s in Series, where: s.organization_id == ^org_id)),
        seasons: Repo.all(from(s in Season, where: s.organization_id == ^org_id)),
        episodes: Repo.all(from(e in Episode, where: e.organization_id == ^org_id)),
        platform_subscription:
          Repo.get_by(Marquee.Billing.PlatformSubscription, organization_id: org_id)
      }
    end
  end

  @doc "Finds the configured demo service organization, optionally locking its allocation row. Cross-tenant administrative lookup."
  def admin_demo_host(host, lock? \\ false) do
    query = from o in Organization, where: o.custom_domain == ^host
    query = if lock?, do: lock(query, "FOR UPDATE"), else: query
    Repo.one(query)
  end

  @doc "Checks the permanent consumed-entry tombstone. Cross-tenant administrative lookup."
  def admin_demo_entry_consumed?(hash),
    do: Repo.exists?(from o in Organization, where: o.demo_entry_key_hash == ^hash)

  @doc "Counts currently active sandbox sessions under the service-host lock. Cross-tenant administrative query."
  def active_admin_demo_count(now) do
    Repo.aggregate(
      from(s in Marquee.AdminDemo.Session,
        where: is_nil(s.revoked_at) and s.expires_at > ^now
      ),
      :count
    )
  end

  @doc "Selects a bounded batch of expired demo sessions for scoped cleanup. Cross-tenant administrative query."
  def expired_admin_demo_sessions(now, limit) do
    purge_before = DateTime.add(now, -86_400)
    retention_before = DateTime.add(now, -30 * 86_400)

    Repo.all(
      from s in Marquee.AdminDemo.Session,
        where: s.expires_at <= ^now,
        where:
          is_nil(s.revoked_at) or (is_nil(s.purged_at) and s.expires_at <= ^purge_before) or
            s.expires_at <= ^retention_before,
        order_by: [asc: s.expires_at, asc: s.id],
        limit: ^limit
    )
  end

  @doc "Returns a bounded customer-only page for platform automation. Cross-tenant administrative query."
  def customer_organization_ids(after_id \\ nil) do
    query =
      from o in Organization,
        where: is_nil(o.demo_kind) and is_nil(o.deleted_at),
        order_by: o.id,
        limit: 100,
        select: o.id

    query = if after_id, do: where(query, [o], o.id > ^after_id), else: query
    Repo.all(query)
  end

  @doc "Returns a bounded customer-only page of due podcast feeds. Cross-tenant administrative query."
  def due_customer_podcast_ids(cutoff, failure_limit, after_id \\ nil) do
    query =
      from s in Marquee.Podcasts.Show,
        join: o in Organization,
        on: o.id == s.organization_id,
        where: is_nil(o.demo_kind) and is_nil(o.deleted_at),
        where: s.source_type == "feed_import" and is_nil(s.deleted_at) and s.published == true,
        where:
          s.remote_consecutive_failures < ^failure_limit and
            (is_nil(s.remote_last_synced_at) or s.remote_last_synced_at < ^cutoff),
        order_by: s.id,
        limit: 100,
        select: s.id

    query = if after_id, do: where(query, [s], s.id > ^after_id), else: query
    Repo.all(query)
  end
end
