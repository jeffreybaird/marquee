defmodule Bobine.Engagement do
  @moduledoc """
  The Engagement context.
  """

  import Ecto.Query, warn: false
  alias Bobine.Repo
  alias Bobine.Pagination
  alias Bobine.Events

  alias Bobine.Engagement.WatchlistItem

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
    with {:ok, item} <- %WatchlistItem{} |> WatchlistItem.changeset(attrs) |> Repo.insert() do
      Events.broadcast(nil, {:watchlist_item_added, item})
      {:ok, item}
    else
      {:error, changeset} -> {:error, :validation, changeset}
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

  ## -----------------------------------------------------------------------
  ## Playback progress
  ## -----------------------------------------------------------------------

  alias Bobine.Engagement.Progress

  @doc """
  Updates playback progress via the buffer (not direct DB write).

  Exempt from doctest — writes to buffer.
  """
  def update_progress(scope, video_id, position) when is_number(position) do
    Bobine.Buffers.ProgressBuffer.update(
      scope.organization.id,
      scope.user.id,
      video_id,
      position / 1
    )
  end

  @doc """
  Gets the saved playback progress for a user+video pair.

  Checks the buffer first, falls back to the database.

  Exempt from doctest — reads buffer and database.
  """
  def get_progress(scope, video_id) do
    org_id = scope.organization.id
    user_id = scope.user.id

    case Bobine.Buffers.ProgressBuffer.get(org_id, user_id, video_id) do
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
end
