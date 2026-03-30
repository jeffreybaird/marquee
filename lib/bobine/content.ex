defmodule Bobine.Content do
  @moduledoc """
  The Content context.

  Manages videos, collections, tags, and the relationships between them.
  All operations are scoped to an organization for multi-tenant isolation.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Bobine.Repo
  alias Bobine.Pagination
  alias Bobine.Events
  alias Bobine.Audit
  alias Bobine.Accounts.Organization

  require Bobine.Otel

  alias Bobine.Content.{Video, Collection, CollectionItem, Tag, VideoTag}

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
    |> apply_video_order(opts)
    |> Pagination.paginate(opts)
  end

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
  Returns the list of videos including soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_videos_including_deleted do
    Repo.all(Video)
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
  Gets a single video. Raises on not found.

  Exempt from doctest — hits the database.
  """
  def get_video!(id), do: Repo.get!(Video, id)

  ## -----------------------------------------------------------------------
  ## Video upload flow
  ## -----------------------------------------------------------------------

  @doc """
  Creates a Mux direct upload URL and a video record in waiting status.

  Returns `{:ok, %{video: video, upload_url: url}}` or an error tuple.

  Exempt from doctest — calls Mux API.
  """
  def create_upload_url(scope, attrs) do
    Bobine.Otel.with_span "bobine.content.create_upload_url",
                          %{"bobine.org.id" => scope.organization.id} do
      with {:ok, upload} <-
             mux_client().create_direct_upload(%{
               cors_origin: build_cors_origin(scope.organization),
               new_asset_settings: %{
                 playback_policy: ["public"],
                 video_quality: "plus"
               }
             }),
           {:ok, video} <- create_video_record(scope, attrs, upload) do
        Events.broadcast(scope, {:video_upload_initiated, video})
        Bobine.Metrics.video_upload_initiated(scope.organization.id)
        {:ok, %{video: video, upload_url: upload_url_from(upload)}}
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

  defp build_cors_origin(org) do
    case Application.get_env(:bobine, :cors_origin) do
      nil -> prod_cors_origin(org)
      origin -> origin
    end
  end

  defp prod_cors_origin(%{custom_domain: domain}) when is_binary(domain) and domain != "",
    do: "https://#{domain}"

  defp prod_cors_origin(%{slug: slug}), do: "https://#{slug}.bobine.dev"

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
          Logger.warning("No video found for mux_upload_id=#{mux_upload_id}")
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
          Logger.warning("No video found for mux_asset_id=#{mux_asset_id}")
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
          Logger.warning("No video found for mux_asset_id=#{mux_asset_id}")
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

  Exempt from doctest — hits the database.
  """
  def create_video(attrs) do
    Bobine.Otel.with_span "bobine.content.create_video" do
      with {:ok, video} <- %Video{} |> Video.changeset(attrs) |> Repo.insert() do
        Events.broadcast(nil, {:video_created, video})
        {:ok, video}
      else
        {:error, changeset} -> {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Updates a video.

  Exempt from doctest — hits the database.
  """
  def update_video(%Video{} = video, attrs) do
    Bobine.Otel.with_span "bobine.content.update_video" do
      with {:ok, video} <- video |> Video.changeset(attrs) |> Repo.update() do
        Events.broadcast(nil, {:video_updated, video})
        {:ok, video}
      else
        {:error, changeset} -> {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Soft-deletes a video by setting `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def delete_video(%Video{} = video) do
    Bobine.Otel.with_span "bobine.content.delete_video" do
      with {:ok, video} <-
             video
             |> Ecto.Changeset.change(
               deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
             )
             |> Repo.update() do
        Events.broadcast(nil, {:video_deleted, video})
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
  Returns the list of collections including soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_collections_including_deleted do
    Repo.all(Collection)
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
  Creates a collection.

  Exempt from doctest — hits the database.
  """
  def create_collection(scope, attrs) do
    Bobine.Otel.with_span "bobine.content.create_collection",
                          %{"bobine.org.id" => scope.organization.id} do
      attrs = put_org_id(attrs, scope.organization.id)

      with {:ok, collection} <- %Collection{} |> Collection.changeset(attrs) |> Repo.insert() do
        Events.broadcast(scope, {:collection_created, collection})
        Audit.log(scope, "collection.created", collection)
        {:ok, collection}
      else
        {:error, changeset} -> {:error, :validation, changeset}
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
      with {:ok, collection} <- collection |> Collection.changeset(attrs) |> Repo.update() do
        Events.broadcast(scope, {:collection_updated, collection})
        Audit.log(scope, "collection.updated", collection, attrs)
        {:ok, collection}
      else
        {:error, changeset} -> {:error, :validation, changeset}
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
      with {:ok, tag} <- tag |> Tag.changeset(attrs) |> Repo.update() do
        Events.broadcast(scope, {:tag_updated, tag})
        Audit.log(scope, "tag.updated", tag, attrs)
        {:ok, tag}
      else
        {:error, changeset} -> {:error, :validation, changeset}
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
