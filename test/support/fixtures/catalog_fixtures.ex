defmodule Bobine.CatalogFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Bobine.Catalog` context.
  """

  import Bobine.Factory

  @doc """
  Generate a row.
  """
  def row_fixture(attrs \\ %{}) do
    org = insert(:organization)

    {:ok, row} =
      attrs
      |> Enum.into(%{
        organization_id: org.id,
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
