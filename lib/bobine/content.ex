defmodule Bobine.Content do
  @moduledoc """
  The Content context.
  """

  import Ecto.Query, warn: false
  alias Bobine.Repo
  alias Bobine.Pagination
  alias Bobine.Events

  alias Bobine.Content.Video

  @doc """
  Returns a paginated list of videos, excluding soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_videos(opts \\ []) do
    Video
    |> where([v], is_nil(v.deleted_at))
    |> order_by(desc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  @doc """
  Returns the list of videos including soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_videos_including_deleted do
    Repo.all(Video)
  end

  @doc """
  Gets a single video.

  Raises `Ecto.NoResultsError` if the Video does not exist.

  ## Examples

      iex> get_video!(123)
      %Video{}

      iex> get_video!(456)
      ** (Ecto.NoResultsError)

  """
  def get_video!(id), do: Repo.get!(Video, id)

  @doc """
  Creates a video.

  Exempt from doctest — hits the database.
  """
  def create_video(attrs) do
    with {:ok, video} <- %Video{} |> Video.changeset(attrs) |> Repo.insert() do
      Events.broadcast(nil, {:video_created, video})
      {:ok, video}
    else
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Updates a video.

  Exempt from doctest — hits the database.
  """
  def update_video(%Video{} = video, attrs) do
    with {:ok, video} <- video |> Video.changeset(attrs) |> Repo.update() do
      Events.broadcast(nil, {:video_updated, video})
      {:ok, video}
    else
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Soft-deletes a video by setting `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def delete_video(%Video{} = video) do
    with {:ok, video} <-
           video
           |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
           |> Repo.update() do
      Events.broadcast(nil, {:video_deleted, video})
      {:ok, video}
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
end
