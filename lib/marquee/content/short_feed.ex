defmodule Marquee.Content.ShortFeed do
  @moduledoc """
  The operator-curated Shorts feed: an ordered list of an organization's
  videos shown one at a time in the viewer's vertical feed at `/shorts`.

  Part of the `Marquee.Content` context (which delegates its public API
  here). Mutations check the acting scope's role first (editor or above,
  or a super admin, with a membership in the scope's own organization),
  then broadcast an event and write a `short_feed.*` audit row.

  The viewer feed (`list_short_feed/2`) returns only eligible videos and is
  cached per organization; `Marquee.Content.ShortFeedCacheSubscriber`
  invalidates it on short-feed and video lifecycle events.
  """

  import Ecto.Query, warn: false

  require Marquee.Otel

  alias Marquee.Accounts
  alias Marquee.Accounts.{Membership, Organization}
  alias Marquee.Audit
  alias Marquee.Cache
  alias Marquee.Content.{ShortFeedItem, Video}
  alias Marquee.Events
  alias Marquee.Pagination
  alias Marquee.Repo

  @item_limit 200
  @viewer_default_per_page 8
  @admin_default_per_page 25
  @cache_ttl_ms 300_000

  ## -----------------------------------------------------------------------
  ## Reads
  ## -----------------------------------------------------------------------

  @doc """
  Returns the organization's feed items (with their videos preloaded) in
  position order, including items whose video is no longer eligible, as a
  pagination map.

  Exempt from doctest — hits the database.
  """
  def list_short_feed_items(%Organization{id: org_id}, opts \\ []) do
    ShortFeedItem
    |> where(organization_id: ^org_id)
    |> order_by(asc: :position, asc: :inserted_at)
    |> preload(:video)
    |> Pagination.paginate(with_default_per_page(opts, @admin_default_per_page))
  end

  @doc """
  Returns eligible videos of the organization that are not yet in its feed,
  optionally filtered by a title `search`, as a pagination map.

  Exempt from doctest — hits the database.
  """
  def list_short_feed_eligible_videos(%Organization{id: org_id}, opts \\ []) do
    in_feed = from(i in ShortFeedItem, where: i.organization_id == ^org_id, select: i.video_id)

    Video
    |> where([v], v.organization_id == ^org_id)
    |> where_eligible()
    |> where([v], v.id not in subquery(in_feed))
    |> apply_title_search(Keyword.get(opts, :search))
    |> order_by([v], asc: v.title, asc: v.id)
    |> Pagination.paginate(with_default_per_page(opts, @admin_default_per_page))
  end

  @doc """
  Fetches one of the organization's feed items.

  Exempt from doctest — hits the database.
  """
  def get_short_feed_item(%Organization{id: org_id}, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %ShortFeedItem{} = item <-
           Repo.one(
             from i in ShortFeedItem, where: i.id == ^uuid and i.organization_id == ^org_id
           ) do
      {:ok, item}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Returns the viewer feed: eligible videos in feed order as
  `{:ok, pagination_map}`, or `{:error, :feed_disabled}`.

  Options: `page`, `per_page` (default 8, max 100) and `only_video_ids`,
  which restricts results to those videos and bypasses the cache.

  Exempt from doctest — hits the database and cache.
  """
  def list_short_feed(%Organization{} = org, opts \\ []) do
    if org.shorts_feed_enabled do
      {:ok, fetch_short_feed_page(org, opts)}
    else
      {:error, :feed_disabled}
    end
  end

  @doc """
  Drops every cached viewer-feed page for the organization.

  Exempt from doctest — uses the cache.
  """
  def invalidate_short_feed_cache(org_id) when is_binary(org_id) do
    Cache.delete_by_prefix(cache_prefix(org_id))
  end

  defp fetch_short_feed_page(org, opts) do
    {page, per_page} = normalize_viewer_page(opts)

    case Keyword.get(opts, :only_video_ids) do
      nil ->
        Cache.fetch("#{cache_prefix(org.id)}#{page}:#{per_page}", [ttl: @cache_ttl_ms], fn ->
          query_short_feed(org, nil, page, per_page)
        end)

      ids when is_list(ids) ->
        query_short_feed(org, valid_uuids(ids), page, per_page)
    end
  end

  defp query_short_feed(%Organization{id: org_id}, only_ids, page, per_page) do
    Video
    |> join(:inner, [v], i in ShortFeedItem,
      on: i.video_id == v.id and i.organization_id == ^org_id
    )
    |> where([v], v.organization_id == ^org_id)
    |> where_eligible()
    |> restrict_to_ids(only_ids)
    |> order_by([_v, i], asc: i.position, asc: i.inserted_at)
    |> Pagination.paginate(page: page, per_page: per_page)
  end

  defp restrict_to_ids(query, nil), do: query
  defp restrict_to_ids(query, ids), do: where(query, [v], v.id in ^ids)

  defp normalize_viewer_page(opts) do
    opts
    |> with_default_per_page(@viewer_default_per_page)
    |> Pagination.normalize_opts()
  end

  defp with_default_per_page(opts, default),
    do: Keyword.put_new(opts, :per_page, default)

  defp valid_uuids(ids) do
    Enum.flat_map(ids, fn id ->
      case Ecto.UUID.cast(id) do
        {:ok, uuid} -> [uuid]
        :error -> []
      end
    end)
  end

  defp cache_prefix(org_id), do: "short_feed:#{org_id}:"

  # Same rule as a playable catalog video: not deleted, ready in Mux and
  # carrying a playback id.
  defp where_eligible(query) do
    where(
      query,
      [v],
      is_nil(v.deleted_at) and v.mux_status == "ready" and not is_nil(v.mux_playback_id) and
        v.mux_playback_id != ""
    )
  end

  defp apply_title_search(query, term) when is_binary(term) and term != "" do
    pattern = "%#{escape_like(String.trim(term))}%"
    where(query, [v], ilike(v.title, ^pattern))
  end

  defp apply_title_search(query, _term), do: query

  defp escape_like(term), do: String.replace(term, ~r/([\\%_])/, "\\\\\\1")

  ## -----------------------------------------------------------------------
  ## Mutations
  ## -----------------------------------------------------------------------

  @doc """
  Appends an eligible video of the scope's organization to the end of its
  feed. Returns `{:ok, item}` or `{:error, :forbidden | :not_found |
  :not_eligible | :already_exists}` or
  `{:error, :plan_limit_reached, %{limit: 200, current: n}}`.

  Exempt from doctest — hits the database.
  """
  def add_short_feed_video(scope, %Video{} = video) do
    with :ok <- authorize_manage(scope),
         :ok <- Marquee.AdminDemo.authorize(scope, :catalog_edit, video) do
      Marquee.Otel.with_span "marquee.content.add_short_feed_video",
                             %{"marquee.org.id" => scope.organization.id} do
        with {:ok, video} <- fetch_org_video(scope.organization, video.id),
             :ok <- ensure_eligible(video),
             :ok <- ensure_not_in_feed(scope.organization, video),
             :ok <- ensure_below_limit(scope.organization),
             {:ok, item} <- insert_item(scope.organization, video) do
          Events.broadcast(scope, {:short_feed_item_added, item})
          Audit.log(scope, "short_feed.item_added", item, %{video_id: video.id})
          {:ok, item}
        end
      end
    end
  end

  @doc """
  Removes an item from the feed (the video is untouched). Returns `:ok` or
  `{:error, :forbidden | :not_found}`.

  Exempt from doctest — hits the database.
  """
  def remove_short_feed_item(scope, %ShortFeedItem{} = item) do
    with :ok <- authorize_manage(scope),
         :ok <- Marquee.AdminDemo.authorize(scope, :catalog_edit, scope.organization) do
      Marquee.Otel.with_span "marquee.content.remove_short_feed_item",
                             %{"marquee.org.id" => scope.organization.id} do
        org_id = scope.organization.id

        case Repo.delete_all(
               from i in ShortFeedItem, where: i.id == ^item.id and i.organization_id == ^org_id
             ) do
          {1, _} ->
            Events.broadcast(scope, {:short_feed_item_removed, item})
            Audit.log(scope, "short_feed.item_removed", item, %{video_id: item.video_id})
            :ok

          {0, _} ->
            {:error, :not_found}
        end
      end
    end
  end

  @doc """
  Swaps an item with its neighbour above (`:up`) or below (`:down`). A move
  past either end is a no-op that still returns `:ok`. Returns
  `{:error, :forbidden | :not_found}` on failure.

  Exempt from doctest — hits the database.
  """
  def move_short_feed_item(scope, %ShortFeedItem{} = item, direction)
      when direction in [:up, :down] do
    with :ok <- authorize_manage(scope),
         :ok <- Marquee.AdminDemo.authorize(scope, :catalog_edit, scope.organization) do
      Marquee.Otel.with_span "marquee.content.move_short_feed_item",
                             %{"marquee.org.id" => scope.organization.id} do
        with {:ok, ordered} <- ordered_ids_containing(scope.organization, item.id),
             {:moved, new_order} <- swap_with_neighbour(ordered, item.id, direction) do
          write_positions(new_order)
          Events.broadcast(scope, {:short_feed_item_moved, item})
          Audit.log(scope, "short_feed.item_moved", item, %{direction: direction})
          :ok
        else
          :unchanged -> :ok
          error -> error
        end
      end
    end
  end

  @doc """
  Applies a full ordering of the organization's feed items. `ids` must be
  exactly the organization's item ids, each once. Returns `:ok` or
  `{:error, :forbidden | :invalid_order}`.

  Exempt from doctest — hits the database.
  """
  def reorder_short_feed(scope, ids) when is_list(ids) do
    with :ok <- authorize_manage(scope),
         :ok <- Marquee.AdminDemo.authorize(scope, :catalog_edit, scope.organization) do
      Marquee.Otel.with_span "marquee.content.reorder_short_feed",
                             %{"marquee.org.id" => scope.organization.id} do
        current = ordered_item_ids(scope.organization)

        if valid_order?(ids, current) do
          write_positions(ids)
          Events.broadcast(scope, {:short_feed_reordered, scope.organization})
          Audit.log(scope, "short_feed.reordered", scope.organization, %{item_ids: ids})
          :ok
        else
          {:error, :invalid_order}
        end
      end
    end
  end

  @doc """
  Updates the feed's enabled flag and access level from
  `%{enabled: boolean, access: level}`. Returns `{:ok, organization}` or
  `{:error, :forbidden}` or `{:error, :validation, changeset}`.

  Exempt from doctest — hits the database.
  """
  def update_short_feed_settings(scope, attrs) when is_map(attrs) do
    with :ok <- authorize_manage(scope),
         :ok <- Marquee.AdminDemo.authorize(scope, :catalog_edit, scope.organization) do
      Marquee.Otel.with_span "marquee.content.update_short_feed_settings",
                             %{"marquee.org.id" => scope.organization.id} do
        changes = %{
          shorts_feed_enabled: setting(attrs, :enabled),
          shorts_feed_access: setting(attrs, :access)
        }

        Organization
        |> Repo.get!(scope.organization.id)
        |> Organization.shorts_feed_changeset(changes)
        |> Repo.update()
        |> case do
          {:ok, org} ->
            Events.broadcast(scope, {:short_feed_settings_updated, org})
            Audit.log(scope, "short_feed.settings_updated", org, changes)
            {:ok, org}

          {:error, changeset} ->
            {:error, :validation, changeset}
        end
      end
    end
  end

  ## -----------------------------------------------------------------------
  ## Mutation helpers
  ## -----------------------------------------------------------------------

  # Role first: editor+ (or super admin) whose membership belongs to the
  # scope's own organization. The organization field alone is not trusted.
  defp authorize_manage(%{organization: %Organization{id: org_id}} = scope) do
    if Accounts.can_manage_content?(scope) and membership_matches_org?(scope, org_id),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp authorize_manage(_scope), do: {:error, :forbidden}

  defp membership_matches_org?(%{user: %{is_super_admin: true}, membership: nil}, _org_id),
    do: true

  defp membership_matches_org?(%{membership: %Membership{organization_id: org_id}}, org_id),
    do: true

  defp membership_matches_org?(_scope, _org_id), do: false

  defp fetch_org_video(%Organization{id: org_id}, video_id) do
    case Repo.one(from v in Video, where: v.id == ^video_id and v.organization_id == ^org_id) do
      %Video{} = video -> {:ok, video}
      nil -> {:error, :not_found}
    end
  end

  defp ensure_eligible(%Video{deleted_at: nil, mux_status: "ready", mux_playback_id: pid})
       when is_binary(pid) and pid != "",
       do: :ok

  defp ensure_eligible(_video), do: {:error, :not_eligible}

  defp ensure_not_in_feed(%Organization{id: org_id}, %Video{id: video_id}) do
    if Repo.exists?(
         from i in ShortFeedItem, where: i.organization_id == ^org_id and i.video_id == ^video_id
       ),
       do: {:error, :already_exists},
       else: :ok
  end

  defp ensure_below_limit(%Organization{id: org_id}) do
    current =
      Repo.aggregate(from(i in ShortFeedItem, where: i.organization_id == ^org_id), :count)

    if current >= @item_limit,
      do: {:error, :plan_limit_reached, %{limit: @item_limit, current: current}},
      else: :ok
  end

  defp insert_item(%Organization{id: org_id}, %Video{id: video_id}) do
    %ShortFeedItem{organization_id: org_id, video_id: video_id}
    |> ShortFeedItem.changeset(%{position: next_position(org_id)})
    |> Repo.insert()
    |> case do
      {:ok, item} ->
        {:ok, item}

      {:error, changeset} ->
        if unique_violation?(changeset),
          do: {:error, :already_exists},
          else: {:error, :validation, changeset}
    end
  end

  defp unique_violation?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_message, opts}} ->
      Keyword.get(opts, :constraint) == :unique
    end)
  end

  defp next_position(org_id) do
    from(i in ShortFeedItem, where: i.organization_id == ^org_id, select: max(i.position))
    |> Repo.one()
    |> case do
      nil -> 1
      max_position -> max_position + 1
    end
  end

  defp ordered_item_ids(%Organization{id: org_id}) do
    Repo.all(
      from i in ShortFeedItem,
        where: i.organization_id == ^org_id,
        order_by: [asc: i.position, asc: i.inserted_at],
        select: i.id
    )
  end

  defp ordered_ids_containing(org, item_id) do
    ids = ordered_item_ids(org)
    if item_id in ids, do: {:ok, ids}, else: {:error, :not_found}
  end

  defp swap_with_neighbour(ids, item_id, direction) do
    index = Enum.find_index(ids, &(&1 == item_id))
    target = if direction == :up, do: index - 1, else: index + 1

    if target < 0 or target >= length(ids) do
      :unchanged
    else
      {:moved,
       ids |> List.replace_at(index, Enum.at(ids, target)) |> List.replace_at(target, item_id)}
    end
  end

  defp valid_order?(ids, current) do
    length(ids) == length(current) and Enum.uniq(ids) == ids and
      MapSet.new(ids) == MapSet.new(current)
  end

  defp write_positions(ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      ids
      |> Enum.with_index(1)
      |> Enum.each(fn {id, position} ->
        Repo.update_all(from(i in ShortFeedItem, where: i.id == ^id),
          set: [position: position, updated_at: now]
        )
      end)
    end)
  end

  defp setting(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
