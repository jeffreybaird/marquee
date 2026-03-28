defmodule Bobine.CatalogTest do
  use Bobine.DataCase

  alias Bobine.Catalog

  describe "rows" do
    alias Bobine.Catalog.Row

    import Bobine.CatalogFixtures

    @invalid_attrs %{position: nil, visible: nil, title: nil, filter_config: nil, source_type: nil}

    test "list_rows/0 returns all rows" do
      row = row_fixture()
      assert Catalog.list_rows() == [row]
    end

    test "get_row!/1 returns the row with given id" do
      row = row_fixture()
      assert Catalog.get_row!(row.id) == row
    end

    test "create_row/1 with valid data creates a row" do
      valid_attrs = %{position: 42, visible: true, title: "some title", filter_config: %{}, source_type: :curated}

      assert {:ok, %Row{} = row} = Catalog.create_row(valid_attrs)
      assert row.position == 42
      assert row.visible == true
      assert row.title == "some title"
      assert row.filter_config == %{}
      assert row.source_type == :curated
    end

    test "create_row/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Catalog.create_row(@invalid_attrs)
    end

    test "update_row/2 with valid data updates the row" do
      row = row_fixture()
      update_attrs = %{position: 43, visible: false, title: "some updated title", filter_config: %{}, source_type: :algorithm}

      assert {:ok, %Row{} = row} = Catalog.update_row(row, update_attrs)
      assert row.position == 43
      assert row.visible == false
      assert row.title == "some updated title"
      assert row.filter_config == %{}
      assert row.source_type == :algorithm
    end

    test "update_row/2 with invalid data returns error changeset" do
      row = row_fixture()
      assert {:error, %Ecto.Changeset{}} = Catalog.update_row(row, @invalid_attrs)
      assert row == Catalog.get_row!(row.id)
    end

    test "delete_row/1 deletes the row" do
      row = row_fixture()
      assert {:ok, %Row{}} = Catalog.delete_row(row)
      assert_raise Ecto.NoResultsError, fn -> Catalog.get_row!(row.id) end
    end

    test "change_row/1 returns a row changeset" do
      row = row_fixture()
      assert %Ecto.Changeset{} = Catalog.change_row(row)
    end
  end
end
