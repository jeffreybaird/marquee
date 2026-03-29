defmodule Bobine.Catalog do
  @moduledoc """
  The Catalog context.
  """

  import Ecto.Query, warn: false
  alias Bobine.Repo
  alias Bobine.Pagination
  alias Bobine.Events

  alias Bobine.Catalog.Row

  @doc """
  Returns a paginated list of rows, excluding soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_rows(opts \\ []) do
    Row
    |> where([r], is_nil(r.deleted_at))
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
  Gets a single row.

  Raises `Ecto.NoResultsError` if the Row does not exist.

  ## Examples

      iex> get_row!(123)
      %Row{}

      iex> get_row!(456)
      ** (Ecto.NoResultsError)

  """
  def get_row!(id), do: Repo.get!(Row, id)

  @doc """
  Creates a row.

  Exempt from doctest — hits the database.
  """
  def create_row(attrs) do
    with {:ok, row} <- %Row{} |> Row.changeset(attrs) |> Repo.insert() do
      Events.broadcast(nil, {:row_created, row})
      {:ok, row}
    else
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Updates a row.

  Exempt from doctest — hits the database.
  """
  def update_row(%Row{} = row, attrs) do
    with {:ok, row} <- row |> Row.changeset(attrs) |> Repo.update() do
      Events.broadcast(nil, {:row_updated, row})
      {:ok, row}
    else
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Soft-deletes a row by setting `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def delete_row(%Row{} = row) do
    with {:ok, row} <-
           row
           |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
           |> Repo.update() do
      Events.broadcast(nil, {:row_deleted, row})
      {:ok, row}
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
end
