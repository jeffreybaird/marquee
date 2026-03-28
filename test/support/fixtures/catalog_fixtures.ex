defmodule Bobine.CatalogFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Bobine.Catalog` context.
  """

  @doc """
  Generate a row.
  """
  def row_fixture(attrs \\ %{}) do
    {:ok, row} =
      attrs
      |> Enum.into(%{
        filter_config: %{},
        position: 42,
        source_type: :curated,
        title: "some title",
        visible: true
      })
      |> Bobine.Catalog.create_row()

    row
  end
end
