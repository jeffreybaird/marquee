defmodule Bobine.Audit do
  @moduledoc "Append-only audit log for all mutating operations."

  import Ecto.Query

  require Bobine.Otel

  alias Bobine.Accounts.Organization
  alias Bobine.Audit.Log
  alias Bobine.Cache
  alias Bobine.Repo

  @default_per_page 50
  @max_per_page 100
  @filter_options_ttl :timer.minutes(5)

  @doc """
  Logs an auditable action.

  scope can be a %Scope{} or nil (for system-level actions).
  action is a string like "video.created".
  resource is the struct that was acted on.
  changes is a map of what changed (can be empty for creates/deletes).
  """
  def log(scope, action, resource, changes \\ %{}) do
    attrs = %{
      organization_id: org_id_from_scope(scope),
      user_id: user_id_from_scope(scope),
      action: action,
      resource_type: resource_type(resource),
      resource_id: resource_id(resource),
      changes: changes,
      metadata: build_metadata(scope)
    }

    %Log{}
    |> Log.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists audit logs for a specific organization with optional filters and cursor pagination.

  Filters (all optional):
  - `action` — exact match on action string
  - `user_id` — exact match on user UUID
  - `resource_type` — exact match on resource type string
  - `from` — `Date` or `DateTime`, inclusive lower bound on `inserted_at`
  - `to` — `Date` or `DateTime`, inclusive upper bound on `inserted_at`
  - `search` — ILIKE match on action OR resource_id

  Options:
  - `:cursor` — `{inserted_at, id}` tuple for cursor pagination (nil for first page)
  - `:per_page` — number of results (default 50, max 100)

  Returns `%{results: [log], next_cursor: cursor_or_nil}`.

  Exempt from doctest — requires database.
  """
  def list_for_organization(%Organization{id: org_id}, filters \\ %{}, opts \\ []) do
    Bobine.Otel.with_span "bobine.audit.list_for_organization",
                          %{"bobine.org.id" => org_id} do
      per_page = min(Keyword.get(opts, :per_page, @default_per_page), @max_per_page)
      cursor = Keyword.get(opts, :cursor, nil)

      query =
        Log
        |> where(organization_id: ^org_id)
        |> apply_filters(filters)
        |> apply_cursor(cursor)
        |> order_by([l], desc: l.inserted_at, desc: l.id)
        |> limit(^(per_page + 1))
        |> preload(:user)

      rows = Repo.all(query)
      {results, next_cursor} = paginate_results(rows, per_page)

      %{results: results, next_cursor: next_cursor}
    end
  end

  @doc """
  Lists audit logs across all organizations with optional filters and cursor pagination.

  System-level: crosses tenants. Use only from super admin contexts.

  Accepts the same filters as `list_for_organization/3`, plus:
  - `organization_id` — filter to a specific org UUID

  Returns `%{results: [log], next_cursor: cursor_or_nil}`.

  Exempt from doctest — requires database.
  """
  def list_all(filters \\ %{}, opts \\ []) do
    Bobine.Otel.with_span "bobine.audit.list_all", %{} do
      per_page = min(Keyword.get(opts, :per_page, @default_per_page), @max_per_page)
      cursor = Keyword.get(opts, :cursor, nil)

      query =
        Log
        |> apply_filters(filters)
        |> apply_org_filter(filters)
        |> apply_cursor(cursor)
        |> order_by([l], desc: l.inserted_at, desc: l.id)
        |> limit(^(per_page + 1))
        |> preload([:user, :organization])

      rows = Repo.all(query)
      {results, next_cursor} = paginate_results(rows, per_page)

      %{results: results, next_cursor: next_cursor}
    end
  end

  @doc """
  Returns filter options for the audit log UI for a given organization.

  Cached per-org with a 5-minute TTL.

  Returns `%{actions: [...], actors: [...user structs], resource_types: [...]}`.

  Exempt from doctest — requires database and cache.
  """
  def get_filter_options(%Organization{id: org_id} = _org) do
    Cache.fetch("audit_filter_options:#{org_id}", [ttl: @filter_options_ttl], fn ->
      actions =
        Log
        |> where(organization_id: ^org_id)
        |> select([l], l.action)
        |> distinct(true)
        |> order_by([l], l.action)
        |> Repo.all()

      resource_types =
        Log
        |> where(organization_id: ^org_id)
        |> select([l], l.resource_type)
        |> distinct(true)
        |> order_by([l], l.resource_type)
        |> Repo.all()

      user_ids =
        Log
        |> where(organization_id: ^org_id)
        |> where([l], not is_nil(l.user_id))
        |> select([l], l.user_id)
        |> distinct(true)
        |> Repo.all()

      actors = load_users_by_ids(user_ids)

      %{actions: actions, actors: actors, resource_types: resource_types}
    end)
  end

  @doc """
  Returns filter options for the global audit log UI (super admin).

  Cross-tenant. Cached globally with a 5-minute TTL.

  Returns `%{actions: [...], actors: [...user structs], resource_types: [...], organizations: [...org structs]}`.

  Exempt from doctest — requires database and cache.
  """
  def get_filter_options_global do
    Cache.fetch("audit_filter_options:global", [ttl: @filter_options_ttl], fn ->
      actions =
        Log
        |> select([l], l.action)
        |> distinct(true)
        |> order_by([l], l.action)
        |> Repo.all()

      resource_types =
        Log
        |> select([l], l.resource_type)
        |> distinct(true)
        |> order_by([l], l.resource_type)
        |> Repo.all()

      user_ids =
        Log
        |> where([l], not is_nil(l.user_id))
        |> select([l], l.user_id)
        |> distinct(true)
        |> Repo.all()

      actors = load_users_by_ids(user_ids)

      org_ids =
        Log
        |> where([l], not is_nil(l.organization_id))
        |> select([l], l.organization_id)
        |> distinct(true)
        |> Repo.all()

      organizations = load_orgs_by_ids(org_ids)

      %{
        actions: actions,
        actors: actors,
        resource_types: resource_types,
        organizations: organizations
      }
    end)
  end

  defp apply_filters(query, filters) do
    query
    |> filter_by_action(filters[:action])
    |> filter_by_user(filters[:user_id])
    |> filter_by_resource_type(filters[:resource_type])
    |> filter_by_from(filters[:from])
    |> filter_by_to(filters[:to])
    |> filter_by_search(filters[:search])
  end

  defp filter_by_action(query, nil), do: query
  defp filter_by_action(query, ""), do: query
  defp filter_by_action(query, action), do: where(query, [l], l.action == ^action)

  defp filter_by_user(query, nil), do: query
  defp filter_by_user(query, ""), do: query
  defp filter_by_user(query, user_id), do: where(query, [l], l.user_id == ^user_id)

  defp filter_by_resource_type(query, nil), do: query
  defp filter_by_resource_type(query, ""), do: query

  defp filter_by_resource_type(query, rt),
    do: where(query, [l], l.resource_type == ^rt)

  defp filter_by_from(query, nil), do: query

  defp filter_by_from(query, %Date{} = date) do
    dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    where(query, [l], l.inserted_at >= ^dt)
  end

  defp filter_by_from(query, %DateTime{} = dt), do: where(query, [l], l.inserted_at >= ^dt)

  defp filter_by_to(query, nil), do: query

  defp filter_by_to(query, %Date{} = date) do
    dt = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
    where(query, [l], l.inserted_at <= ^dt)
  end

  defp filter_by_to(query, %DateTime{} = dt), do: where(query, [l], l.inserted_at <= ^dt)

  defp filter_by_search(query, nil), do: query
  defp filter_by_search(query, ""), do: query

  defp filter_by_search(query, search) do
    pattern = "%#{search}%"

    where(
      query,
      [l],
      ilike(l.action, ^pattern) or ilike(fragment("?::text", l.resource_id), ^pattern)
    )
  end

  defp apply_org_filter(query, %{organization_id: org_id}) when is_binary(org_id) do
    where(query, [l], l.organization_id == ^org_id)
  end

  defp apply_org_filter(query, _), do: query

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, {inserted_at, id}) do
    where(
      query,
      [l],
      l.inserted_at < ^inserted_at or (l.inserted_at == ^inserted_at and l.id < ^id)
    )
  end

  defp paginate_results(rows, per_page) when length(rows) > per_page do
    results = Enum.take(rows, per_page)
    last = List.last(results)
    next_cursor = {last.inserted_at, last.id}
    {results, next_cursor}
  end

  defp paginate_results(rows, _per_page), do: {rows, nil}

  defp load_users_by_ids([]), do: []

  defp load_users_by_ids(user_ids) do
    Bobine.Accounts.User
    |> where([u], u.id in ^user_ids)
    |> Repo.all()
  end

  defp load_orgs_by_ids([]), do: []

  defp load_orgs_by_ids(org_ids) do
    Bobine.Accounts.Organization
    |> where([o], o.id in ^org_ids)
    |> Repo.all()
  end

  defp org_id_from_scope(nil), do: nil
  defp org_id_from_scope(%{organization: nil}), do: nil
  defp org_id_from_scope(%{organization: org}), do: org.id

  defp user_id_from_scope(nil), do: nil
  defp user_id_from_scope(%{user: nil}), do: nil
  defp user_id_from_scope(%{user: user}), do: user.id

  defp resource_type(%{__struct__: module}), do: module |> Module.split() |> List.last()
  defp resource_type(_), do: "Unknown"

  defp resource_id(%{id: id}), do: id
  defp resource_id(_), do: nil

  defp build_metadata(scope) do
    base =
      case Bobine.RequestContext.current() do
        nil -> %{}
        ctx -> Map.take(ctx, [:request_id, :ip, :user_agent])
      end

    case scope do
      %{impersonated_by: admin_id} when not is_nil(admin_id) ->
        Map.put(base, :impersonated_by, admin_id)

      _ ->
        base
    end
  end
end
