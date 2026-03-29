defmodule Bobine.Content do
  @moduledoc """
  The Content context.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Bobine.Repo
  alias Bobine.Pagination
  alias Bobine.Events
  alias Bobine.Accounts.Organization

  require Bobine.Otel

  alias Bobine.Content.Video

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
    |> apply_video_order(Keyword.get(opts, :order, :newest))
    |> Pagination.paginate(opts)
  end

  defp apply_video_search(query, nil), do: query

  defp apply_video_search(query, term) do
    pattern = "%#{term}%"
    where(query, [v], ilike(v.title, ^pattern))
  end

  defp apply_video_order(query, :oldest), do: order_by(query, asc: :inserted_at)
  defp apply_video_order(query, :alphabetical), do: order_by(query, asc: :title)
  defp apply_video_order(query, _newest), do: order_by(query, desc: :inserted_at)

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
              Events.broadcast(nil, {:video_ready, video})
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
              Events.broadcast(nil, {:video_errored, video})
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

  alias Bobine.Content.Collection

  @doc """
  Returns a paginated list of collections, excluding soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_collections(opts \\ []) do
    Collection
    |> where([c], is_nil(c.deleted_at))
    |> order_by(desc: :inserted_at)
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
  Gets a single collection.

  Raises `Ecto.NoResultsError` if the Collection does not exist.

  ## Examples

      iex> get_collection!(123)
      %Collection{}

      iex> get_collection!(456)
      ** (Ecto.NoResultsError)

  """
  def get_collection!(id), do: Repo.get!(Collection, id)

  @doc """
  Creates a collection.

  Exempt from doctest — hits the database.
  """
  def create_collection(attrs) do
    with {:ok, collection} <- %Collection{} |> Collection.changeset(attrs) |> Repo.insert() do
      Events.broadcast(nil, {:collection_created, collection})
      {:ok, collection}
    else
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Updates a collection.

  Exempt from doctest — hits the database.
  """
  def update_collection(%Collection{} = collection, attrs) do
    with {:ok, collection} <- collection |> Collection.changeset(attrs) |> Repo.update() do
      Events.broadcast(nil, {:collection_updated, collection})
      {:ok, collection}
    else
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Soft-deletes a collection by setting `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def delete_collection(%Collection{} = collection) do
    with {:ok, collection} <-
           collection
           |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
           |> Repo.update() do
      Events.broadcast(nil, {:collection_deleted, collection})
      {:ok, collection}
    end
  end

  @doc """
  Restores a soft-deleted collection by clearing `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def restore_collection(%Collection{} = collection) do
    collection
    |> Ecto.Changeset.change(deleted_at: nil)
    |> Repo.update()
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

  defp mux_client do
    Application.get_env(:bobine, :mux_client, Bobine.Content.MuxClient)
  end
end
