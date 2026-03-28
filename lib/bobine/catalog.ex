defmodule Bobine.Catalog do
  @moduledoc """
  The Catalog context.
  """

  import Ecto.Query, warn: false
  alias Bobine.Repo

  alias Bobine.Catalog.Row

  @doc """
  Returns the list of rows.

  ## Examples

      iex> list_rows()
      [%Row{}, ...]

  """
  def list_rows do
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

  ## Examples

      iex> create_row(%{field: value})
      {:ok, %Row{}}

      iex> create_row(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_row(attrs) do
    %Row{}
    |> Row.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a row.

  ## Examples

      iex> update_row(row, %{field: new_value})
      {:ok, %Row{}}

      iex> update_row(row, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_row(%Row{} = row, attrs) do
    row
    |> Row.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a row.

  ## Examples

      iex> delete_row(row)
      {:ok, %Row{}}

      iex> delete_row(row)
      {:error, %Ecto.Changeset{}}

  """
  def delete_row(%Row{} = row) do
    Repo.delete(row)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking row changes.

  ## Examples

      iex> change_row(row)
      %Ecto.Changeset{data: %Row{}}

  """
  def change_row(%Row{} = row, attrs \\ %{}) do
    Row.changeset(row, attrs)
  end
end
