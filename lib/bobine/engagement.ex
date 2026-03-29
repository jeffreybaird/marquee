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
end
