defmodule Bobine.Content do
  @moduledoc """
  The Content context.

  Manages videos, collections, tags, and the relationships between them.
  All operations are scoped to an organization for multi-tenant isolation.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Bobine.Accounts.Organization
  alias Bobine.Audit
  alias Bobine.Cache
  alias Bobine.Events
  alias Bobine.Pagination
  alias Bobine.Repo

  require Bobine.Otel

  alias Bobine.Content.{Collection, CollectionItem, Episode, Season, Series, Tag, Video, VideoTag}
  alias Bobine.PlatformBilling.UsageLimits

  ## -----------------------------------------------------------------------
  ## Video queries
  ## -----------------------------------------------------------------------

  @doc """
  Returns a paginated list of videos for an organization, excluding soft-deleted.

  Exempt from doctest — hits the database.
  """
  def list_videos(%Organization{id: org_id}, opts \\ []) do
    Video
    |> where(organization_id: ^org_id)
    |> where([v], is_nil(v.deleted_at))
    |> apply_video_search(Keyword.get(opts, :search))
    |> apply_video_episode_exclusion(Keyword.get(opts, :exclude_episodes, false))
    |> apply_video_order(opts)
    |> Pagination.paginate(opts)
  end

  defp apply_video_episode_exclusion(query, true), do: exclude_episode_videos(query)
  defp apply_video_episode_exclusion(query, _), do: query

  defp apply_video_search(query, nil), do: query

  defp apply_video_search(query, term) do
    pattern = "%#{term}%"
    where(query, [v], ilike(v.title, ^pattern))
  end

  defp apply_video_order(query, opts) do
    case Keyword.get(opts, :order_by) do
      [{dir, field}] -> order_by(query, [{^dir, ^field}])
      _ -> apply_video_order_legacy(query, Keyword.get(opts, :order, :newest))
    end
  end

  defp apply_video_order_legacy(query, :oldest), do: order_by(query, asc: :inserted_at)
  defp apply_video_order_legacy(query, :alphabetical), do: order_by(query, asc: :title)
  defp apply_video_order_legacy(query, _newest), do: order_by(query, desc: :inserted_at)

  @doc """
  Returns the list of videos for an organization, including soft-deleted
  records.

  Exempt from doctest — hits the database.
  """
  def list_videos_including_deleted(%Organization{id: org_id}) do
    Video
    |> where(organization_id: ^org_id)
    |> Repo.all()
  end

  @doc """
  Gets a single video by ID within an organization.

  Returns `{:ok, video}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_video(%Organization{id: org_id}, id) do
    case Repo.get_by(Video, id: id, organization_id: org_id) do
      nil -> {:error, :not_found}
      video -> {:ok, video}
    end
  end

  @doc """
  Gets a single video in an organization. Raises on not found.

  Exempt from doctest — hits the database.
  """
  def get_video!(%Organization{id: org_id}, id) do
    Repo.get_by!(Video, id: id, organization_id: org_id)
  end

  @doc """
  Returns the `organization_id` for the video identified by its
  Mux asset id, or `nil` when no video matches.

  Cross-tenant lookup — intended for webhook routing when the tenant
  context has not yet been established.

  Exempt from doctest — hits the database.
  """
  def get_organization_id_by_mux_asset_id(mux_asset_id) when is_binary(mux_asset_id) do
    Video
    |> where([v], v.mux_asset_id == ^mux_asset_id)
    |> select([v], v.organization_id)
    |> Repo.one()
  end

  def get_organization_id_by_mux_asset_id(_), do: nil

  @doc """
  Returns the `organization_id` for the video identified by its
  Mux upload id, or `nil` when no video matches.

  Cross-tenant lookup — intended for webhook routing when the tenant
  context has not yet been established.

  Exempt from doctest — hits the database.
  """
  def get_organization_id_by_mux_upload_id(mux_upload_id) when is_binary(mux_upload_id) do
    Video
    |> where([v], v.mux_upload_id == ^mux_upload_id)
    |> select([v], v.organization_id)
    |> Repo.one()
  end

  def get_organization_id_by_mux_upload_id(_), do: nil

  @doc """
  Returns a small related-video set for the watch page without running the
  paginator's extra count query. Results are cached briefly because the watch
  page reads this on both the initial HTTP render and the LiveView connect.

  Exempt from doctest — hits cache/database.
  """
  def list_related_videos_for_watch(%Organization{id: org_id}, %Video{id: video_id}, limit \\ 8) do
    cache_key = "watch_related:#{org_id}:#{video_id}:#{limit}"

    case Cache.get(cache_key) do
      {:ok, videos} ->
        %{videos: videos, cache_status: :hit, query_count: 0, db_duration_ms: 0}

      :miss ->
        {db_duration_ms, videos} =
          timed(fn ->
            Video
            |> where(organization_id: ^org_id)
            |> where([v], is_nil(v.deleted_at))
            |> where([v], v.mux_status == "ready")
            |> where([v], v.id != ^video_id)
            |> order_by(desc: :inserted_at)
            |> limit(^limit)
            |> Repo.all()
          end)

        Cache.put(cache_key, videos, ttl: 60_000)

        %{
          videos: videos,
          cache_status: :miss,
          query_count: 1,
          db_duration_ms: db_duration_ms
        }
    end
  end

  ## -----------------------------------------------------------------------
  ## Video upload flow
  ## -----------------------------------------------------------------------

  @doc """
  Creates a Mux direct upload URL and a video record in waiting status.

  Returns `{:ok, %{video: video, upload_url: url}}` or an error tuple.

  Exempt from doctest — calls Mux API.
  """
  def create_upload_url(scope, attrs, opts \\ []) do
    if UsageLimits.can_upload_video?(scope.organization) do
      do_create_upload_url(scope, attrs, opts)
    else
      limit_status = UsageLimits.video_limit_status(scope.organization)
      {:error, :plan_limit_reached, limit_status}
    end
  end

  defp do_create_upload_url(scope, attrs, opts) do
    mux_upload_params =
      build_mux_upload_params(scope.organization, Keyword.get(opts, :current_origin))

    Bobine.Otel.with_span "bobine.content.create_upload_url",
                          %{"bobine.org.id" => scope.organization.id} do
      Logger.info("Creating Mux direct upload",
        org_id: scope.organization.id,
        user_id: scope.user.id,
        title: inspect(attrs[:title] || attrs["title"]),
        mux_upload_params: inspect(mux_upload_params, pretty: true, limit: :infinity)
      )

      with {:ok, upload} <- mux_client().create_direct_upload(mux_upload_params),
           {:ok, video} <- create_video_record(scope, attrs, upload) do
        Events.broadcast(scope, {:video_upload_initiated, video})
        Bobine.Metrics.video_upload_initiated(scope.organization.id)
        {:ok, %{video: video, upload_url: upload_url_from(upload)}}
      else
        {:error, :mux_error, reason} = error ->
          Logger.error("Failed to create Mux direct upload",
            org_id: scope.organization.id,
            user_id: scope.user.id,
            title: inspect(attrs[:title] || attrs["title"]),
            reason: inspect(reason, pretty: true, limit: :infinity),
            mux_upload_params: inspect(mux_upload_params, pretty: true, limit: :infinity)
          )

          error

        other ->
          other
      end
    end
  end

  defp create_video_record(scope, attrs, upload) do
    title = attrs[:title] || attrs["title"] || "Untitled"

    %Video{}
    |> Video.changeset(%{
      organization_id: scope.organization.id,
      title: title,
      description: attrs[:description] || attrs["description"],
      slug: slugify(title),
      mux_upload_id: upload_id_from(upload),
      mux_status: "waiting"
    })
    |> Repo.insert()
    |> case do
      {:ok, video} -> {:ok, video}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  defp upload_url_from(%{"url" => url}), do: url
  defp upload_url_from(%{url: url}), do: url
  defp upload_url_from(upload), do: Map.get(upload, "url") || Map.get(upload, :url)

  defp upload_id_from(%{"id" => id}), do: id
  defp upload_id_from(%{id: id}), do: id
  defp upload_id_from(upload), do: Map.get(upload, "id") || Map.get(upload, :id)

  defp build_mux_upload_params(org, current_origin) do
    %{
      cors_origin: build_cors_origin(org, current_origin),
      new_asset_settings: %{
        playback_policy: ["public"],
        video_quality: mux_video_quality()
      }
    }
  end

  defp mux_video_quality do
    Application.get_env(:bobine, :mux_video_quality, "plus")
  end

  defp build_cors_origin(org, current_origin) do
    case Application.get_env(:bobine, :cors_origin) do
      nil -> prod_cors_origin(org)
      "*" -> current_origin || default_dev_cors_origin()
      origin -> origin
    end
  end

  defp prod_cors_origin(%{custom_domain: domain}) when is_binary(domain) and domain != "",
    do: "https://#{domain}"

  defp prod_cors_origin(%{slug: slug}), do: "https://#{slug}.bobine.dev"

  defp default_dev_cors_origin, do: "http://localhost:4000"

  defp timed(fun) do
    started_at = System.monotonic_time()
    result = fun.()

    duration_ms =
      System.convert_time_unit(System.monotonic_time() - started_at, :native, :millisecond)

    {duration_ms, result}
  end

  ## -----------------------------------------------------------------------
  ## Mux webhook handlers
  ## -----------------------------------------------------------------------

  @doc """
  Links a Mux upload to its asset. Called by `video.upload.asset_ready` webhook.

  Exempt from doctest — hits the database.
  """
  def link_upload_to_asset(mux_upload_id, mux_asset_id) do
    Bobine.Otel.with_span "bobine.content.link_upload_to_asset" do
      case Repo.get_by(Video, mux_upload_id: mux_upload_id) do
        nil ->
          Logger.warning("No video found for mux upload", mux_upload_id: mux_upload_id)
          {:error, :not_found}

        video ->
          video
          |> Video.mux_status_changeset(%{mux_asset_id: mux_asset_id, mux_status: "preparing"})
          |> Repo.update()
      end
    end
  end

  @doc """
  Marks a video as ready. Called by `video.asset.ready` webhook.

  Exempt from doctest — hits the database.
  """
  def mark_video_ready(mux_asset_id, metadata) do
    Bobine.Otel.with_span "bobine.content.mark_video_ready" do
      case Repo.get_by(Video, mux_asset_id: mux_asset_id) do
        nil ->
          Logger.warning("No video found for mux asset on ready",
            mux_asset_id: mux_asset_id
          )

          {:error, :not_found}

        video ->
          attrs = %{
            mux_status: "ready",
            duration: metadata[:duration],
            max_resolution: metadata[:max_resolution],
            mux_playback_id: metadata[:playback_id]
          }

          case video |> Video.mux_status_changeset(attrs) |> Repo.update() do
            {:ok, video} ->
              org = Repo.get!(Organization, video.organization_id)
              Events.broadcast(%{organization: org}, {:video_ready, video})
              {:ok, video}

            {:error, changeset} ->
              {:error, :validation, changeset}
          end
      end
    end
  end

  @doc """
  Marks a video as errored. Called by `video.asset.errored` webhook.

  Exempt from doctest — hits the database.
  """
  def mark_video_errored(mux_asset_id, _error_details) do
    Bobine.Otel.with_span "bobine.content.mark_video_errored" do
      case Repo.get_by(Video, mux_asset_id: mux_asset_id) do
        nil ->
          Logger.warning("No video found for mux asset on error",
            mux_asset_id: mux_asset_id
          )

          {:error, :not_found}

        video ->
          case video |> Video.mux_status_changeset(%{mux_status: "errored"}) |> Repo.update() do
            {:ok, video} ->
              org = Repo.get!(Organization, video.organization_id)
              Events.broadcast(%{organization: org}, {:video_errored, video})
              {:ok, video}

            {:error, changeset} ->
              {:error, :validation, changeset}
          end
      end
    end
  end

  ## -----------------------------------------------------------------------
  ## Video CRUD
  ## -----------------------------------------------------------------------

  @doc """
  Creates a video.

  Accepts an optional scope so the broadcast + audit subscriber can
  attribute the action to the acting user/org.

  Exempt from doctest — hits the database.
  """
  def create_video(scope \\ nil, attrs) do
    Bobine.Otel.with_span "bobine.content.create_video" do
      case %Video{} |> Video.changeset(attrs) |> Repo.insert() do
        {:ok, video} ->
          Events.broadcast(scope, {:video_created, video})
          {:ok, video}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Updates a video.

  Accepts an optional scope so the broadcast + audit subscriber can
  attribute the action to the acting user/org.

  Exempt from doctest — hits the database.
  """
  def update_video(scope \\ nil, %Video{} = video, attrs) do
    Bobine.Otel.with_span "bobine.content.update_video" do
      case video |> Video.changeset(attrs) |> Repo.update() do
        {:ok, video} ->
          Events.broadcast(scope, {:video_updated, video})
          {:ok, video}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Soft-deletes a video by setting `deleted_at`.

  Accepts an optional scope so the broadcast + audit subscriber can
  attribute the action to the acting user/org.

  Exempt from doctest — hits the database.
  """
  def delete_video(scope \\ nil, %Video{} = video) do
    Bobine.Otel.with_span "bobine.content.delete_video" do
      with {:ok, video} <-
             video
             |> Ecto.Changeset.change(
               deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
             )
             |> Repo.update() do
        Events.broadcast(scope, {:video_deleted, video})
        {:ok, video}
      end
    end
  end

  @doc """
  Restores a soft-deleted video by clearing `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def restore_video(%Video{} = video) do
    video
    |> Ecto.Changeset.change(deleted_at: nil)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking video changes.

  ## Examples

      iex> change_video(%Bobine.Content.Video{})
      %Ecto.Changeset{data: %Bobine.Content.Video{}}

  """
  def change_video(%Video{} = video, attrs \\ %{}) do
    Video.changeset(video, attrs)
  end

  ## -----------------------------------------------------------------------
  ## Collections
  ## -----------------------------------------------------------------------

  @doc """
  Returns a paginated list of collections for an organization, excluding soft-deleted.

  Exempt from doctest — hits the database.
  """
  def list_collections(%Organization{id: org_id}, opts \\ []) do
    Collection
    |> where(organization_id: ^org_id)
    |> where([c], is_nil(c.deleted_at))
    |> order_by(asc: :position)
    |> Pagination.paginate(opts)
  end

  @doc """
  Returns the list of collections for an organization, including
  soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_collections_including_deleted(%Organization{id: org_id}) do
    Collection
    |> where(organization_id: ^org_id)
    |> Repo.all()
  end

  @doc """
  Gets a single collection within an organization.

  Returns `{:ok, collection}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_collection(%Organization{id: org_id}, id) do
    case Repo.get_by(Collection, id: id, organization_id: org_id) do
      nil -> {:error, :not_found}
      collection -> {:ok, collection}
    end
  end

  @doc """
  Gets a single collection within an organization. Raises on not found.

  Exempt from doctest — hits the database.
  """
  def get_collection!(%Organization{id: org_id}, id) do
    Collection
    |> where(organization_id: ^org_id)
    |> Repo.get!(id)
  end

  @doc """
  Gets a collection by slug within an organization.

  Returns `{:ok, collection}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_collection_by_slug(%Organization{id: org_id}, slug) do
    query =
      Collection
      |> where(organization_id: ^org_id, slug: ^slug)
      |> where([c], is_nil(c.deleted_at))

    case Repo.one(query) do
      nil -> {:error, :not_found}
      collection -> {:ok, collection}
    end
  end

  @doc """
  Creates a collection.

  Exempt from doctest — hits the database.
  """
  def create_collection(scope, attrs) do
    Bobine.Otel.with_span "bobine.content.create_collection",
                          %{"bobine.org.id" => scope.organization.id} do
      attrs = put_org_id(attrs, scope.organization.id)

      case %Collection{} |> Collection.changeset(attrs) |> Repo.insert() do
        {:ok, collection} ->
          Events.broadcast(scope, {:collection_created, collection})
          Audit.log(scope, "collection.created", collection)
          {:ok, collection}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Updates a collection.

  Exempt from doctest — hits the database.
  """
  def update_collection(scope, %Collection{} = collection, attrs) do
    Bobine.Otel.with_span "bobine.content.update_collection",
                          %{"bobine.org.id" => scope.organization.id} do
      case collection |> Collection.changeset(attrs) |> Repo.update() do
        {:ok, collection} ->
          Events.broadcast(scope, {:collection_updated, collection})
          Audit.log(scope, "collection.updated", collection, attrs)
          {:ok, collection}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Soft-deletes a collection by setting `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def delete_collection(scope, %Collection{} = collection) do
    Bobine.Otel.with_span "bobine.content.delete_collection",
                          %{"bobine.org.id" => scope.organization.id} do
      with {:ok, collection} <-
             collection
             |> Ecto.Changeset.change(
               deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
             )
             |> Repo.update() do
        Events.broadcast(scope, {:collection_deleted, collection})
        Audit.log(scope, "collection.deleted", collection)
        {:ok, collection}
      end
    end
  end

  @doc """
  Restores a soft-deleted collection by clearing `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def restore_collection(scope, %Collection{} = collection) do
    Bobine.Otel.with_span "bobine.content.restore_collection" do
      with {:ok, collection} <-
             collection
             |> Ecto.Changeset.change(deleted_at: nil)
             |> Repo.update() do
        Events.broadcast(scope, {:collection_updated, collection})
        {:ok, collection}
      end
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking collection changes.

  ## Examples

      iex> change_collection(%Bobine.Content.Collection{})
      %Ecto.Changeset{data: %Bobine.Content.Collection{}}

  """
  def change_collection(%Collection{} = collection, attrs \\ %{}) do
    Collection.changeset(collection, attrs)
  end

  @doc """
  Reorders collections by updating positions in a single transaction.

  Accepts a list of collection IDs in the desired display order.

  Exempt from doctest — hits the database.
  """
  def reorder_collections(scope, ordered_ids) do
    Bobine.Otel.with_span "bobine.content.reorder_collections",
                          %{"bobine.org.id" => scope.organization.id} do
      Repo.transaction(fn ->
        ordered_ids
        |> Enum.with_index()
        |> Enum.each(fn {id, position} ->
          Collection
          |> where(id: ^id, organization_id: ^scope.organization.id)
          |> Repo.update_all(set: [position: position])
        end)
      end)
      |> case do
        {:ok, _} ->
          Events.broadcast(scope, {:collections_reordered, ordered_ids})
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  ## -----------------------------------------------------------------------
  ## Collection Items (videos within a collection)
  ## -----------------------------------------------------------------------

  @doc """
  Returns a paginated list of videos in a collection, ordered by position.

  Exempt from doctest — hits the database.
  """
  def list_collection_videos(%Organization{id: org_id}, %{id: collection_id}, opts \\ []) do
    Video
    |> join(:inner, [v], ci in CollectionItem,
      on: ci.video_id == v.id and ci.collection_id == ^collection_id
    )
    |> where([v], v.organization_id == ^org_id)
    |> where([v], is_nil(v.deleted_at))
    |> order_by([_v, ci], asc: ci.position)
    |> Pagination.paginate(opts)
  end

  @doc """
  Adds a video to a collection at the given position.

  Exempt from doctest — hits the database.
  """
  def add_video_to_collection(
        scope,
        %Collection{} = collection,
        %Video{} = video,
        position \\ nil
      ) do
    Bobine.Otel.with_span "bobine.content.add_video_to_collection",
                          %{"bobine.org.id" => scope.organization.id} do
      position = position || next_collection_item_position(collection.id)

      attrs = %{
        organization_id: scope.organization.id,
        collection_id: collection.id,
        video_id: video.id,
        item_type: :video,
        position: position
      }

      case %CollectionItem{} |> CollectionItem.changeset(attrs) |> Repo.insert() do
        {:ok, item} ->
          Events.broadcast(
            scope,
            {:collection_video_added, %{collection: collection, video: video}}
          )

          Audit.log(scope, "collection.video_added", item)
          {:ok, item}

        {:error, changeset} ->
          if has_unique_constraint_error?(changeset) do
            {:error, :already_exists}
          else
            {:error, :validation, changeset}
          end
      end
    end
  end

  @doc """
  Adds a season to a collection at the given position. Sets item_type to :season.

  Exempt from doctest — hits the database.
  """
  def add_season_to_collection(
        scope,
        %Collection{} = collection,
        %Season{} = season,
        position \\ nil
      ) do
    Bobine.Otel.with_span "bobine.content.add_season_to_collection",
                          %{"bobine.org.id" => scope.organization.id} do
      position = position || next_collection_item_position(collection.id)

      attrs = %{
        organization_id: scope.organization.id,
        collection_id: collection.id,
        season_id: season.id,
        item_type: :season,
        position: position
      }

      case %CollectionItem{} |> CollectionItem.changeset(attrs) |> Repo.insert() do
        {:ok, item} ->
          Events.broadcast(scope, {:collection_item_added, item})

          Audit.log(scope, "collection_item.added", item, %{
            item_type: "season",
            season_id: season.id
          })

          {:ok, item}

        {:error, changeset} ->
          if has_unique_constraint_error?(changeset) do
            {:error, :already_exists}
          else
            {:error, :validation, changeset}
          end
      end
    end
  end

  @doc """
  Adds a series to a collection at the given position. Sets item_type to :series.

  Exempt from doctest — hits the database.
  """
  def add_series_to_collection(
        scope,
        %Collection{} = collection,
        %Series{} = series,
        position \\ nil
      ) do
    Bobine.Otel.with_span "bobine.content.add_series_to_collection",
                          %{"bobine.org.id" => scope.organization.id} do
      position = position || next_collection_item_position(collection.id)

      attrs = %{
        organization_id: scope.organization.id,
        collection_id: collection.id,
        series_id: series.id,
        item_type: :series,
        position: position
      }

      case %CollectionItem{} |> CollectionItem.changeset(attrs) |> Repo.insert() do
        {:ok, item} ->
          Events.broadcast(scope, {:collection_item_added, item})

          Audit.log(scope, "collection_item.added", item, %{
            item_type: "series",
            series_id: series.id
          })

          {:ok, item}

        {:error, changeset} ->
          if has_unique_constraint_error?(changeset) do
            {:error, :already_exists}
          else
            {:error, :validation, changeset}
          end
      end
    end
  end

  @doc """
  Adds multiple videos to a collection in a single transaction.

  Skips videos that are already in the collection. Returns the list of
  successfully created items.

  Exempt from doctest — hits the database.
  """
  def add_videos_to_collection(scope, %Collection{} = collection, videos) when is_list(videos) do
    Bobine.Otel.with_span "bobine.content.add_videos_to_collection",
                          %{"bobine.org.id" => scope.organization.id} do
      existing_video_ids =
        CollectionItem
        |> where(collection_id: ^collection.id)
        |> select([ci], ci.video_id)
        |> Repo.all()
        |> MapSet.new()

      new_videos = Enum.reject(videos, &MapSet.member?(existing_video_ids, &1.id))

      Repo.transaction(fn ->
        starting_position = next_collection_item_position(collection.id)

        new_videos
        |> Enum.with_index(starting_position)
        |> Enum.reduce([], fn {video, position}, acc ->
          [insert_collection_item(scope, collection, video, position) | acc]
        end)
        |> Enum.reverse()
      end)
    end
  end

  defp insert_collection_item(scope, collection, video, position) do
    attrs = %{
      organization_id: scope.organization.id,
      collection_id: collection.id,
      video_id: video.id,
      item_type: :video,
      position: position
    }

    case %CollectionItem{} |> CollectionItem.changeset(attrs) |> Repo.insert() do
      {:ok, item} ->
        Events.broadcast(
          scope,
          {:collection_video_added, %{collection: collection, video: video}}
        )

        Audit.log(scope, "collection.video_added", item)
        item

      {:error, changeset} ->
        Repo.rollback({:validation, changeset})
    end
  end

  @doc """
  Removes a video from a collection.

  Exempt from doctest — hits the database.
  """
  def remove_video_from_collection(scope, %Collection{} = collection, %Video{} = video) do
    Bobine.Otel.with_span "bobine.content.remove_video_from_collection",
                          %{"bobine.org.id" => scope.organization.id} do
      case Repo.get_by(CollectionItem, collection_id: collection.id, video_id: video.id) do
        nil ->
          {:error, :not_found}

        item ->
          case Repo.delete(item) do
            {:ok, _} ->
              Events.broadcast(
                scope,
                {:collection_video_removed, %{collection: collection, video: video}}
              )

              Audit.log(scope, "collection.video_removed", item)
              :ok

            {:error, changeset} ->
              {:error, :validation, changeset}
          end
      end
    end
  end

  @doc """
  Reorders videos within a collection by updating positions in a single transaction.

  Exempt from doctest — hits the database.
  """
  def reorder_collection_videos(scope, %Collection{} = collection, ordered_video_ids) do
    Bobine.Otel.with_span "bobine.content.reorder_collection_videos",
                          %{"bobine.org.id" => scope.organization.id} do
      Repo.transaction(fn ->
        ordered_video_ids
        |> Enum.with_index()
        |> Enum.each(fn {video_id, position} ->
          CollectionItem
          |> where(collection_id: ^collection.id, video_id: ^video_id)
          |> Repo.update_all(set: [position: position])
        end)
      end)
      |> case do
        {:ok, _} ->
          Events.broadcast(scope, {:collection_videos_reordered, %{collection: collection}})
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp next_collection_item_position(collection_id) do
    CollectionItem
    |> where(collection_id: ^collection_id)
    |> select([ci], max(ci.position))
    |> Repo.one()
    |> case do
      nil -> 0
      max_pos -> max_pos + 1
    end
  end

  defp has_unique_constraint_error?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_msg, opts}} ->
      Keyword.get(opts, :constraint) == :unique
    end)
  end

  ## -----------------------------------------------------------------------
  ## Collection Items (polymorphic)
  ## -----------------------------------------------------------------------

  @doc """
  Lists collection items with their referenced entities preloaded.
  Returns items in position order with the correct association preloaded
  based on item_type.

  Exempt from doctest — hits the database.
  """
  def list_collection_items(%Organization{id: org_id}, %{id: collection_id}, opts \\ []) do
    Bobine.Otel.with_span "bobine.content.list_collection_items",
                          %{"bobine.org.id" => org_id} do
      CollectionItem
      |> where(organization_id: ^org_id, collection_id: ^collection_id)
      |> order_by(:position)
      |> preload([:video, :series, season: :series])
      |> Pagination.paginate(opts)
    end
  end

  @doc """
  Removes a collection item by soft-deleting it. Works for any item type.

  Exempt from doctest — hits the database.
  """
  def remove_collection_item(scope, %CollectionItem{} = item) do
    Bobine.Otel.with_span "bobine.content.remove_collection_item",
                          %{"bobine.org.id" => scope.organization.id} do
      case Repo.delete(item) do
        {:ok, _} ->
          Events.broadcast(scope, {:collection_item_removed, item})

          Audit.log(scope, "collection_item.removed", item, %{
            item_type: to_string(item.item_type)
          })

          :ok

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Reorders collection items by updating positions.

  Accepts a list of collection item IDs in the desired order.

  Exempt from doctest — hits the database.
  """
  def reorder_collection_items(scope, %Collection{} = collection, ordered_item_ids) do
    Bobine.Otel.with_span "bobine.content.reorder_collection_items",
                          %{"bobine.org.id" => scope.organization.id} do
      Repo.transaction(fn ->
        ordered_item_ids
        |> Enum.with_index()
        |> Enum.each(fn {id, position} ->
          CollectionItem
          |> where(id: ^id, collection_id: ^collection.id)
          |> Repo.update_all(set: [position: position])
        end)
      end)
      |> case do
        {:ok, _} ->
          Events.broadcast(scope, {:collection_items_reordered, %{collection: collection}})
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  ## -----------------------------------------------------------------------
  ## Tags
  ## -----------------------------------------------------------------------

  @doc """
  Returns a paginated list of tags for an organization, excluding soft-deleted.

  Exempt from doctest — hits the database.
  """
  def list_tags(%Organization{id: org_id}, opts \\ []) do
    Tag
    |> where(organization_id: ^org_id)
    |> where([t], is_nil(t.deleted_at))
    |> order_by(asc: :name)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a single tag within an organization.

  Returns `{:ok, tag}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_tag(%Organization{id: org_id}, id) do
    case Repo.get_by(Tag, id: id, organization_id: org_id) do
      nil -> {:error, :not_found}
      tag -> {:ok, tag}
    end
  end

  @doc """
  Creates a tag. Name is normalized to lowercase.

  Exempt from doctest — hits the database.
  """
  def create_tag(scope, attrs) do
    Bobine.Otel.with_span "bobine.content.create_tag",
                          %{"bobine.org.id" => scope.organization.id} do
      attrs = put_org_id(attrs, scope.organization.id)

      case %Tag{} |> Tag.changeset(attrs) |> Repo.insert() do
        {:ok, tag} ->
          Events.broadcast(scope, {:tag_created, tag})
          Audit.log(scope, "tag.created", tag)
          {:ok, tag}

        {:error, changeset} ->
          if has_unique_constraint_error?(changeset) do
            {:error, :already_exists}
          else
            {:error, :validation, changeset}
          end
      end
    end
  end

  @doc """
  Updates a tag.

  Exempt from doctest — hits the database.
  """
  def update_tag(scope, %Tag{} = tag, attrs) do
    Bobine.Otel.with_span "bobine.content.update_tag",
                          %{"bobine.org.id" => scope.organization.id} do
      case tag |> Tag.changeset(attrs) |> Repo.update() do
        {:ok, tag} ->
          Events.broadcast(scope, {:tag_updated, tag})
          Audit.log(scope, "tag.updated", tag, attrs)
          {:ok, tag}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Soft-deletes a tag and removes all video_tag associations.

  Exempt from doctest — hits the database.
  """
  def delete_tag(scope, %Tag{} = tag) do
    Bobine.Otel.with_span "bobine.content.delete_tag",
                          %{"bobine.org.id" => scope.organization.id} do
      Repo.transaction(fn ->
        VideoTag
        |> where(tag_id: ^tag.id)
        |> Repo.delete_all()

        {:ok, deleted_tag} =
          tag
          |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
          |> Repo.update()

        deleted_tag
      end)
      |> case do
        {:ok, tag} ->
          Events.broadcast(scope, {:tag_deleted, tag})
          Audit.log(scope, "tag.deleted", tag)
          {:ok, tag}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  ## -----------------------------------------------------------------------
  ## Video Tagging
  ## -----------------------------------------------------------------------

  @doc """
  Tags a video with a tag.

  Exempt from doctest — hits the database.
  """
  def tag_video(scope, %Video{} = video, %Tag{} = tag) do
    Bobine.Otel.with_span "bobine.content.tag_video",
                          %{"bobine.org.id" => scope.organization.id} do
      attrs = %{
        organization_id: scope.organization.id,
        video_id: video.id,
        tag_id: tag.id
      }

      case %VideoTag{} |> VideoTag.changeset(attrs) |> Repo.insert() do
        {:ok, video_tag} ->
          Events.broadcast(scope, {:video_tagged, %{video: video, tag: tag}})
          Audit.log(scope, "video.tagged", video_tag)
          {:ok, video_tag}

        {:error, changeset} ->
          if has_unique_constraint_error?(changeset) do
            {:error, :already_exists}
          else
            {:error, :validation, changeset}
          end
      end
    end
  end

  @doc """
  Removes a tag from a video.

  Exempt from doctest — hits the database.
  """
  def untag_video(scope, %Video{} = video, %Tag{} = tag) do
    Bobine.Otel.with_span "bobine.content.untag_video",
                          %{"bobine.org.id" => scope.organization.id} do
      case Repo.get_by(VideoTag, video_id: video.id, tag_id: tag.id) do
        nil ->
          {:error, :not_found}

        video_tag ->
          case Repo.delete(video_tag) do
            {:ok, _} ->
              Events.broadcast(scope, {:video_untagged, %{video: video, tag: tag}})
              Audit.log(scope, "video.untagged", video_tag)
              :ok

            {:error, changeset} ->
              {:error, :validation, changeset}
          end
      end
    end
  end

  @doc """
  Lists all tags for a video within an organization.

  Exempt from doctest — hits the database.
  """
  def list_video_tags(%Organization{id: org_id}, %Video{} = video) do
    Tag
    |> join(:inner, [t], vt in VideoTag, on: vt.tag_id == t.id and vt.video_id == ^video.id)
    |> where([t], t.organization_id == ^org_id)
    |> where([t], is_nil(t.deleted_at))
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc """
  Returns a map of `%{video_id => [tag, ...]}` for a list of videos.

  Loads all tags in a single query to avoid N+1.

  Exempt from doctest — hits the database.
  """
  def list_tags_for_videos(%Organization{id: org_id}, video_ids) when is_list(video_ids) do
    Tag
    |> join(:inner, [t], vt in VideoTag, on: vt.tag_id == t.id)
    |> where([t, vt], vt.video_id in ^video_ids)
    |> where([t], t.organization_id == ^org_id)
    |> where([t], is_nil(t.deleted_at))
    |> order_by(asc: :name)
    |> select([t, vt], {vt.video_id, t})
    |> Repo.all()
    |> Enum.group_by(fn {vid, _tag} -> vid end, fn {_vid, tag} -> tag end)
  end

  @doc """
  Returns a paginated list of videos with a given tag.

  Exempt from doctest — hits the database.
  """
  def list_videos_by_tag(%Organization{id: org_id}, %{id: tag_id}, opts \\ []) do
    Video
    |> join(:inner, [v], vt in VideoTag, on: vt.video_id == v.id and vt.tag_id == ^tag_id)
    |> where([v], v.organization_id == ^org_id)
    |> where([v], is_nil(v.deleted_at))
    |> order_by(desc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  ## -----------------------------------------------------------------------
  ## Series
  ## -----------------------------------------------------------------------

  @doc """
  Returns a paginated list of visible series for an organization, ordered by position.

  Exempt from doctest — hits the database.
  """
  def list_series(%Organization{id: org_id}, opts \\ []) do
    Bobine.Otel.with_span "bobine.content.list_series",
                          %{"bobine.org.id" => org_id} do
      Series
      |> where(organization_id: ^org_id)
      |> where([s], is_nil(s.deleted_at))
      |> order_by(:position)
      |> Pagination.paginate(opts)
    end
  end

  @doc """
  Gets a series by ID, scoped to org.

  Returns `{:ok, series}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_series(%Organization{id: org_id}, id) do
    case Repo.get_by(Series, id: id, organization_id: org_id) do
      nil -> {:error, :not_found}
      series -> {:ok, series}
    end
  end

  @doc """
  Gets a series by ID, scoped to org. Raises if not found.

  Exempt from doctest — hits the database.
  """
  def get_series!(%Organization{id: org_id}, id) do
    Series
    |> where(organization_id: ^org_id)
    |> Repo.get!(id)
  end

  @doc """
  Gets a series by slug, scoped to org.

  Returns `{:ok, series}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_series_by_slug(%Organization{id: org_id}, slug) do
    query =
      Series
      |> where(organization_id: ^org_id, slug: ^slug)
      |> where([s], is_nil(s.deleted_at))

    case Repo.one(query) do
      nil -> {:error, :not_found}
      series -> {:ok, series}
    end
  end

  @doc """
  Creates a series.

  Exempt from doctest — hits the database.
  """
  def create_series(scope, attrs) do
    Bobine.Otel.with_span "bobine.content.create_series",
                          %{"bobine.org.id" => scope.organization.id} do
      case %Series{organization_id: scope.organization.id}
           |> Series.changeset(attrs)
           |> Repo.insert() do
        {:ok, series} ->
          Events.broadcast(scope, {:series_created, series})
          Audit.log(scope, "series.created", series, attrs)
          {:ok, series}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Updates a series.

  Exempt from doctest — hits the database.
  """
  def update_series(scope, %Series{} = series, attrs) do
    Bobine.Otel.with_span "bobine.content.update_series",
                          %{"bobine.org.id" => scope.organization.id} do
      case series |> Series.changeset(attrs) |> Repo.update() do
        {:ok, series} ->
          invalidate_series_thumbnail_cache(series)
          Events.broadcast(scope, {:series_updated, series})
          Audit.log(scope, "series.updated", series, attrs)
          {:ok, series}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Soft-deletes a series and cascades to its seasons.

  Exempt from doctest — hits the database.
  """
  def delete_series(scope, %Series{} = series) do
    Bobine.Otel.with_span "bobine.content.delete_series",
                          %{"bobine.org.id" => scope.organization.id} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      with {:ok, series} <-
             series
             |> Ecto.Changeset.change(deleted_at: now)
             |> Repo.update() do
        Season
        |> where(series_id: ^series.id)
        |> where([s], is_nil(s.deleted_at))
        |> Repo.update_all(set: [deleted_at: now])

        invalidate_series_thumbnail_cache(series)
        Events.broadcast(scope, {:series_deleted, series})
        Audit.log(scope, "series.deleted", series)
        {:ok, series}
      end
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking series changes.

  ## Examples

      iex> change_series(%Bobine.Content.Series{})
      %Ecto.Changeset{data: %Bobine.Content.Series{}}

  """
  def change_series(%Series{} = series, attrs \\ %{}) do
    Series.changeset(series, attrs)
  end

  ## -----------------------------------------------------------------------
  ## Seasons
  ## -----------------------------------------------------------------------

  @doc """
  Returns a paginated list of seasons for a series, ordered by season_number.

  Exempt from doctest — hits the database.
  """
  def list_seasons(%Organization{id: org_id}, %Series{id: series_id}, opts \\ []) do
    Bobine.Otel.with_span "bobine.content.list_seasons",
                          %{"bobine.org.id" => org_id, "bobine.series.id" => series_id} do
      Season
      |> where(organization_id: ^org_id, series_id: ^series_id)
      |> where([s], is_nil(s.deleted_at))
      |> order_by(:season_number)
      |> Pagination.paginate(opts)
    end
  end

  @doc """
  Returns the non-deleted season count for a series.

  Scoped by the series's `organization_id`. Useful for display badges
  where preloading the full seasons list would be wasteful.

  Exempt from doctest — hits the database.
  """
  def count_seasons_for_series(%Series{id: series_id, organization_id: org_id}) do
    Season
    |> where(series_id: ^series_id, organization_id: ^org_id)
    |> where([s], is_nil(s.deleted_at))
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets a season by ID, scoped to org.

  Returns `{:ok, season}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_season(%Organization{id: org_id}, id) do
    case Repo.get_by(Season, id: id, organization_id: org_id) do
      nil -> {:error, :not_found}
      season -> {:ok, season}
    end
  end

  @doc """
  Gets a season by ID, scoped to org. Raises if not found.

  Exempt from doctest — hits the database.
  """
  def get_season!(%Organization{id: org_id}, id) do
    Season
    |> where(organization_id: ^org_id)
    |> Repo.get!(id)
  end

  @doc """
  Gets a season by slug, scoped to org.

  Returns `{:ok, season}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_season_by_slug(%Organization{id: org_id}, slug) do
    query =
      Season
      |> where(organization_id: ^org_id, slug: ^slug)
      |> where([s], is_nil(s.deleted_at))

    case Repo.one(query) do
      nil -> {:error, :not_found}
      season -> {:ok, season}
    end
  end

  @doc """
  Creates a season within a series. Auto-assigns season_number if not provided.

  Exempt from doctest — hits the database.
  """
  def create_season(scope, %Series{} = series, attrs) do
    Bobine.Otel.with_span "bobine.content.create_season",
                          %{
                            "bobine.org.id" => scope.organization.id,
                            "bobine.series.id" => series.id
                          } do
      attrs =
        attrs
        |> maybe_assign_season_number(series)
        |> maybe_assign_default_title(series)

      case %Season{organization_id: scope.organization.id, series_id: series.id}
           |> Season.changeset(attrs)
           |> Repo.insert() do
        {:ok, season} ->
          invalidate_season_thumbnail_cache(season)
          Events.broadcast(scope, {:season_created, season})
          Audit.log(scope, "season.created", season, attrs)
          {:ok, season}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  defp maybe_assign_season_number(attrs, series) do
    has_season_number =
      Map.has_key?(attrs, :season_number) || Map.has_key?(attrs, "season_number")

    cond do
      has_season_number -> attrs
      has_string_keys?(attrs) -> Map.put(attrs, "season_number", next_season_number(series))
      true -> Map.put(attrs, :season_number, next_season_number(series))
    end
  end

  # If the caller did not provide a title (or provided a blank one), default to
  # "Season <season number>". Season titles are not unique across series, so the
  # generic default is fine — the operator can override per-season when needed.
  # Honors the params' key style (string vs atom).
  defp maybe_assign_default_title(attrs, %Series{} = _series) do
    title = Map.get(attrs, :title) || Map.get(attrs, "title")

    if is_binary(title) and String.trim(title) != "" do
      attrs
    else
      season_number = Map.get(attrs, :season_number) || Map.get(attrs, "season_number")
      default = "Season #{season_number}"

      if has_string_keys?(attrs) do
        Map.put(attrs, "title", default)
      else
        Map.put(attrs, :title, default)
      end
    end
  end

  defp next_season_number(%Series{id: series_id}) do
    Season
    |> where(series_id: ^series_id)
    |> where([s], is_nil(s.deleted_at))
    |> Repo.aggregate(:max, :season_number)
    |> then(fn
      nil -> 1
      n -> n + 1
    end)
  end

  @doc """
  Updates a season.

  Exempt from doctest — hits the database.
  """
  def update_season(scope, %Season{} = season, attrs) do
    Bobine.Otel.with_span "bobine.content.update_season",
                          %{"bobine.org.id" => scope.organization.id} do
      case season |> Season.changeset(attrs) |> Repo.update() do
        {:ok, season} ->
          invalidate_season_thumbnail_cache(season)
          Events.broadcast(scope, {:season_updated, season})
          Audit.log(scope, "season.updated", season, attrs)
          {:ok, season}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Soft-deletes a season.

  Exempt from doctest — hits the database.
  """
  def delete_season(scope, %Season{} = season) do
    Bobine.Otel.with_span "bobine.content.delete_season",
                          %{"bobine.org.id" => scope.organization.id} do
      with {:ok, season} <-
             season
             |> Ecto.Changeset.change(
               deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
             )
             |> Repo.update() do
        invalidate_season_thumbnail_cache(season)
        Events.broadcast(scope, {:season_deleted, season})
        Audit.log(scope, "season.deleted", season)
        {:ok, season}
      end
    end
  end

  @doc """
  Reorders seasons within a series by updating season_numbers.

  Exempt from doctest — hits the database.
  """
  def reorder_seasons(scope, %Series{} = series, ordered_season_ids) do
    Bobine.Otel.with_span "bobine.content.reorder_seasons",
                          %{"bobine.org.id" => scope.organization.id} do
      Repo.transaction(fn ->
        # Two-pass to avoid unique constraint violations during swap
        ordered_season_ids
        |> Enum.with_index(1)
        |> Enum.each(fn {id, position} ->
          Season
          |> where(id: ^id, series_id: ^series.id)
          |> Repo.update_all(set: [season_number: -position])
        end)

        ordered_season_ids
        |> Enum.with_index(1)
        |> Enum.each(fn {id, position} ->
          Season
          |> where(id: ^id, series_id: ^series.id)
          |> Repo.update_all(set: [season_number: position])
        end)
      end)
      |> case do
        {:ok, _} ->
          Events.broadcast(scope, {:seasons_reordered, series})
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Gets the next season in a series after the given season.
  Returns nil if this is the last season.

  Exempt from doctest — hits the database.
  """
  def next_season(%Organization{id: org_id}, %Season{} = season) do
    Season
    |> where(organization_id: ^org_id, series_id: ^season.series_id)
    |> where([s], is_nil(s.deleted_at))
    |> where([s], s.season_number > ^season.season_number)
    |> order_by(:season_number)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking season changes.

  ## Examples

      iex> change_season(%Bobine.Content.Season{})
      %Ecto.Changeset{data: %Bobine.Content.Season{}}

  """
  def change_season(%Season{} = season, attrs \\ %{}) do
    Season.changeset(season, attrs)
  end

  ## -----------------------------------------------------------------------
  ## Episodes
  ## -----------------------------------------------------------------------

  @doc """
  Lists episodes in a season, ordered by episode_number. Preloads video.

  Exempt from doctest — hits the database.
  """
  def list_episodes(%Organization{id: org_id}, %Season{id: season_id}) do
    Bobine.Otel.with_span "bobine.content.list_episodes",
                          %{"bobine.org.id" => org_id, "bobine.season.id" => season_id} do
      Episode
      |> where(organization_id: ^org_id, season_id: ^season_id)
      |> order_by(:episode_number)
      |> preload(:video)
      |> Repo.all()
    end
  end

  @doc """
  Adds a video as an episode in a season. Auto-assigns episode_number
  if not provided. Updates the season's cached episode_count.

  Exempt from doctest — hits the database.
  """
  def add_episode(scope, %Season{} = season, %Video{} = video, attrs \\ %{}) do
    Bobine.Otel.with_span "bobine.content.add_episode",
                          %{"bobine.org.id" => scope.organization.id} do
      episode_number =
        attrs[:episode_number] || attrs["episode_number"] || next_episode_number(season)

      result =
        %Episode{
          organization_id: scope.organization.id,
          season_id: season.id
        }
        |> Episode.changeset(
          Map.merge(attrs, %{episode_number: episode_number, video_id: video.id})
        )
        |> Repo.insert()

      case result do
        {:ok, episode} ->
          update_episode_count(season)
          invalidate_season_thumbnail_cache(season)
          Events.broadcast(scope, {:episode_added, episode})

          Audit.log(scope, "episode.added", episode, %{
            video_id: video.id,
            season_id: season.id
          })

          {:ok, Repo.preload(episode, :video)}

        {:error, changeset} ->
          if has_unique_constraint_error?(changeset) do
            {:error, :already_exists}
          else
            {:error, :validation, changeset}
          end
      end
    end
  end

  defp next_episode_number(%Season{id: season_id}) do
    Episode
    |> where(season_id: ^season_id)
    |> Repo.aggregate(:max, :episode_number)
    |> then(fn
      nil -> 1
      n -> n + 1
    end)
  end

  defp update_episode_count(%Season{id: season_id}) do
    count =
      Episode
      |> where(season_id: ^season_id)
      |> Repo.aggregate(:count)

    Season
    |> where(id: ^season_id)
    |> Repo.update_all(set: [episode_count: count])
  end

  @doc """
  Returns a MapSet of video IDs that are attached as an Episode anywhere
  within the organization. Useful for filtering a video picker so operators
  don't double-attach a video to two seasons.

  Exempt from doctest — hits the database.
  """
  def list_assigned_episode_video_ids(%Organization{id: org_id}) do
    Episode
    |> where(organization_id: ^org_id)
    |> select([e], e.video_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Removes an episode from a season. Does NOT delete the video.
  Updates the season's cached episode_count.

  Exempt from doctest — hits the database.
  """
  def remove_episode(scope, %Season{} = season, %Video{} = video) do
    Bobine.Otel.with_span "bobine.content.remove_episode",
                          %{"bobine.org.id" => scope.organization.id} do
      case Repo.get_by(Episode, season_id: season.id, video_id: video.id) do
        nil ->
          {:error, :not_found}

        episode ->
          Repo.delete(episode)
          update_episode_count(season)
          invalidate_season_thumbnail_cache(season)
          Events.broadcast(scope, {:episode_removed, episode})
          Audit.log(scope, "episode.removed", episode, %{video_id: video.id})
          :ok
      end
    end
  end

  @doc """
  Reorders episodes within a season by updating episode_numbers.

  Exempt from doctest — hits the database.
  """
  def reorder_episodes(scope, %Season{} = season, ordered_video_ids) do
    Bobine.Otel.with_span "bobine.content.reorder_episodes",
                          %{"bobine.org.id" => scope.organization.id} do
      Repo.transaction(fn ->
        # Two-pass to avoid unique constraint violations during swap
        ordered_video_ids
        |> Enum.with_index(1)
        |> Enum.each(fn {video_id, position} ->
          Episode
          |> where(season_id: ^season.id, video_id: ^video_id)
          |> Repo.update_all(set: [episode_number: -position])
        end)

        ordered_video_ids
        |> Enum.with_index(1)
        |> Enum.each(fn {video_id, position} ->
          Episode
          |> where(season_id: ^season.id, video_id: ^video_id)
          |> Repo.update_all(set: [episode_number: position])
        end)
      end)
      |> case do
        {:ok, _} ->
          Events.broadcast(scope, {:episodes_reordered, season})
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Gets the next episode in a season after the given video.
  Returns nil if the video is the last episode or not in a season.

  Exempt from doctest — hits the database.
  """
  def next_episode(%Organization{id: org_id}, %Video{} = video) do
    case get_episode_context(%Organization{id: org_id}, video) do
      nil ->
        nil

      ctx ->
        Episode
        |> where(organization_id: ^org_id, season_id: ^ctx.season.id)
        |> where([e], e.episode_number > ^ctx.episode_number)
        |> order_by(:episode_number)
        |> limit(1)
        |> preload(:video)
        |> Repo.one()
    end
  end

  @doc """
  Returns full season/series context for a video, if it's an episode.
  Returns nil for standalone videos.

  Exempt from doctest — hits the database.
  """
  def get_episode_context(%Organization{id: org_id}, %Video{id: video_id}) do
    episode =
      Episode
      |> where(organization_id: ^org_id, video_id: ^video_id)
      |> preload(season: :series)
      |> Repo.one()

    case episode do
      nil ->
        nil

      ep ->
        %{
          episode: ep,
          season: ep.season,
          series: ep.season.series,
          episode_number: ep.episode_number,
          season_number: ep.season.season_number,
          total_episodes: ep.season.episode_count
        }
    end
  end

  ## -----------------------------------------------------------------------
  ## New Season flag
  ## -----------------------------------------------------------------------

  @doc """
  Returns true when a series should currently display the "New Season" badge.

  A flag is "active" when:
    1. `new_season` is true, AND
    2. `new_season_expires_at` is nil (no expiry — permanent until cleared)
       OR `new_season_expires_at` is in the future.

      iex> Bobine.Content.new_season_active?(%Bobine.Content.Series{new_season: false})
      false

      iex> Bobine.Content.new_season_active?(%Bobine.Content.Series{new_season: true, new_season_expires_at: nil})
      true
  """
  def new_season_active?(%Series{new_season: false}), do: false

  def new_season_active?(%Series{new_season: true, new_season_expires_at: nil}), do: true

  def new_season_active?(%Series{new_season: true, new_season_expires_at: %DateTime{} = expires}) do
    DateTime.compare(expires, DateTime.utc_now()) == :gt
  end

  @doc """
  Returns the number of whole days until the new-season badge expires.

  Returns nil if the flag is not active or has no expiry. A series whose
  expiry has already passed returns 0 (the badge is no longer shown but the
  caller may still want to render "expiring today" copy).

      iex> Bobine.Content.days_until_new_season_expires(%Bobine.Content.Series{new_season: false})
      nil

      iex> Bobine.Content.days_until_new_season_expires(%Bobine.Content.Series{new_season: true, new_season_expires_at: nil})
      nil
  """
  def days_until_new_season_expires(%Series{new_season: false}), do: nil
  def days_until_new_season_expires(%Series{new_season_expires_at: nil}), do: nil

  def days_until_new_season_expires(%Series{new_season_expires_at: %DateTime{} = expires}) do
    diff_seconds = DateTime.diff(expires, DateTime.utc_now(), :second)

    if diff_seconds <= 0 do
      0
    else
      div(diff_seconds, 86_400)
    end
  end

  ## -----------------------------------------------------------------------
  ## Thumbnail resolution
  ## -----------------------------------------------------------------------

  @placeholder_thumbnail "/images/placeholder-thumbnail.svg"

  @doc """
  Resolves the display thumbnail URL for a series.

  Resolution chain:
    1. `series.cover_image_url`
    2. Latest season's resolved thumbnail
    3. Placeholder image

  Exempt from doctest — hits the database.
  """
  def resolve_series_thumbnail(%Series{cover_image_url: url}) when is_binary(url) and url != "" do
    url
  end

  def resolve_series_thumbnail(%Series{} = series) do
    case latest_season(series) do
      nil -> @placeholder_thumbnail
      season -> resolve_season_thumbnail(season)
    end
  end

  @doc """
  Resolves the display thumbnail URL for a season.

  Resolution chain:
    1. `season.cover_image_url`
    2. First episode's video Mux thumbnail
    3. Placeholder image

  Exempt from doctest — hits the database.
  """
  def resolve_season_thumbnail(%Season{cover_image_url: url}) when is_binary(url) and url != "" do
    url
  end

  def resolve_season_thumbnail(%Season{} = season) do
    case first_episode_video(season) do
      %Video{mux_playback_id: playback_id} when is_binary(playback_id) ->
        mux_thumbnail_url(playback_id, width: 400, height: 225)

      _ ->
        @placeholder_thumbnail
    end
  end

  @doc """
  Cached version of `resolve_series_thumbnail/1`. Caches the resolved URL
  for 10 minutes per series. Invalidated automatically on series, season,
  and episode mutations.

  Exempt from doctest — hits the database / cache.
  """
  def resolve_series_thumbnail_cached(%Series{} = series) do
    Cache.fetch(
      "series_thumb:#{series.id}",
      [ttl: :timer.minutes(10)],
      fn -> resolve_series_thumbnail(series) end
    )
  end

  @doc """
  Cached version of `resolve_season_thumbnail/1`. Caches for 10 minutes.

  Exempt from doctest — hits the database / cache.
  """
  def resolve_season_thumbnail_cached(%Season{} = season) do
    Cache.fetch(
      "season_thumb:#{season.id}",
      [ttl: :timer.minutes(10)],
      fn -> resolve_season_thumbnail(season) end
    )
  end

  @doc """
  Returns the placeholder thumbnail URL used when no image source is available.
  """
  def placeholder_thumbnail, do: @placeholder_thumbnail

  defp latest_season(%Series{id: series_id}) do
    Season
    |> where(series_id: ^series_id)
    |> where([s], is_nil(s.deleted_at))
    |> order_by(desc: :season_number)
    |> limit(1)
    |> Repo.one()
  end

  defp first_episode_video(%Season{id: season_id}) do
    Episode
    |> where(season_id: ^season_id)
    |> order_by(:episode_number)
    |> limit(1)
    |> preload(:video)
    |> Repo.one()
    |> case do
      nil -> nil
      ep -> ep.video
    end
  end

  defp mux_thumbnail_url(playback_id, opts) do
    width = Keyword.get(opts, :width, 400)
    height = Keyword.get(opts, :height, 225)

    "https://image.mux.com/#{playback_id}/thumbnail.webp?" <>
      "width=#{width}&height=#{height}&fit_mode=smartcrop"
  end

  ## -----------------------------------------------------------------------
  ## Episode video filtering
  ## -----------------------------------------------------------------------

  @doc """
  Returns a query scope that excludes videos which are episodes in any season.
  Use this in auto-populated row queries (e.g. `:recent`, `:popular`) so the
  homepage does not surface individual episodes alongside their parent series.

      iex> q = Bobine.Content.exclude_episode_videos(Bobine.Content.Video)
      iex> match?(%Ecto.Query{}, q)
      true
  """
  def exclude_episode_videos(query) do
    episode_video_ids = from(e in Episode, select: e.video_id)
    from(v in query, where: v.id not in subquery(episode_video_ids))
  end

  ## -----------------------------------------------------------------------
  ## Cache invalidation
  ## -----------------------------------------------------------------------

  defp invalidate_series_thumbnail_cache(%Series{id: id}) do
    Cache.delete("series_thumb:#{id}")
  end

  defp invalidate_season_thumbnail_cache(%Season{id: id, series_id: series_id}) do
    Cache.delete("season_thumb:#{id}")
    Cache.delete("series_thumb:#{series_id}")
  end

  ## -----------------------------------------------------------------------
  ## Helpers
  ## -----------------------------------------------------------------------

  @doc """
  Generates a URL-safe slug from a title.

      iex> Bobine.Content.slugify("My Awesome Video!")
      "my-awesome-video"

      iex> Bobine.Content.slugify("  Spaces  and---dashes  ")
      "spaces-and-dashes"
  """
  def slugify(title) when is_binary(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/u, "")
    |> String.replace(~r/[\s_]+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
    |> then(fn slug ->
      if slug == "", do: "untitled-#{System.unique_integer([:positive])}", else: slug
    end)
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

  defp mux_client do
    Application.get_env(:bobine, :mux_client, Bobine.Content.MuxClient)
  end
end
