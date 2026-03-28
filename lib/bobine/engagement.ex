defmodule Bobine.Engagement do
  @moduledoc """
  The Engagement context.
  """

  import Ecto.Query, warn: false
  alias Bobine.Repo

  alias Bobine.Engagement.WatchlistItem

  @doc """
  Returns the list of watchlist_items.

  ## Examples

      iex> list_watchlist_items()
      [%WatchlistItem{}, ...]

  """
  def list_watchlist_items do
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

  ## Examples

      iex> create_watchlist_item(%{field: value})
      {:ok, %WatchlistItem{}}

      iex> create_watchlist_item(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_watchlist_item(attrs) do
    %WatchlistItem{}
    |> WatchlistItem.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a watchlist_item.

  ## Examples

      iex> update_watchlist_item(watchlist_item, %{field: new_value})
      {:ok, %WatchlistItem{}}

      iex> update_watchlist_item(watchlist_item, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_watchlist_item(%WatchlistItem{} = watchlist_item, attrs) do
    watchlist_item
    |> WatchlistItem.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a watchlist_item.

  ## Examples

      iex> delete_watchlist_item(watchlist_item)
      {:ok, %WatchlistItem{}}

      iex> delete_watchlist_item(watchlist_item)
      {:error, %Ecto.Changeset{}}

  """
  def delete_watchlist_item(%WatchlistItem{} = watchlist_item) do
    Repo.delete(watchlist_item)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking watchlist_item changes.

  ## Examples

      iex> change_watchlist_item(watchlist_item)
      %Ecto.Changeset{data: %WatchlistItem{}}

  """
  def change_watchlist_item(%WatchlistItem{} = watchlist_item, attrs \\ %{}) do
    WatchlistItem.changeset(watchlist_item, attrs)
  end
end
