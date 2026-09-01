defmodule Marquee.CatalogFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Marquee.Catalog` context.
  """

  @doc """
  Generate a row for a given scope.
  """
  def row_fixture(scope, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{
        position: 42,
        source_type: :curated,
        title: "some title",
        visible: true,
        max_items: 20
      })

    {:ok, row} = Marquee.Catalog.create_row(scope, attrs)
    row
  end
end
