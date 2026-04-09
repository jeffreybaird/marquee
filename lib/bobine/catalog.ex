defmodule Bobine.Catalog do
  @moduledoc """
  The Catalog context.

  Manages homepage rows, row items, and content resolution for viewer-facing
  catalog pages. Rows define the layout; each row resolves its content based
  on its source type (curated, collection, tag, recent, popular, continue_watching).
  """

  import Ecto.Query, warn: false

  alias Bobine.Accounts.Organization
  alias Bobine.Audit
  alias Bobine.Cache
  alias Bobine.Catalog.{HeroSlide, Row, RowItem}
  alias Bobine.Content
  alias Bobine.Content.{CollectionItem, Video}
  alias Bobine.Events
  alias Bobine.Pagination
  alias Bobine.Repo

  require Bobine.Otel

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

      case %Row{} |> Row.changeset(attrs) |> Repo.insert() do
        {:ok, row} ->
          Events.broadcast(scope, {:row_created, row})
          Audit.log(scope, "row.created", row)
          {:ok, row}

        {:error, changeset} ->
          {:error, :validation, changeset}
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
      case row |> Row.changeset(attrs) |> Repo.update() do
        {:ok, row} ->
          Events.broadcast(scope, {:row_updated, row})
          Audit.log(scope, "row.updated", row, attrs)
          invalidate_row_cache(scope.organization.id, row.id)

          if row.source_type == :hero do
            invalidate_hero_cache(scope.organization.id)
          end

          {:ok, row}

        {:error, changeset} ->
          {:error, :validation, changeset}
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
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def resolve_row_content(%Organization{} = organization, %Row{} = row, opts \\ []) do
    case row.source_type do
      :curated ->
        list_row_items(organization, row, opts)

      :collection ->
        Content.list_collection_items(organization, %{id: row.source_id}, opts)

      :tag ->
        Content.list_videos_by_tag(organization, %{id: row.source_id}, opts)

      :recent ->
        Content.list_videos(
          organization,
          Keyword.merge(opts, order_by: [{:desc, :inserted_at}], exclude_episodes: true)
        )

      :popular ->
        Content.list_videos(
          organization,
          Keyword.merge(opts, order_by: [{:desc, :inserted_at}], exclude_episodes: true)
        )

      :continue_watching ->
        viewer = Keyword.get(opts, :viewer)

        if viewer do
          Bobine.Engagement.list_continue_watching(organization, viewer, per_page: row.max_items)
        else
          %{results: [], page: 1, per_page: 25, total: 0, total_pages: 1}
        end

      :new_seasons ->
        resolve_new_seasons(organization, row, opts)

      :hero ->
        # Hero rows resolve their content through resolve_hero_slides/1, not here
        %{results: [], page: 1, per_page: 25, total: 0, total_pages: 1}
    end
  end

  defp resolve_new_seasons(%Organization{id: org_id}, %Row{} = row, opts) do
    Bobine.Otel.with_span "bobine.catalog.resolve_new_seasons",
                          %{"bobine.org.id" => org_id} do
      limit = Keyword.get(opts, :per_page) || row.max_items || 20
      now = DateTime.utc_now()

      seasons_query =
        from s in Bobine.Content.Season,
          where: is_nil(s.deleted_at),
          order_by: [asc: s.season_number]

      results =
        Bobine.Content.Series
        |> where(organization_id: ^org_id)
        |> where([s], is_nil(s.deleted_at))
        |> where([s], s.visible == true and s.new_season == true)
        |> where([s], is_nil(s.new_season_expires_at) or s.new_season_expires_at > ^now)
        |> order_by(desc: :updated_at)
        |> limit(^limit)
        |> preload(seasons: ^seasons_query)
        |> Repo.all()

      %{
        results: results,
        page: 1,
        per_page: limit,
        total: length(results),
        total_pages: 1
      }
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

  @doc """
  Cached version of resolve_row_content_as_videos. Bypasses cache for
  personalized rows (`:continue_watching`).

  Exempt from doctest — hits the database.
  """
  def resolve_row_content_as_videos_cached(
        %Organization{} = organization,
        %Row{} = row,
        opts \\ []
      ) do
    case row.source_type do
      :continue_watching ->
        resolve_row_content_as_videos(organization, row, opts)

      _ ->
        Cache.fetch(
          "row_content_videos:#{organization.id}:#{row.id}",
          [ttl: :timer.minutes(1)],
          fn -> resolve_row_content_as_videos(organization, row, opts) end
        )
    end
  end

  @doc """
  Resolves row content as a flat list of videos.

  For collection rows, seasons are expanded to their episode videos and series
  are expanded to all season episode videos. Non-collection rows pass through
  unchanged. Use this for contexts that need a flat video list (e.g. the
  existing content card renderer).

  Exempt from doctest — hits the database.
  """
  def resolve_row_content_as_videos(%Organization{} = organization, %Row{} = row, opts \\ []) do
    result = resolve_row_content(organization, row, opts)

    videos = Enum.flat_map(result.results, &flatten_item_to_videos(organization, &1))
    %{result | results: videos}
  end

  defp flatten_item_to_videos(_org, %CollectionItem{item_type: :video, video: video}), do: [video]

  defp flatten_item_to_videos(org, %CollectionItem{item_type: :season, season: season}) do
    Content.list_episodes(org, season) |> Enum.map(& &1.video)
  end

  defp flatten_item_to_videos(org, %CollectionItem{item_type: :series, series: series}) do
    Content.list_seasons(org, series).results
    |> Enum.flat_map(fn s -> Content.list_episodes(org, s) |> Enum.map(& &1.video) end)
  end

  defp flatten_item_to_videos(_org, %Video{} = video), do: [video]
  defp flatten_item_to_videos(_org, _), do: []

  @doc """
  Loads catalog rows with their resolved content for the viewer-facing homepage.

  Fetches visible rows, excludes hero rows (which render separately), resolves
  each row's video content via cache, and filters out rows with no results.

  Accepts an `%Organization{}` and optional keyword opts. Supported opts include
  `:viewer` for personalized rows like `:continue_watching`.

  Returns a list of `%{row: row, videos: videos}` maps.

  Exempt from doctest — hits the database.
  """
  def load_catalog_rows_with_content(%Organization{} = organization, opts \\ []) do
    %{results: rows} = list_visible_rows(organization, per_page: 100)

    rows
    |> Enum.reject(&(&1.source_type == :hero))
    |> Enum.map(fn row ->
      row_opts = opts |> Keyword.put(:per_page, row.max_items)

      %{results: videos} =
        resolve_row_content_as_videos_cached(organization, row, row_opts)

      %{row: row, videos: videos}
    end)
    |> Enum.reject(fn %{videos: videos} -> Enum.empty?(videos) end)
  end

  @doc """
  Loads catalog rows with their resolved content as a polymorphic item list.

  Unlike `load_catalog_rows_with_content/2` (which flattens everything to a
  list of videos), this returns mixed items per row — videos, series, and
  seasons — so the renderer can dispatch on item type and show series cards
  alongside video cards.

  CollectionItems are unwrapped to their underlying entity (Video / Season / Series).
  Rows whose `source_type` is `:hero` are excluded; empty rows are filtered out.

  Returns a list of `%{row: row, items: items}` maps.

  Exempt from doctest — hits the database.
  """
  def load_catalog_rows_with_items(%Organization{} = organization, opts \\ []) do
    %{results: rows} = list_visible_rows(organization, per_page: 100)

    rows
    |> Enum.reject(&(&1.source_type == :hero))
    |> Enum.map(fn row ->
      row_opts = opts |> Keyword.put(:per_page, row.max_items)

      %{results: results} = resolve_row_content_cached(organization, row, row_opts)

      items = Enum.map(results, &unwrap_row_item/1)
      %{row: row, items: items}
    end)
    |> Enum.reject(fn %{items: items} -> Enum.empty?(items) end)
  end

  defp unwrap_row_item(%CollectionItem{item_type: :video, video: video}), do: video
  defp unwrap_row_item(%CollectionItem{item_type: :season, season: season}), do: season
  defp unwrap_row_item(%CollectionItem{item_type: :series, series: series}), do: series
  defp unwrap_row_item(item), do: item

  @doc """
  Lists hero slides enriched with their associated video title and description.

  Accepts an `%Organization{}` and a hero `%Row{}`. Returns a list of maps
  containing all slide fields plus `video_title` and `video_description`
  from the linked video.

  Exempt from doctest — hits the database.
  """
  def list_enriched_hero_slides(%Organization{} = organization, %Row{} = hero_row) do
    organization
    |> list_hero_slides(hero_row)
    |> Enum.map(fn slide ->
      video = Content.get_video!(slide.video_id)

      %{
        id: slide.id,
        position: slide.position,
        video_id: slide.video_id,
        video_title: video.title,
        video_description: video.description,
        headline: slide.headline,
        subheadline: slide.subheadline,
        brand_tag: slide.brand_tag,
        description: slide.description,
        primary_cta_label: slide.primary_cta_label,
        secondary_cta_label: slide.secondary_cta_label,
        background_image_url: slide.background_image_url
      }
    end)
  end

  ## -----------------------------------------------------------------------
  ## Hero Row
  ## -----------------------------------------------------------------------

  @doc """
  Gets the hero row for an organization. Each org can have at most one.

  Returns `{:ok, row}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_hero_row(%Organization{id: org_id}) do
    Row
    |> where(organization_id: ^org_id, source_type: :hero)
    |> where([r], is_nil(r.deleted_at))
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  @doc """
  Creates a hero row. Returns `{:error, :already_exists}` if one already exists.

  Exempt from doctest — hits the database.
  """
  def create_hero_row(scope, attrs) do
    case get_hero_row(scope.organization) do
      {:ok, _existing} ->
        {:error, :already_exists}

      {:error, :not_found} ->
        attrs =
          attrs
          |> Map.merge(%{source_type: :hero, visible: true})
          |> Map.put_new(:title, "Hero")

        create_row(scope, attrs)
    end
  end

  ## -----------------------------------------------------------------------
  ## Hero Slides
  ## -----------------------------------------------------------------------

  @hero_slide_limit 4

  @doc """
  Lists hero slides for a hero row, ordered by position.
  Excludes soft-deleted slides.

  Exempt from doctest — hits the database.
  """
  def list_hero_slides(%Organization{id: org_id}, %Row{id: row_id}) do
    HeroSlide
    |> where(organization_id: ^org_id, row_id: ^row_id)
    |> where([s], is_nil(s.deleted_at))
    |> order_by(asc: :position)
    |> Repo.all()
  end

  @doc """
  Creates a hero slide. Enforces max 4 slides per hero row.

  Returns `{:error, :hero_limit_reached, %{limit: 4, current: n}}` if at capacity.

  Exempt from doctest — hits the database.
  """
  def create_hero_slide(scope, %Row{} = row, attrs) do
    Bobine.Otel.with_span "bobine.catalog.create_hero_slide",
                          %{"bobine.org.id" => scope.organization.id} do
      current_count = count_active_hero_slides(scope.organization, row)

      if current_count >= @hero_slide_limit do
        {:error, :hero_limit_reached, %{limit: @hero_slide_limit, current: current_count}}
      else
        position = Map.get(attrs, :position, current_count)

        %HeroSlide{organization_id: scope.organization.id, row_id: row.id}
        |> HeroSlide.changeset(Map.put(attrs, :position, position))
        |> Repo.insert()
        |> case do
          {:ok, slide} ->
            Events.broadcast(scope, {:hero_slide_created, slide})
            Audit.log(scope, "hero_slide.created", slide)
            invalidate_hero_cache(scope.organization.id)
            {:ok, slide}

          {:error, changeset} ->
            {:error, :validation, changeset}
        end
      end
    end
  end

  @doc """
  Updates a hero slide's custom text fields or background image.

  Exempt from doctest — hits the database.
  """
  def update_hero_slide(scope, %HeroSlide{} = slide, attrs) do
    Bobine.Otel.with_span "bobine.catalog.update_hero_slide",
                          %{"bobine.org.id" => scope.organization.id} do
      slide
      |> HeroSlide.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          Events.broadcast(scope, {:hero_slide_updated, updated})
          Audit.log(scope, "hero_slide.updated", updated, attrs)
          invalidate_hero_cache(scope.organization.id)
          {:ok, updated}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Soft-deletes a hero slide.

  Exempt from doctest — hits the database.
  """
  def delete_hero_slide(scope, %HeroSlide{} = slide) do
    Bobine.Otel.with_span "bobine.catalog.delete_hero_slide",
                          %{"bobine.org.id" => scope.organization.id} do
      slide
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update()
      |> case do
        {:ok, deleted} ->
          Events.broadcast(scope, {:hero_slide_deleted, deleted})
          Audit.log(scope, "hero_slide.deleted", deleted)
          invalidate_hero_cache(scope.organization.id)
          {:ok, deleted}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Reorders hero slides within the hero row.

  Exempt from doctest — hits the database.
  """
  def reorder_hero_slides(scope, %Row{} = row, ordered_slide_ids) do
    Bobine.Otel.with_span "bobine.catalog.reorder_hero_slides",
                          %{"bobine.org.id" => scope.organization.id} do
      Repo.transaction(fn ->
        ordered_slide_ids
        |> Enum.with_index()
        |> Enum.each(fn {slide_id, position} ->
          HeroSlide
          |> where(id: ^slide_id, row_id: ^row.id)
          |> Repo.update_all(set: [position: position])
        end)
      end)
      |> case do
        {:ok, _} ->
          Events.broadcast(scope, {:hero_slides_reordered, %{row: row}})
          invalidate_hero_cache(scope.organization.id)
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking hero slide changes.

  Exempt from doctest — changeset building only.
  """
  def change_hero_slide(%HeroSlide{} = slide, attrs \\ %{}) do
    HeroSlide.changeset(slide, attrs)
  end

  @doc """
  Gets a single hero slide within an organization.

  Returns `{:ok, slide}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_hero_slide(%Organization{id: org_id}, id) do
    case Repo.get_by(HeroSlide, id: id, organization_id: org_id) do
      nil -> {:error, :not_found}
      slide -> {:ok, slide}
    end
  end

  defp count_active_hero_slides(%Organization{id: org_id}, %Row{id: row_id}) do
    HeroSlide
    |> where(organization_id: ^org_id, row_id: ^row_id)
    |> where([s], is_nil(s.deleted_at))
    |> Repo.aggregate(:count)
  end

  ## -----------------------------------------------------------------------
  ## Resolve Hero Slides for Viewer
  ## -----------------------------------------------------------------------

  @doc """
  Returns resolved hero slides for rendering. Custom text fields fall back
  to the linked video's data when blank.

  Returns a list of maps with all slide data needed for rendering.

  Exempt from doctest — hits the database.
  """
  def resolve_hero_slides(%Organization{} = organization) do
    Bobine.Otel.with_span "bobine.catalog.resolve_hero_slides",
                          %{"bobine.org.id" => organization.id} do
      case get_hero_row(organization) do
        {:ok, %Row{visible: true} = row} ->
          slides =
            row
            |> then(&list_hero_slides(organization, &1))
            |> Enum.map(fn slide ->
              video = Content.get_video!(slide.video_id)
              resolve_slide_with_fallbacks(slide, video)
            end)

          auto_advance_ms = get_in(row.filter_config || %{}, ["auto_advance_ms"]) || 8000

          %{slides: slides, auto_advance_ms: auto_advance_ms}

        _ ->
          %{slides: [], auto_advance_ms: 8000}
      end
    end
  end

  @doc """
  Cached version of `resolve_hero_slides/1`. Invalidated when hero slides
  or the hero row are modified.

  Exempt from doctest — hits the database.
  """
  def resolve_hero_slides_cached(%Organization{} = organization) do
    Cache.fetch(
      "hero:#{organization.id}",
      [ttl: :timer.minutes(2)],
      fn -> resolve_hero_slides(organization) end
    )
  end

  defp resolve_slide_with_fallbacks(slide, video) do
    %{
      id: slide.id,
      video_id: video.id,
      background_image_url: slide.background_image_url || mux_hero_thumbnail(video),
      headline: presence(slide.headline) || video.title,
      subheadline: slide.subheadline,
      brand_tag: slide.brand_tag,
      description: presence(slide.description) || video.description,
      primary_cta_label: presence(slide.primary_cta_label) || "Watch now",
      primary_cta_path: "/watch/#{video.id}",
      secondary_cta_label: presence(slide.secondary_cta_label) || "More info",
      secondary_cta_path: "/watch/#{video.id}"
    }
  end

  defp mux_hero_thumbnail(%{mux_playback_id: nil}), do: nil

  defp mux_hero_thumbnail(%{mux_playback_id: playback_id}) do
    "https://image.mux.com/#{playback_id}/thumbnail.webp?width=1920&height=1080&fit_mode=smartcrop"
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(str) when is_binary(str), do: str

  defp invalidate_hero_cache(org_id) do
    Cache.delete("hero:#{org_id}")
  end

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
