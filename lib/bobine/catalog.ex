defmodule Bobine.Catalog do
  @moduledoc """
  The Catalog context.

  Manages homepage rows, row items, and content resolution for viewer-facing
  catalog pages. Rows define the layout; each row resolves its content based
  on its source type (curated, collection, tag, recent, popular, continue_watching).
  """

  import Ecto.Query, warn: false

  alias Bobine.Repo
  alias Bobine.Pagination
  alias Bobine.Events
  alias Bobine.Audit
  alias Bobine.Cache
  alias Bobine.Content
  alias Bobine.Accounts.Organization

  require Bobine.Otel

  alias Bobine.Catalog.{Row, RowItem}

  ## -----------------------------------------------------------------------
  ## Rows
  ## -----------------------------------------------------------------------

  @doc """
  Returns a paginated list of rows for an organization, excluding soft-deleted.

  Exempt from doctest — hits the database.
  """
  def list_rows(%Organization{id: org_id}, opts \\ []) do
    Row
    |> where(organization_id: ^org_id)
    |> where([r], is_nil(r.deleted_at))
    |> order_by(asc: :position)
    |> Pagination.paginate(opts)
  end

  @doc """
  Returns visible, non-deleted rows for an organization, ordered by position.

  Exempt from doctest — hits the database.
  """
  def list_visible_rows(%Organization{id: org_id}, opts \\ []) do
    Row
    |> where(organization_id: ^org_id)
    |> where([r], is_nil(r.deleted_at))
    |> where([r], r.visible == true)
    |> order_by(asc: :position)
    |> Pagination.paginate(opts)
  end

  @doc """
  Returns the list of rows including soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_rows_including_deleted do
    Repo.all(Row)
  end

  @doc """
  Gets a single row within an organization.

  Returns `{:ok, row}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_row(%Organization{id: org_id}, id) do
    case Repo.get_by(Row, id: id, organization_id: org_id) do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  @doc """
  Gets a single row. Raises on not found.

  Exempt from doctest — hits the database.
  """
  def get_row!(id), do: Repo.get!(Row, id)

  @doc """
  Creates a row.

  Exempt from doctest — hits the database.
  """
  def create_row(scope, attrs) do
    Bobine.Otel.with_span "bobine.catalog.create_row",
                          %{"bobine.org.id" => scope.organization.id} do
      attrs = put_org_id(attrs, scope.organization.id)

      with {:ok, row} <- %Row{} |> Row.changeset(attrs) |> Repo.insert() do
        Events.broadcast(scope, {:row_created, row})
        Audit.log(scope, "row.created", row)
        {:ok, row}
      else
        {:error, changeset} -> {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Updates a row.

  Exempt from doctest — hits the database.
  """
  def update_row(scope, %Row{} = row, attrs) do
    Bobine.Otel.with_span "bobine.catalog.update_row",
                          %{"bobine.org.id" => scope.organization.id} do
      with {:ok, row} <- row |> Row.changeset(attrs) |> Repo.update() do
        Events.broadcast(scope, {:row_updated, row})
        Audit.log(scope, "row.updated", row, attrs)
        invalidate_row_cache(scope.organization.id, row.id)
        {:ok, row}
      else
        {:error, changeset} -> {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Soft-deletes a row by setting `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def delete_row(scope, %Row{} = row) do
    Bobine.Otel.with_span "bobine.catalog.delete_row",
                          %{"bobine.org.id" => scope.organization.id} do
      with {:ok, row} <-
             row
             |> Ecto.Changeset.change(
               deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
             )
             |> Repo.update() do
        Events.broadcast(scope, {:row_deleted, row})
        Audit.log(scope, "row.deleted", row)
        invalidate_row_cache(scope.organization.id, row.id)
        {:ok, row}
      end
    end
  end

  @doc """
  Restores a soft-deleted row by clearing `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def restore_row(%Row{} = row) do
    row
    |> Ecto.Changeset.change(deleted_at: nil)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking row changes.

  ## Examples

      iex> change_row(%Bobine.Catalog.Row{})
      %Ecto.Changeset{data: %Bobine.Catalog.Row{}}

  """
  def change_row(%Row{} = row, attrs \\ %{}) do
    Row.changeset(row, attrs)
  end

  @doc """
  Reorders rows by updating positions in a single transaction.

  Exempt from doctest — hits the database.
  """
  def reorder_rows(scope, ordered_ids) do
    Bobine.Otel.with_span "bobine.catalog.reorder_rows",
                          %{"bobine.org.id" => scope.organization.id} do
      Repo.transaction(fn ->
        ordered_ids
        |> Enum.with_index()
        |> Enum.each(fn {id, position} ->
          Row
          |> where(id: ^id, organization_id: ^scope.organization.id)
          |> Repo.update_all(set: [position: position])
        end)
      end)
      |> case do
        {:ok, _} ->
          Events.broadcast(scope, {:rows_reordered, ordered_ids})
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  ## -----------------------------------------------------------------------
  ## Row Items (for curated rows)
  ## -----------------------------------------------------------------------

  @doc """
  Returns a paginated list of row items (videos) for a row, ordered by position.

  Exempt from doctest — hits the database.
  """
  def list_row_items(%Organization{id: org_id}, %{id: row_id}, opts \\ []) do
    Bobine.Content.Video
    |> join(:inner, [v], ri in RowItem, on: ri.video_id == v.id and ri.row_id == ^row_id)
    |> where([v], v.organization_id == ^org_id)
    |> where([v], is_nil(v.deleted_at))
    |> where([_v, ri], is_nil(ri.deleted_at))
    |> order_by([_v, ri], asc: ri.position)
    |> Pagination.paginate(opts)
  end

  @doc """
  Adds a video to a curated row at the given position.

  Exempt from doctest — hits the database.
  """
  def add_item_to_row(scope, %Row{} = row, %Bobine.Content.Video{} = video, position \\ nil) do
    Bobine.Otel.with_span "bobine.catalog.add_item_to_row",
                          %{"bobine.org.id" => scope.organization.id} do
      position = position || next_row_item_position(row.id)

      attrs = %{
        organization_id: scope.organization.id,
        row_id: row.id,
        video_id: video.id,
        position: position
      }

      case %RowItem{} |> RowItem.changeset(attrs) |> Repo.insert() do
        {:ok, item} ->
          Events.broadcast(scope, {:row_item_added, %{row: row, video: video}})
          Audit.log(scope, "row.item_added", item)
          invalidate_row_cache(scope.organization.id, row.id)
          {:ok, item}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Removes a video from a curated row.

  Exempt from doctest — hits the database.
  """
  def remove_item_from_row(scope, %Row{} = row, %Bobine.Content.Video{} = video) do
    Bobine.Otel.with_span "bobine.catalog.remove_item_from_row",
                          %{"bobine.org.id" => scope.organization.id} do
      case Repo.get_by(RowItem, row_id: row.id, video_id: video.id) do
        nil ->
          {:error, :not_found}

        item ->
          case Repo.delete(item) do
            {:ok, _} ->
              Events.broadcast(scope, {:row_item_removed, %{row: row, video: video}})
              Audit.log(scope, "row.item_removed", item)
              invalidate_row_cache(scope.organization.id, row.id)
              :ok

            {:error, changeset} ->
              {:error, :validation, changeset}
          end
      end
    end
  end

  @doc """
  Reorders items within a curated row by updating positions in a single transaction.

  Exempt from doctest — hits the database.
  """
  def reorder_row_items(scope, %Row{} = row, ordered_video_ids) do
    Bobine.Otel.with_span "bobine.catalog.reorder_row_items",
                          %{"bobine.org.id" => scope.organization.id} do
      Repo.transaction(fn ->
        ordered_video_ids
        |> Enum.with_index()
        |> Enum.each(fn {video_id, position} ->
          RowItem
          |> where(row_id: ^row.id, video_id: ^video_id)
          |> Repo.update_all(set: [position: position])
        end)
      end)
      |> case do
        {:ok, _} ->
          Events.broadcast(scope, {:row_items_reordered, %{row: row}})
          invalidate_row_cache(scope.organization.id, row.id)
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp next_row_item_position(row_id) do
    RowItem
    |> where(row_id: ^row_id)
    |> select([ri], max(ri.position))
    |> Repo.one()
    |> case do
      nil -> 0
      max_pos -> max_pos + 1
    end
  end

  ## -----------------------------------------------------------------------
  ## Row Content Resolution
  ## -----------------------------------------------------------------------

  @doc """
  Returns the videos for a row regardless of source type.

  Exempt from doctest — hits the database.
  """
  def resolve_row_content(%Organization{} = organization, %Row{} = row, opts \\ []) do
    case row.source_type do
      :curated ->
        list_row_items(organization, row, opts)

      :collection ->
        Content.list_collection_videos(organization, %{id: row.source_id}, opts)

      :tag ->
        Content.list_videos_by_tag(organization, %{id: row.source_id}, opts)

      :recent ->
        Content.list_videos(
          organization,
          Keyword.merge(opts, order_by: [{:desc, :inserted_at}])
        )

      :popular ->
        Content.list_videos(
          organization,
          Keyword.merge(opts, order_by: [{:desc, :inserted_at}])
        )

      :continue_watching ->
        %{results: [], page: 1, per_page: 25, total: 0, total_pages: 1}
    end
  end

  @doc """
  Cached version of resolve_row_content for non-personalized rows.

  Exempt from doctest — hits the database.
  """
  def resolve_row_content_cached(%Organization{} = organization, %Row{} = row, opts \\ []) do
    case row.source_type do
      :continue_watching ->
        resolve_row_content(organization, row, opts)

      _ ->
        Cache.fetch(
          "row_content:#{organization.id}:#{row.id}",
          [ttl: :timer.minutes(1)],
          fn -> resolve_row_content(organization, row, opts) end
        )
    end
  end

  ## -----------------------------------------------------------------------
  ## Hero Items
  ## -----------------------------------------------------------------------

  alias BobineWeb.Viewer.HeroItem

  @doc """
  Builds a list of `HeroItem` structs for the homepage hero carousel.

  Uses the first visible row marked as "featured" or falls back to the most
  recent videos with Mux playback IDs.

  Exempt from doctest — hits the database.
  """
  def build_hero_items(%Organization{} = organization, opts \\ []) do
    Bobine.Otel.with_span "bobine.catalog.build_hero_items",
                          %{"bobine.org.id" => organization.id} do
      limit = Keyword.get(opts, :limit, 5)

      organization
      |> fetch_hero_videos(limit)
      |> Enum.map(&video_to_hero_item/1)
    end
  end

  defp fetch_hero_videos(organization, limit) do
    # Try to find a featured/curated row first
    case find_featured_row(organization) do
      nil ->
        # Fallback: most recent ready videos
        %{results: videos} =
          Content.list_videos(organization,
            per_page: limit,
            order_by: [{:desc, :inserted_at}]
          )

        videos

      row ->
        %{results: videos} =
          resolve_row_content_cached(organization, row, per_page: limit)

        videos
    end
  end

  defp find_featured_row(organization) do
    %{results: rows} = list_visible_rows(organization, per_page: 1)
    List.first(rows)
  end

  defp video_to_hero_item(video) do
    %HeroItem{
      id: video.id,
      background_image_url: mux_thumbnail_url(video.mux_playback_id, width: 1920, height: 1080),
      title: video.title,
      status_text: hero_status_text(video),
      metadata_text: hero_metadata_text(video),
      primary_cta_label: "Watch Now",
      primary_cta_path: "/watch/#{video.id}",
      secondary_cta_label: nil,
      secondary_cta_path: nil
    }
  end

  defp mux_thumbnail_url(nil, _opts), do: nil

  defp mux_thumbnail_url(playback_id, opts) do
    width = Keyword.get(opts, :width, 1920)
    height = Keyword.get(opts, :height, 1080)

    "https://image.mux.com/#{playback_id}/thumbnail.webp?width=#{width}&height=#{height}&fit_mode=smartcrop"
  end

  defp hero_status_text(_), do: nil

  defp hero_metadata_text(%{duration: duration}) when is_float(duration) and duration > 0 do
    total = round(duration)
    mins = div(total, 60)

    cond do
      mins >= 60 -> "#{div(mins, 60)}h #{rem(mins, 60)}m"
      mins > 0 -> "#{mins} min"
      true -> "#{total}s"
    end
  end

  defp hero_metadata_text(_), do: nil

  defp invalidate_row_cache(org_id, row_id) do
    Cache.delete("row_content:#{org_id}:#{row_id}")
  end

  defp put_org_id(attrs, org_id) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, :organization_id) -> attrs
      Map.has_key?(attrs, "organization_id") -> attrs
      has_string_keys?(attrs) -> Map.put(attrs, "organization_id", org_id)
      true -> Map.put(attrs, :organization_id, org_id)
    end
  end

  defp has_string_keys?(map) do
    map |> Map.keys() |> Enum.any?(&is_binary/1)
  end
end
