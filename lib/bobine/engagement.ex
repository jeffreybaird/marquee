defmodule Bobine.Engagement do
  @moduledoc """
  The Engagement context.

  Manages viewer engagement features: playback queue, watchlist, favorites,
  watch history, and playback progress.
  """

  import Ecto.Query, warn: false

  alias Bobine.Accounts.Organization
  alias Bobine.Buffers.ProgressBuffer
  alias Bobine.Content
  alias Bobine.Content.{Episode, Season, Series, Video}

  alias Bobine.Engagement.{
    Favorite,
    PlaybackDropOff,
    Progress,
    QueueItem,
    WatchHistory,
    WatchlistItem
  }

  alias Bobine.Events
  alias Bobine.Metrics
  alias Bobine.Pagination
  alias Bobine.Repo

  require Bobine.Otel

  ## -----------------------------------------------------------------------
  ## Queue
  ## -----------------------------------------------------------------------

  @doc """
  Gets the viewer's current queue, ordered by position.
  Returns a list of QueueItems with videos preloaded.

  Exempt from doctest — hits the database.
  """
  def list_queue(%Organization{id: org_id}, %{id: viewer_id}) do
    QueueItem
    |> where(organization_id: ^org_id, viewer_id: ^viewer_id)
    |> order_by(asc: :position)
    |> preload(:video)
    |> Repo.all()
  end

  @doc """
  Adds a video to the end of the queue.
  Returns {:error, :already_in_queue} if the video is already queued.

  Exempt from doctest — hits the database.
  """
  def add_to_queue(
        %Organization{id: org_id} = org,
        %{id: viewer_id} = viewer,
        video,
        source \\ "browse"
      ) do
    Bobine.Otel.with_span "bobine.engagement.add_to_queue",
                          %{"bobine.org.id" => org_id, "bobine.viewer.id" => viewer_id} do
      max_pos = get_max_queue_position(org_id, viewer_id)

      attrs = %{
        organization_id: org_id,
        viewer_id: viewer_id,
        video_id: video.id,
        position: max_pos + 1,
        added_from: source,
        added_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      case %QueueItem{} |> QueueItem.changeset(attrs) |> Repo.insert() do
        {:ok, item} ->
          Events.broadcast(
            nil,
            {:queue_item_added, %{organization: org, viewer: viewer, item: item}}
          )

          {:ok, Repo.preload(item, :video)}

        {:error, %Ecto.Changeset{errors: errors} = _changeset} ->
          if Keyword.has_key?(errors, :organization_id) do
            {:error, :already_in_queue}
          else
            {:error, :already_in_queue}
          end
      end
    end
  end

  @doc """
  Inserts a video at position 0 (next to play).
  Shifts all other items down by one position.

  Exempt from doctest — hits the database.
  """
  def play_next(
        %Organization{id: org_id} = org,
        %{id: viewer_id} = viewer,
        video,
        source \\ "browse"
      ) do
    Bobine.Otel.with_span "bobine.engagement.play_next",
                          %{"bobine.org.id" => org_id, "bobine.viewer.id" => viewer_id} do
      Repo.transaction(fn ->
        case get_queue_item(org_id, viewer_id, video.id) do
          nil ->
            # Shift all existing items down by 1
            from(q in QueueItem,
              where: q.organization_id == ^org_id,
              where: q.viewer_id == ^viewer_id
            )
            |> Repo.update_all(inc: [position: 1])

            # Insert at position 0
            {:ok, item} =
              %QueueItem{
                organization_id: org_id,
                viewer_id: viewer_id,
                video_id: video.id,
                position: 0,
                added_from: source,
                added_at: DateTime.utc_now() |> DateTime.truncate(:second)
              }
              |> Repo.insert()

            Events.broadcast(
              nil,
              {:queue_item_added, %{organization: org, viewer: viewer, item: item}}
            )

            Repo.preload(item, :video)

          existing ->
            reorder_to_front(org_id, viewer_id, existing)
            Repo.preload(existing, :video)
        end
      end)
    end
  end

  @doc """
  Adds all videos from a collection to the end of the queue, preserving
  the collection's video order. Skips any videos already in the queue.

  Exempt from doctest — hits the database.
  """
  def add_collection_to_queue(
        %Organization{id: org_id} = org,
        %{id: viewer_id} = viewer,
        collection
      ) do
    Bobine.Otel.with_span "bobine.engagement.add_collection_to_queue",
                          %{"bobine.org.id" => org_id} do
      %{results: videos} = Content.list_collection_videos(org, collection, per_page: 100)
      current_max = get_max_queue_position(org_id, viewer_id)

      existing_video_ids = list_queue_video_ids(org_id, viewer_id)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      new_items =
        videos
        |> Enum.reject(fn v -> v.id in existing_video_ids end)
        |> Enum.with_index(current_max + 1)
        |> Enum.map(fn {video, position} ->
          %{
            id: Ecto.UUID.generate(),
            organization_id: org_id,
            viewer_id: viewer_id,
            video_id: video.id,
            position: position,
            added_from: "collection",
            added_at: now,
            inserted_at: now,
            updated_at: now
          }
        end)

      {count, _} = Repo.insert_all(QueueItem, new_items, on_conflict: :nothing)

      Events.broadcast(
        nil,
        {:queue_collection_added, %{organization: org, viewer: viewer, count: count}}
      )

      {:ok, count}
    end
  end

  @doc """
  Adds a list of videos to the END of the queue, preserving the input order.

  Skips videos already in the queue (idempotent — useful for "add a season"
  flows where some episodes may already be queued). Returns `{:ok, count}`
  where `count` is the number of NEW items inserted.

  Exempt from doctest — hits the database.
  """
  def add_videos_to_queue_end(
        %Organization{id: org_id} = org,
        %{id: viewer_id} = viewer,
        videos
      )
      when is_list(videos) do
    Bobine.Otel.with_span "bobine.engagement.add_videos_to_queue_end",
                          %{"bobine.org.id" => org_id, "bobine.viewer.id" => viewer_id} do
      current_max = get_max_queue_position(org_id, viewer_id)
      existing_ids = list_queue_video_ids(org_id, viewer_id)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      new_items =
        videos
        |> Enum.reject(fn v -> v.id in existing_ids end)
        |> Enum.with_index(current_max + 1)
        |> Enum.map(fn {video, position} ->
          %{
            id: Ecto.UUID.generate(),
            organization_id: org_id,
            viewer_id: viewer_id,
            video_id: video.id,
            position: position,
            added_from: "collection",
            added_at: now,
            inserted_at: now,
            updated_at: now
          }
        end)

      {count, _} = Repo.insert_all(QueueItem, new_items, on_conflict: :nothing)

      if count > 0 do
        Events.broadcast(
          nil,
          {:queue_collection_added, %{organization: org, viewer: viewer, count: count}}
        )
      end

      {:ok, count}
    end
  end

  @doc """
  Adds a list of videos to the BEGINNING of the queue, preserving the
  input order. Existing items are shifted down by the number of new items
  added. Skips videos already in the queue.

  Exempt from doctest — hits the database.
  """
  def add_videos_to_queue_beginning(
        %Organization{id: org_id} = org,
        %{id: viewer_id} = viewer,
        videos
      )
      when is_list(videos) do
    Bobine.Otel.with_span "bobine.engagement.add_videos_to_queue_beginning",
                          %{"bobine.org.id" => org_id, "bobine.viewer.id" => viewer_id} do
      existing_ids = list_queue_video_ids(org_id, viewer_id)
      videos_to_add = Enum.reject(videos, fn v -> v.id in existing_ids end)
      shift_amount = length(videos_to_add)

      if shift_amount == 0 do
        {:ok, 0}
      else
        do_add_videos_to_queue_beginning(org, viewer, videos_to_add, shift_amount)
      end
    end
  end

  defp do_add_videos_to_queue_beginning(
         %Organization{id: org_id} = org,
         %{id: viewer_id} = viewer,
         videos_to_add,
         shift_amount
       ) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, count} =
      Repo.transaction(fn ->
        from(q in QueueItem,
          where: q.organization_id == ^org_id,
          where: q.viewer_id == ^viewer_id
        )
        |> Repo.update_all(inc: [position: shift_amount])

        new_items =
          videos_to_add
          |> Enum.with_index(0)
          |> Enum.map(fn {video, position} ->
            %{
              id: Ecto.UUID.generate(),
              organization_id: org_id,
              viewer_id: viewer_id,
              video_id: video.id,
              position: position,
              added_from: "collection",
              added_at: now,
              inserted_at: now,
              updated_at: now
            }
          end)

        {count, _} = Repo.insert_all(QueueItem, new_items, on_conflict: :nothing)
        count
      end)

    if count > 0 do
      Events.broadcast(
        nil,
        {:queue_collection_added, %{organization: org, viewer: viewer, count: count}}
      )
    end

    {:ok, count}
  end

  @doc """
  Returns true when the viewer has any progress on any episode in the
  given season. Used to decide whether the "add season to queue" button
  should prompt for a confirmation (all vs. unwatched).

  Exempt from doctest — hits the database.
  """
  def has_season_progress?(%Organization{id: org_id}, %{id: viewer_id}, season) do
    episode_video_ids =
      Episode
      |> where(organization_id: ^org_id, season_id: ^season.id)
      |> select([e], e.video_id)

    Progress
    |> where(organization_id: ^org_id, viewer_id: ^viewer_id)
    |> where([p], p.video_id in subquery(episode_video_ids))
    |> Repo.exists?()
  end

  @doc """
  Removes a video from the queue. Hard delete.

  Exempt from doctest — hits the database.
  """
  def remove_from_queue(%Organization{id: org_id} = org, %{id: viewer_id} = viewer, video) do
    Bobine.Otel.with_span "bobine.engagement.remove_from_queue",
                          %{"bobine.org.id" => org_id} do
      {deleted, _} =
        from(q in QueueItem,
          where: q.organization_id == ^org_id,
          where: q.viewer_id == ^viewer_id,
          where: q.video_id == ^video.id
        )
        |> Repo.delete_all()

      if deleted > 0 do
        recompact_positions(org_id, viewer_id)

        Events.broadcast(
          nil,
          {:queue_item_removed, %{organization: org, viewer: viewer, video: video}}
        )

        :ok
      else
        {:error, :not_found}
      end
    end
  end

  @doc """
  Removes the video at the front of the queue (the one that just finished
  or was skipped) and returns the next video.

  Returns {:ok, %{next_video: video | nil, previous_video: video}} or {:ok, nil} if empty.

  Exempt from doctest — hits the database.
  """
  def advance_queue(%Organization{id: org_id} = org, %{id: viewer_id} = viewer, completed_video) do
    Bobine.Otel.with_span "bobine.engagement.advance_queue",
                          %{"bobine.org.id" => org_id} do
      Repo.transaction(fn ->
        progress = get_progress(org, viewer, completed_video)

        # Remove the completed video from the queue
        from(q in QueueItem,
          where: q.organization_id == ^org_id,
          where: q.viewer_id == ^viewer_id,
          where: q.video_id == ^completed_video.id
        )
        |> Repo.delete_all()

        recompact_positions(org_id, viewer_id)

        # Store go-back state
        store_go_back_state(org, viewer, %{
          video_id: completed_video.id,
          position: (progress && progress.position) || 0.0,
          advanced_at: DateTime.utc_now()
        })

        # Get the next video
        next = peek_next(org, viewer)

        if next do
          Events.broadcast(
            nil,
            {:queue_advanced, %{organization: org, viewer: viewer, video: next.video}}
          )
        end

        %{next_video: next && next.video, previous_video: completed_video}
      end)
    end
  end

  @doc """
  Reverses the last queue advance — re-inserts the previous video at the
  front of the queue and returns it. Only valid within 60 seconds.

  Exempt from doctest — hits the database.
  """
  def go_back_in_queue(%Organization{} = org, %{id: _viewer_id} = viewer) do
    case get_go_back_state(org, viewer) do
      nil ->
        {:error, :no_go_back_available}

      %{advanced_at: advanced_at} = state ->
        elapsed = DateTime.diff(DateTime.utc_now(), advanced_at, :second)

        if elapsed > 60 do
          clear_go_back_state(org, viewer)
          {:error, :go_back_expired}
        else
          video = Content.get_video!(state.video_id)
          play_next(org, viewer, video, "go_back")
          clear_go_back_state(org, viewer)

          {:ok, %{video: video, resume_position: state.position}}
        end
    end
  end

  @doc """
  Reorders the queue. Accepts a list of video IDs in the desired order.
  Updates all positions in a single transaction.

  Exempt from doctest — hits the database.
  """
  def reorder_queue(%Organization{id: org_id}, %{id: viewer_id}, ordered_video_ids) do
    Bobine.Otel.with_span "bobine.engagement.reorder_queue",
                          %{"bobine.org.id" => org_id} do
      Repo.transaction(fn ->
        ordered_video_ids
        |> Enum.with_index()
        |> Enum.each(fn {video_id, position} ->
          from(q in QueueItem,
            where: q.organization_id == ^org_id,
            where: q.viewer_id == ^viewer_id,
            where: q.video_id == ^video_id
          )
          |> Repo.update_all(set: [position: position])
        end)
      end)
      |> case do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Clears the entire queue for a viewer.

  Exempt from doctest — hits the database.
  """
  def clear_queue(%Organization{id: org_id} = org, %{id: viewer_id} = viewer) do
    Bobine.Otel.with_span "bobine.engagement.clear_queue",
                          %{"bobine.org.id" => org_id} do
      from(q in QueueItem,
        where: q.organization_id == ^org_id,
        where: q.viewer_id == ^viewer_id
      )
      |> Repo.delete_all()

      Events.broadcast(nil, {:queue_cleared, %{organization: org, viewer: viewer}})
      :ok
    end
  end

  @doc """
  Returns the count of items in the viewer's queue.

  Exempt from doctest — hits the database.
  """
  def queue_count(%Organization{id: org_id}, %{id: viewer_id}) do
    from(q in QueueItem,
      where: q.organization_id == ^org_id,
      where: q.viewer_id == ^viewer_id
    )
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns the next video in the queue (lowest position) without removing it.

  Exempt from doctest — hits the database.
  """
  def peek_next(%Organization{id: org_id}, %{id: viewer_id}) do
    QueueItem
    |> where(organization_id: ^org_id, viewer_id: ^viewer_id)
    |> order_by(asc: :position)
    |> limit(1)
    |> preload(:video)
    |> Repo.one()
  end

  ## Queue private helpers

  defp get_queue_item(org_id, viewer_id, video_id) do
    Repo.get_by(QueueItem,
      organization_id: org_id,
      viewer_id: viewer_id,
      video_id: video_id
    )
  end

  defp get_max_queue_position(org_id, viewer_id) do
    from(q in QueueItem,
      where: q.organization_id == ^org_id,
      where: q.viewer_id == ^viewer_id,
      select: max(q.position)
    )
    |> Repo.one()
    |> Kernel.||(-1)
  end

  defp list_queue_video_ids(org_id, viewer_id) do
    from(q in QueueItem,
      where: q.organization_id == ^org_id,
      where: q.viewer_id == ^viewer_id,
      select: q.video_id
    )
    |> Repo.all()
  end

  defp reorder_to_front(org_id, viewer_id, %QueueItem{} = item) do
    # Move everything else down
    from(q in QueueItem,
      where: q.organization_id == ^org_id,
      where: q.viewer_id == ^viewer_id,
      where: q.id != ^item.id
    )
    |> Repo.update_all(inc: [position: 1])

    # Move this item to front
    item
    |> Ecto.Changeset.change(position: 0)
    |> Repo.update!()
  end

  defp recompact_positions(org_id, viewer_id) do
    items =
      from(q in QueueItem,
        where: q.organization_id == ^org_id,
        where: q.viewer_id == ^viewer_id,
        order_by: [asc: q.position],
        select: q.id
      )
      |> Repo.all()

    items
    |> Enum.with_index()
    |> Enum.each(fn {id, index} ->
      from(q in QueueItem, where: q.id == ^id)
      |> Repo.update_all(set: [position: index])
    end)
  end

  ## Go-back state (ETS — ephemeral, not persisted)

  defp store_go_back_state(%Organization{id: org_id}, %{id: viewer_id}, state) do
    key = {:go_back, org_id, viewer_id}
    :ets.insert(:bobine_go_back, {key, state})
  end

  @doc false
  def get_go_back_state(%Organization{id: org_id}, %{id: viewer_id}) do
    key = {:go_back, org_id, viewer_id}

    case :ets.lookup(:bobine_go_back, key) do
      [{^key, state}] -> state
      [] -> nil
    end
  end

  defp clear_go_back_state(%Organization{id: org_id}, %{id: viewer_id}) do
    key = {:go_back, org_id, viewer_id}
    :ets.delete(:bobine_go_back, key)
  end

  ## -----------------------------------------------------------------------
  ## Watchlist (existing functions preserved + new viewer-scoped functions)
  ## -----------------------------------------------------------------------

  @doc """
  Returns a paginated list of watchlist_items, excluding soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_watchlist_items(opts \\ []) do
    WatchlistItem
    |> where([w], is_nil(w.deleted_at))
    |> order_by(desc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  @doc """
  Returns the list of watchlist_items including soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_watchlist_items_including_deleted do
    Repo.all(WatchlistItem)
  end

  @doc """
  Gets a single watchlist_item.

  Raises `Ecto.NoResultsError` if the Watchlist item does not exist.

  ## Examples

      iex> get_watchlist_item!(123)
      %WatchlistItem{}

      iex> get_watchlist_item!(456)
      ** (Ecto.NoResultsError)

  """
  def get_watchlist_item!(id), do: Repo.get!(WatchlistItem, id)

  @doc """
  Creates a watchlist_item.

  Exempt from doctest — hits the database.
  """
  def create_watchlist_item(attrs) do
    case %WatchlistItem{} |> WatchlistItem.changeset(attrs) |> Repo.insert() do
      {:ok, item} ->
        Events.broadcast(nil, {:watchlist_item_added, item})
        {:ok, item}

      {:error, changeset} ->
        {:error, :validation, changeset}
    end
  end

  @doc """
  Updates a watchlist_item.

  Exempt from doctest — hits the database.
  """
  def update_watchlist_item(%WatchlistItem{} = watchlist_item, attrs) do
    case watchlist_item |> WatchlistItem.changeset(attrs) |> Repo.update() do
      {:ok, item} -> {:ok, item}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Soft-deletes a watchlist_item by setting `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def delete_watchlist_item(%WatchlistItem{} = watchlist_item) do
    with {:ok, item} <-
           watchlist_item
           |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
           |> Repo.update() do
      Events.broadcast(nil, {:watchlist_item_removed, item})
      {:ok, item}
    end
  end

  @doc """
  Restores a soft-deleted watchlist_item by clearing `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def restore_watchlist_item(%WatchlistItem{} = watchlist_item) do
    watchlist_item
    |> Ecto.Changeset.change(deleted_at: nil)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking watchlist_item changes.

  ## Examples

      iex> change_watchlist_item(%Bobine.Engagement.WatchlistItem{})
      %Ecto.Changeset{data: %Bobine.Engagement.WatchlistItem{}}

  """
  def change_watchlist_item(%WatchlistItem{} = watchlist_item, attrs \\ %{}) do
    WatchlistItem.changeset(watchlist_item, attrs)
  end

  ## Viewer watchlist

  @doc """
  Returns a paginated list of watchlist items for a viewer, with preloaded videos.

  Exempt from doctest — hits the database.
  """
  def list_viewer_watchlist(%Organization{id: org_id}, viewer_id, opts \\ [])
      when is_binary(viewer_id) do
    WatchlistItem
    |> where([w], w.organization_id == ^org_id)
    |> where([w], w.viewer_id == ^viewer_id)
    |> where([w], is_nil(w.deleted_at))
    |> order_by(desc: :inserted_at)
    |> preload([:video, :series, season: :series])
    |> Pagination.paginate(opts)
  end

  @doc """
  Returns a flat list of videos from a viewer's watchlist.

  Exempt from doctest — hits the database.
  """
  def list_viewer_watchlist_videos(%Organization{} = org, viewer_id, opts \\ [])
      when is_binary(viewer_id) do
    org
    |> list_viewer_watchlist(viewer_id, opts)
    |> Map.fetch!(:results)
    |> Enum.map(& &1.video)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Returns a paginated watchlist for a viewer (struct-based API).

  Each item is one of three polymorphic kinds (`:video`, `:season`, or
  `:series`); all three associations are preloaded so the renderer can
  dispatch on `item_type` without follow-up queries.

  Exempt from doctest — hits the database.
  """
  def list_watchlist(%Organization{id: org_id}, %{id: viewer_id}, opts \\ []) do
    WatchlistItem
    |> where([w], w.organization_id == ^org_id)
    |> where([w], w.viewer_id == ^viewer_id)
    |> where([w], is_nil(w.deleted_at))
    |> order_by(desc: :inserted_at)
    |> preload([:video, :season, :series])
    |> Pagination.paginate(opts)
  end

  @doc """
  Adds a video, season, or series to a viewer's watchlist.

  Dispatches on the struct type. Restores previously soft-deleted items
  rather than creating duplicates.

  Exempt from doctest — hits the database.
  """
  def add_to_watchlist(
        %Organization{id: org_id} = _org,
        %{id: viewer_id} = _viewer,
        %Video{} = video
      ) do
    Bobine.Otel.with_span "bobine.engagement.add_to_watchlist",
                          %{"bobine.org.id" => org_id} do
      do_add_video_to_watchlist(org_id, viewer_id, video)
    end
  end

  def add_to_watchlist(
        %Organization{id: org_id} = _org,
        %{id: viewer_id} = _viewer,
        %Season{} = season
      ) do
    Bobine.Otel.with_span "bobine.engagement.add_to_watchlist",
                          %{"bobine.org.id" => org_id, "bobine.engagement.item_type" => "season"} do
      do_add_polymorphic_to_watchlist(
        org_id,
        viewer_id,
        :season,
        :season_id,
        season.id
      )
    end
  end

  def add_to_watchlist(
        %Organization{id: org_id} = _org,
        %{id: viewer_id} = _viewer,
        %Series{} = series
      ) do
    Bobine.Otel.with_span "bobine.engagement.add_to_watchlist",
                          %{"bobine.org.id" => org_id, "bobine.engagement.item_type" => "series"} do
      do_add_polymorphic_to_watchlist(
        org_id,
        viewer_id,
        :series,
        :series_id,
        series.id
      )
    end
  end

  defp do_add_video_to_watchlist(org_id, viewer_id, video) do
    existing =
      WatchlistItem
      |> where(
        organization_id: ^org_id,
        viewer_id: ^viewer_id,
        video_id: ^video.id,
        item_type: :video
      )
      |> Repo.one()

    case existing do
      %WatchlistItem{deleted_at: deleted_at} = item when not is_nil(deleted_at) ->
        restore_watchlist_item(item)

      %WatchlistItem{} ->
        {:error, :already_in_watchlist}

      nil ->
        attrs = %{
          organization_id: org_id,
          viewer_id: viewer_id,
          video_id: video.id,
          item_type: :video
        }

        case %WatchlistItem{} |> WatchlistItem.viewer_changeset(attrs) |> Repo.insert() do
          {:ok, item} ->
            Events.broadcast(nil, {:watchlist_item_added, item})
            {:ok, item}

          {:error, changeset} ->
            {:error, :validation, changeset}
        end
    end
  end

  defp do_add_polymorphic_to_watchlist(org_id, viewer_id, item_type, fk_field, fk_value) do
    existing =
      WatchlistItem
      |> where([w], w.organization_id == ^org_id and w.viewer_id == ^viewer_id)
      |> where([w], field(w, ^fk_field) == ^fk_value)
      |> where([w], w.item_type == ^item_type)
      |> Repo.one()

    case existing do
      %WatchlistItem{deleted_at: deleted_at} = item when not is_nil(deleted_at) ->
        restore_watchlist_item(item)

      %WatchlistItem{} ->
        {:error, :already_in_watchlist}

      nil ->
        attrs =
          %{
            organization_id: org_id,
            viewer_id: viewer_id,
            item_type: item_type
          }
          |> Map.put(fk_field, fk_value)

        case %WatchlistItem{} |> WatchlistItem.viewer_changeset(attrs) |> Repo.insert() do
          {:ok, item} ->
            Events.broadcast(nil, {:watchlist_item_added, item})
            {:ok, item}

          {:error, changeset} ->
            {:error, :validation, changeset}
        end
    end
  end

  @doc """
  Adds a video to a viewer's watchlist (ID-based API, preserved for compatibility).

  Exempt from doctest — hits the database.
  """
  def add_to_viewer_watchlist(org_id, viewer_id, video_id)
      when is_binary(org_id) and is_binary(viewer_id) and is_binary(video_id) do
    attrs = %{
      organization_id: org_id,
      viewer_id: viewer_id,
      video_id: video_id
    }

    case %WatchlistItem{} |> WatchlistItem.viewer_changeset(attrs) |> Repo.insert() do
      {:ok, item} ->
        Events.broadcast(nil, {:watchlist_item_added, item})
        {:ok, item}

      {:error, changeset} ->
        {:error, :validation, changeset}
    end
  end

  @doc """
  Removes a video, season, or series from a viewer's watchlist (soft delete).

  Dispatches on the struct type.

  Exempt from doctest — hits the database.
  """
  def remove_from_watchlist(%Organization{id: org_id}, %{id: viewer_id}, %Video{} = video) do
    Bobine.Otel.with_span "bobine.engagement.remove_from_watchlist",
                          %{"bobine.org.id" => org_id} do
      delete_polymorphic_watchlist_item(org_id, viewer_id, :video, :video_id, video.id)
    end
  end

  def remove_from_watchlist(%Organization{id: org_id}, %{id: viewer_id}, %Season{} = season) do
    Bobine.Otel.with_span "bobine.engagement.remove_from_watchlist",
                          %{"bobine.org.id" => org_id} do
      delete_polymorphic_watchlist_item(org_id, viewer_id, :season, :season_id, season.id)
    end
  end

  def remove_from_watchlist(%Organization{id: org_id}, %{id: viewer_id}, %Series{} = series) do
    Bobine.Otel.with_span "bobine.engagement.remove_from_watchlist",
                          %{"bobine.org.id" => org_id} do
      delete_polymorphic_watchlist_item(org_id, viewer_id, :series, :series_id, series.id)
    end
  end

  defp delete_polymorphic_watchlist_item(org_id, viewer_id, item_type, fk_field, fk_value) do
    query =
      WatchlistItem
      |> where([w], w.organization_id == ^org_id and w.viewer_id == ^viewer_id)
      |> where([w], field(w, ^fk_field) == ^fk_value)
      |> where([w], w.item_type == ^item_type)
      |> where([w], is_nil(w.deleted_at))

    case Repo.one(query) do
      nil -> {:error, :not_found}
      item -> delete_watchlist_item(item)
    end
  end

  @doc """
  Removes a video from a viewer's watchlist (ID-based API, preserved for compatibility).

  Exempt from doctest — hits the database.
  """
  def remove_from_viewer_watchlist(org_id, viewer_id, video_id) do
    query =
      WatchlistItem
      |> where(organization_id: ^org_id, viewer_id: ^viewer_id, video_id: ^video_id)
      |> where([w], is_nil(w.deleted_at))

    case Repo.one(query) do
      nil -> {:error, :not_found}
      item -> delete_watchlist_item(item)
    end
  end

  @doc """
  Checks if a video, season, or series is in a viewer's watchlist.

  Exempt from doctest — hits the database.
  """
  def in_watchlist?(%Organization{id: org_id}, %{id: viewer_id}, %Video{id: video_id}) do
    WatchlistItem
    |> where(
      organization_id: ^org_id,
      viewer_id: ^viewer_id,
      video_id: ^video_id,
      item_type: :video
    )
    |> where([w], is_nil(w.deleted_at))
    |> Repo.exists?()
  end

  def in_watchlist?(%Organization{id: org_id}, %{id: viewer_id}, %Season{id: season_id}) do
    WatchlistItem
    |> where(
      organization_id: ^org_id,
      viewer_id: ^viewer_id,
      season_id: ^season_id,
      item_type: :season
    )
    |> where([w], is_nil(w.deleted_at))
    |> Repo.exists?()
  end

  def in_watchlist?(%Organization{id: org_id}, %{id: viewer_id}, %Series{id: series_id}) do
    WatchlistItem
    |> where(
      organization_id: ^org_id,
      viewer_id: ^viewer_id,
      series_id: ^series_id,
      item_type: :series
    )
    |> where([w], is_nil(w.deleted_at))
    |> Repo.exists?()
  end

  @doc """
  Reorders the watchlist. Accepts a list of video IDs in the desired order.

  Exempt from doctest — hits the database.
  """
  def reorder_watchlist(%Organization{id: org_id}, %{id: viewer_id}, ordered_video_ids) do
    Repo.transaction(fn ->
      ordered_video_ids
      |> Enum.with_index()
      |> Enum.each(fn {video_id, position} ->
        from(w in WatchlistItem,
          where: w.organization_id == ^org_id,
          where: w.viewer_id == ^viewer_id,
          where: w.video_id == ^video_id
        )
        |> Repo.update_all(set: [position: position])
      end)
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  ## -----------------------------------------------------------------------
  ## Favorites
  ## -----------------------------------------------------------------------

  @doc """
  Returns a paginated list of favorites for a viewer, with videos preloaded.

  Exempt from doctest — hits the database.
  """
  def list_favorites(%Organization{id: org_id}, %{id: viewer_id}, opts \\ []) do
    Favorite
    |> where(organization_id: ^org_id, viewer_id: ^viewer_id)
    |> where([f], is_nil(f.deleted_at))
    |> order_by(desc: :inserted_at)
    |> preload(:video)
    |> Pagination.paginate(opts)
  end

  @doc """
  Toggles a favorite — adds if not favorited, removes if favorited.
  Returns `{:ok, :added}` or `{:ok, :removed}`.

  Exempt from doctest — hits the database.
  """
  def toggle_favorite(%Organization{id: org_id} = org, %{id: viewer_id} = viewer, video) do
    Bobine.Otel.with_span "bobine.engagement.toggle_favorite",
                          %{"bobine.org.id" => org_id} do
      existing =
        Favorite
        |> where(organization_id: ^org_id, viewer_id: ^viewer_id, video_id: ^video.id)
        |> Repo.one()

      case existing do
        %Favorite{deleted_at: nil} = fav ->
          fav
          |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
          |> Repo.update!()

          Events.broadcast(
            nil,
            {:favorite_removed, %{organization: org, viewer: viewer, video: video}}
          )

          {:ok, :removed}

        %Favorite{deleted_at: _} = fav ->
          fav
          |> Ecto.Changeset.change(deleted_at: nil)
          |> Repo.update!()

          Events.broadcast(
            nil,
            {:favorite_added, %{organization: org, viewer: viewer, video: video}}
          )

          {:ok, :added}

        nil ->
          %Favorite{
            organization_id: org_id,
            viewer_id: viewer_id,
            video_id: video.id
          }
          |> Repo.insert!()

          Events.broadcast(
            nil,
            {:favorite_added, %{organization: org, viewer: viewer, video: video}}
          )

          {:ok, :added}
      end
    end
  end

  @doc """
  Checks if a video is favorited by a viewer.

  Exempt from doctest — hits the database.
  """
  def favorited?(%Organization{id: org_id}, %{id: viewer_id}, video) do
    Favorite
    |> where(organization_id: ^org_id, viewer_id: ^viewer_id, video_id: ^video.id)
    |> where([f], is_nil(f.deleted_at))
    |> Repo.exists?()
  end

  ## -----------------------------------------------------------------------
  ## Watch History
  ## -----------------------------------------------------------------------

  @doc """
  Records or updates a watch history entry for this viewing session.

  Exempt from doctest — hits the database.
  """
  def record_watch_activity(%Organization{id: org_id}, %{id: viewer_id}, video) do
    Bobine.Otel.with_span "bobine.engagement.record_watch_activity",
                          %{"bobine.org.id" => org_id} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Check for recent entry (within last 30 minutes)
      cutoff = DateTime.add(now, -30, :minute)

      recent =
        WatchHistory
        |> where(organization_id: ^org_id, viewer_id: ^viewer_id, video_id: ^video.id)
        |> where([wh], wh.watched_at > ^cutoff)
        |> order_by(desc: :watched_at)
        |> limit(1)
        |> Repo.one()

      case recent do
        %WatchHistory{} = entry ->
          entry
          |> Ecto.Changeset.change(watched_at: now)
          |> Repo.update()

        nil ->
          %WatchHistory{
            organization_id: org_id,
            viewer_id: viewer_id,
            video_id: video.id,
            watched_at: now
          }
          |> Repo.insert()
      end
    end
  end

  @doc """
  Gets the viewer's watch history, most recent first.

  Exempt from doctest — hits the database.
  """
  def list_watch_history(%Organization{id: org_id}, %{id: viewer_id}, opts \\ []) do
    WatchHistory
    |> where(organization_id: ^org_id, viewer_id: ^viewer_id)
    |> order_by(desc: :watched_at)
    |> preload(:video)
    |> Pagination.paginate(opts)
  end

  @doc """
  Returns the viewer's continue-watching items.

  Mixes three kinds of entries, deduplicated to one per series:

    * `:in_progress` — episode/standalone videos the viewer started but
      hasn't finished. The card shows a progress bar.
    * `:between_episodes` — the viewer finished an episode in a season
      and there are more unwatched episodes after it. The next episode is
      surfaced with no progress bar.
    * `:next_season` — the viewer finished every episode in a season and
      another season exists. The next season is surfaced.

  Each result is a map with `:type`, `:video`, `:episode_context`,
  `:position`, `:duration`, `:last_activity_at`, `:series_id`, and
  (for `:next_season`) `:season` and `:series` keys.

  Items are deduplicated by `series_id` (standalone items are never
  deduplicated) and sorted by most recent activity.

  Exempt from doctest — hits the database.
  """
  def list_continue_watching(%Organization{} = org, %{} = viewer, opts \\ []) do
    Bobine.Otel.with_span "bobine.engagement.list_continue_watching",
                          %{"bobine.org.id" => org.id, "bobine.viewer.id" => viewer.id} do
      per_page = Keyword.get(opts, :per_page, 20)

      in_progress_records = list_in_progress_records(org, viewer)

      episode_items = build_in_progress_items(org, in_progress_records)
      between_items = find_between_episode_items(org, viewer, in_progress_records)
      next_season_items = find_next_season_items(org, viewer)

      results =
        (episode_items ++ between_items ++ next_season_items)
        |> deduplicate_by_series()
        |> Enum.sort_by(& &1.last_activity_at, {:desc, DateTime})
        |> Enum.take(per_page)

      %{
        results: results,
        page: 1,
        per_page: per_page,
        total: length(results),
        total_pages: 1
      }
    end
  end

  defp list_in_progress_records(%Organization{id: org_id}, %{id: viewer_id}) do
    Progress
    |> where(organization_id: ^org_id, viewer_id: ^viewer_id)
    |> where([p], p.completed == false)
    |> where([p], p.position > 0.0)
    |> join(:inner, [p], v in Video, on: v.id == p.video_id and is_nil(v.deleted_at))
    |> order_by([p], desc: p.updated_at)
    |> preload(:video)
    |> Repo.all()
  end

  defp build_in_progress_items(%Organization{} = org, in_progress_records) do
    Enum.map(in_progress_records, fn progress ->
      video = progress.video
      episode_context = Content.get_episode_context(org, video)

      %{
        type: :in_progress,
        video: video,
        episode_context: episode_context,
        position: progress.position,
        duration: progress.duration || video.duration || 0.0,
        last_activity_at: progress.updated_at,
        season: episode_context && episode_context.season,
        series: episode_context && episode_context.series,
        series_id: episode_context && episode_context.series.id
      }
    end)
  end

  # Finds seasons where the viewer's most-recent completed episode has a
  # successor episode they haven't started yet.
  defp find_between_episode_items(%Organization{id: org_id} = org, viewer, in_progress_records) do
    in_progress_video_ids =
      in_progress_records
      |> Enum.map(& &1.video_id)
      |> MapSet.new()

    completed_progress_by_season =
      Progress
      |> where(organization_id: ^org_id, viewer_id: ^viewer.id)
      |> where([p], p.completed == true)
      |> join(:inner, [p], e in Episode,
        on: e.video_id == p.video_id and e.organization_id == ^org_id
      )
      |> select([p, e], %{
        episode_number: e.episode_number,
        season_id: e.season_id,
        updated_at: p.updated_at
      })
      |> Repo.all()
      |> Enum.group_by(& &1.season_id)

    Enum.flat_map(completed_progress_by_season, fn {season_id, completed_records} ->
      build_between_episode_item(org, viewer, season_id, completed_records, in_progress_video_ids)
    end)
  end

  defp build_between_episode_item(
         org,
         _viewer,
         season_id,
         completed_records,
         in_progress_video_ids
       ) do
    season = Content.get_season!(org, season_id)
    episodes = Content.list_episodes(org, season)
    max_completed = completed_records |> Enum.map(& &1.episode_number) |> Enum.max(fn -> 0 end)

    next_episode = Enum.find(episodes, &(&1.episode_number > max_completed))

    cond do
      is_nil(next_episode) ->
        []

      MapSet.member?(in_progress_video_ids, next_episode.video_id) ->
        # The viewer has already started the next episode — the in-progress
        # entry will represent it; don't double-count.
        []

      true ->
        episode_context = Content.get_episode_context(org, next_episode.video)
        most_recent = Enum.max_by(completed_records, & &1.updated_at, DateTime)

        [
          %{
            type: :between_episodes,
            video: next_episode.video,
            episode_context: episode_context,
            position: 0.0,
            duration: next_episode.video.duration || 0.0,
            last_activity_at: most_recent.updated_at,
            season: episode_context && episode_context.season,
            series: episode_context && episode_context.series,
            series_id: episode_context && episode_context.series.id
          }
        ]
    end
  end

  # Finds seasons where every episode is completed and the next season has
  # no progress yet.
  defp find_next_season_items(%Organization{id: org_id} = org, viewer) do
    viewer_season_ids =
      Progress
      |> where(organization_id: ^org_id, viewer_id: ^viewer.id)
      |> join(:inner, [p], e in Episode,
        on: e.video_id == p.video_id and e.organization_id == ^org_id
      )
      |> select([_p, e], e.season_id)
      |> distinct(true)
      |> Repo.all()

    Enum.flat_map(viewer_season_ids, fn season_id ->
      build_next_season_item(org, viewer, season_id)
    end)
  end

  defp build_next_season_item(%Organization{} = org, viewer, season_id) do
    season = Content.get_season!(org, season_id)
    episodes = Content.list_episodes(org, season)

    cond do
      episodes == [] ->
        []

      not all_episodes_completed?(org, viewer, episodes) ->
        []

      true ->
        case Content.next_season(org, season) do
          nil -> []
          next_season -> maybe_build_next_season_item(org, viewer, season, next_season)
        end
    end
  end

  defp maybe_build_next_season_item(org, viewer, season, next_season) do
    next_episodes = Content.list_episodes(org, next_season)

    cond do
      next_episodes == [] ->
        []

      season_started?(org, viewer, next_episodes) ->
        []

      true ->
        series = season.series || Repo.preload(season, :series).series
        most_recent = most_recent_progress_in_season(org, viewer, season.id)

        [
          %{
            type: :next_season,
            video: nil,
            episode_context: nil,
            season: next_season,
            series: series,
            position: 0.0,
            duration: 0.0,
            last_activity_at: most_recent && most_recent.updated_at,
            series_id: season.series_id
          }
        ]
    end
  end

  defp all_episodes_completed?(org, viewer, episodes) do
    Enum.all?(episodes, fn ep ->
      case get_progress(org, viewer, ep.video) do
        %Progress{completed: true} -> true
        _ -> false
      end
    end)
  end

  defp season_started?(org, viewer, episodes) do
    Enum.any?(episodes, fn ep ->
      case get_progress(org, viewer, ep.video) do
        nil -> false
        _ -> true
      end
    end)
  end

  defp most_recent_progress_in_season(%Organization{id: org_id}, %{id: viewer_id}, season_id) do
    Progress
    |> where(organization_id: ^org_id, viewer_id: ^viewer_id)
    |> join(:inner, [p], e in Episode, on: e.video_id == p.video_id and e.season_id == ^season_id)
    |> order_by(desc: :updated_at)
    |> limit(1)
    |> Repo.one()
  end

  # Standalone items (series_id == nil) are never collapsed; series-bound
  # items keep only the most recent representative per series.
  defp deduplicate_by_series(items) do
    {standalone, series_items} = Enum.split_with(items, &is_nil(&1.series_id))

    deduped =
      series_items
      |> Enum.group_by(& &1.series_id)
      |> Enum.map(fn {_id, group} ->
        Enum.max_by(group, & &1.last_activity_at, DateTime)
      end)

    standalone ++ deduped
  end

  ## -----------------------------------------------------------------------
  ## Batch engagement state (for card UI)
  ## -----------------------------------------------------------------------

  @doc """
  Returns a MapSet of video IDs the viewer has favorited (non-deleted).

  Exempt from doctest — hits the database.
  """
  def favorited_video_ids(%Organization{id: org_id}, %{id: viewer_id}) do
    Favorite
    |> where(organization_id: ^org_id, viewer_id: ^viewer_id)
    |> where([f], is_nil(f.deleted_at))
    |> select([f], f.video_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Returns a MapSet of video IDs in the viewer's watchlist (non-deleted).

  Exempt from doctest — hits the database.
  """
  def watchlisted_video_ids(%Organization{id: org_id}, %{id: viewer_id}) do
    WatchlistItem
    |> where(organization_id: ^org_id, viewer_id: ^viewer_id)
    |> where([w], is_nil(w.deleted_at))
    |> select([w], w.video_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Returns a MapSet of video IDs in the viewer's queue.

  Exempt from doctest — hits the database.
  """
  def queued_video_ids(%Organization{id: org_id}, %{id: viewer_id}) do
    QueueItem
    |> where(organization_id: ^org_id, viewer_id: ^viewer_id)
    |> select([q], q.video_id)
    |> Repo.all()
    |> MapSet.new()
  end

  ## -----------------------------------------------------------------------
  ## Playback progress
  ## -----------------------------------------------------------------------

  @doc """
  Returns the lightweight watch-session state needed to bootstrap the watch page.

  Uses a single query for viewer-specific booleans and counters, then overlays
  any fresher buffered progress in memory so reconnects do not miss recent
  playback state.
  """
  def get_watch_session_state(%Organization{id: org_id}, %{id: viewer_id}, %{id: video_id}) do
    state =
      Organization
      |> where([o], o.id == ^org_id)
      |> select([_o], %{
        resume_position:
          fragment(
            """
            COALESCE(
              (
                SELECT p.position
                FROM progresses AS p
                WHERE p.organization_id = ? AND p.viewer_id = ? AND p.video_id = ?
                LIMIT 1
              ),
              0.0
            )
            """,
            type(^org_id, :binary_id),
            type(^viewer_id, :binary_id),
            type(^video_id, :binary_id)
          ),
        queue_count:
          fragment(
            """
            COALESCE(
              (
                SELECT COUNT(*)
                FROM queue_items AS q
                WHERE q.organization_id = ? AND q.viewer_id = ?
              ),
              0
            )
            """,
            type(^org_id, :binary_id),
            type(^viewer_id, :binary_id)
          ),
        is_favorited:
          fragment(
            """
            EXISTS (
              SELECT 1
              FROM favorites AS f
              WHERE f.organization_id = ?
                AND f.viewer_id = ?
                AND f.video_id = ?
                AND f.deleted_at IS NULL
            )
            """,
            type(^org_id, :binary_id),
            type(^viewer_id, :binary_id),
            type(^video_id, :binary_id)
          ),
        in_watchlist:
          fragment(
            """
            EXISTS (
              SELECT 1
              FROM watchlist_items AS w
              WHERE w.organization_id = ?
                AND w.viewer_id = ?
                AND w.video_id = ?
                AND w.deleted_at IS NULL
            )
            """,
            type(^org_id, :binary_id),
            type(^viewer_id, :binary_id),
            type(^video_id, :binary_id)
          )
      })
      |> Repo.one() ||
        %{resume_position: 0.0, queue_count: 0, is_favorited: false, in_watchlist: false}

    buffered_resume_position =
      case ProgressBuffer.get_viewer(org_id, viewer_id, video_id) do
        %{position: position} -> position
        _ -> state.resume_position
      end

    %{state | resume_position: buffered_resume_position}
  end

  @doc """
  Updates playback progress via the buffer (not direct DB write).

  Exempt from doctest — writes to buffer.
  """
  def update_progress(scope, video_id, position) when is_map(scope) and is_number(position) do
    case scope do
      %{organization: %{id: org_id}, user: %{id: user_id}} ->
        ProgressBuffer.update(org_id, user_id, video_id, position / 1)

      _ ->
        :ok
    end
  end

  @doc """
  Updates playback progress for a viewer with duration tracking and completion detection.

  Uses the progress buffer for the position write. Checks for completion
  at 99% threshold.

  Exempt from doctest — writes to buffer/database.
  """
  def update_progress(
        %Organization{id: org_id},
        %{id: viewer_id},
        video_id,
        position,
        duration
      )
      when is_number(position) and is_number(duration) do
    ProgressBuffer.update_viewer(org_id, viewer_id, video_id, position / 1, duration)
    :ok
  end

  @doc """
  Gets the saved playback progress for a user+video pair.

  Checks the buffer first, falls back to the database.

  Exempt from doctest — reads buffer and database.
  """
  def get_progress(scope, video_id) when is_map(scope) and not is_struct(scope, Organization) do
    org_id = scope.organization.id
    user_id = scope.user.id

    case ProgressBuffer.get(org_id, user_id, video_id) do
      nil ->
        Repo.get_by(Progress,
          organization_id: org_id,
          user_id: user_id,
          video_id: video_id
        )

      position ->
        %Progress{position: position, completed: false}
    end
  end

  @doc """
  Gets the saved progress for a viewer+video pair.

  Exempt from doctest — reads buffer and database.
  """
  def get_progress(%Organization{id: org_id}, %{id: viewer_id}, video) do
    case ProgressBuffer.get_viewer(org_id, viewer_id, video.id) do
      %{position: position, duration: duration} ->
        %Progress{position: position, duration: duration, completed: false}

      nil ->
        Repo.get_by(Progress,
          organization_id: org_id,
          viewer_id: viewer_id,
          video_id: video.id
        )
    end
  end

  @doc """
  Gets progress for multiple videos in a single query.
  Returns a map of %{video_id => %Progress{}}.

  Exempt from doctest — hits the database.
  """
  def batch_get_progress(%Organization{id: org_id}, %{id: viewer_id}, video_ids)
      when is_list(video_ids) do
    Progress
    |> where(organization_id: ^org_id, viewer_id: ^viewer_id)
    |> where([p], p.video_id in ^video_ids)
    |> Repo.all()
    |> Map.new(&{&1.video_id, &1})
  end

  @doc """
  Marks a video as completed.

  Exempt from doctest — hits the database.
  """
  def mark_completed(%Organization{} = org, %{id: viewer_id} = viewer, video) do
    Bobine.Otel.with_span "bobine.engagement.mark_completed",
                          %{"bobine.org.id" => org.id} do
      ProgressBuffer.delete_viewer(org.id, viewer_id, video.id)

      # Update or create progress record
      case Repo.get_by(Progress,
             organization_id: org.id,
             viewer_id: viewer_id,
             video_id: video.id
           ) do
        %Progress{} = progress ->
          progress
          |> Ecto.Changeset.change(completed: true)
          |> Repo.update()

        nil ->
          %Progress{
            organization_id: org.id,
            viewer_id: viewer_id,
            video_id: video.id,
            position: 0.0,
            completed: true
          }
          |> Repo.insert()
      end

      # Record completion in watch history
      record_watch_activity(org, viewer, video)

      # Broadcast for UI
      Events.broadcast(
        nil,
        {:video_completed, %{organization: org, viewer: viewer, video: video}}
      )

      Metrics.video_completed(org.id, video.id)
      :ok
    end
  end

  ## -----------------------------------------------------------------------
  ## Playback drop-offs
  ## -----------------------------------------------------------------------

  @doc """
  Records a playback drop-off event for later aggregation.

  The caller provides the viewer (or user), the video, the max position
  reached in the session, and the video duration. The event is stored raw
  and processed by `Bobine.Workers.DropOffAggregator` after the 1-hour
  return window has elapsed.

  Completed watches should not be recorded — the player is responsible for
  skipping drop-off events when playback reaches the end. The aggregator
  also double-checks the completed flag before counting.

  Accepts a map with string or atom keys so LiveView events can be routed
  directly without conversion.

  Returns `{:ok, drop_off}` or `{:error, :validation, changeset}`.

  Exempt from doctest — hits the database.
  """
  def record_drop_off(attrs) when is_map(attrs) do
    Bobine.Otel.with_span "bobine.engagement.record_drop_off",
                          %{
                            "bobine.org.id" => fetch_attr(attrs, :organization_id),
                            "bobine.video.id" => fetch_attr(attrs, :video_id)
                          } do
      max_position = fetch_attr(attrs, :max_position) |> to_float_or_zero()

      full_attrs =
        attrs
        |> normalize_attrs()
        |> Map.put(:bucket, PlaybackDropOff.bucket_for(max_position))
        |> Map.put(:max_position, max_position)
        |> Map.put_new(:left_at, DateTime.utc_now() |> DateTime.truncate(:second))

      case %PlaybackDropOff{} |> PlaybackDropOff.changeset(full_attrs) |> Repo.insert() do
        {:ok, drop_off} ->
          Metrics.drop_off_recorded(drop_off.organization_id, drop_off.video_id)
          {:ok, drop_off}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  defp fetch_attr(attrs, key) when is_atom(key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp normalize_attrs(attrs) do
    [:organization_id, :video_id, :viewer_id, :user_id, :video_duration]
    |> Enum.reduce(%{}, fn key, acc ->
      case fetch_attr(attrs, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp to_float_or_zero(nil), do: 0.0
  defp to_float_or_zero(n) when is_integer(n), do: n * 1.0
  defp to_float_or_zero(n) when is_float(n), do: n

  defp to_float_or_zero(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end
end
