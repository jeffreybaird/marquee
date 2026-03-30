defmodule Bobine.CatalogTest do
  use Bobine.DataCase

  alias Bobine.Catalog
  alias Bobine.Accounts.Scope

  describe "rows" do
    alias Bobine.Catalog.Row

    setup do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
      %{org: org, scope: scope}
    end

    test "list_rows/2 returns all rows for the org", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "some title",
          source_type: :curated,
          position: 42,
          visible: true,
          max_items: 20
        })

      assert %{results: [found]} = Catalog.list_rows(org)
      assert found.id == row.id
    end

    test "get_row!/1 returns the row with given id", %{scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "some title",
          source_type: :curated,
          position: 42,
          visible: true,
          max_items: 20
        })

      assert Catalog.get_row!(row.id).id == row.id
    end

    test "create_row/2 with valid data creates a row", %{scope: scope} do
      valid_attrs = %{
        position: 42,
        visible: true,
        title: "some title",
        source_type: :curated,
        max_items: 20
      }

      assert {:ok, %Row{} = row} = Catalog.create_row(scope, valid_attrs)
      assert row.position == 42
      assert row.visible == true
      assert row.title == "some title"
      assert row.source_type == :curated
    end

    test "create_row/2 with invalid data returns error changeset", %{scope: scope} do
      invalid_attrs = %{title: nil, source_type: nil}
      assert {:error, :validation, %Ecto.Changeset{}} = Catalog.create_row(scope, invalid_attrs)
    end

    test "update_row/3 with valid data updates the row", %{scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "some title",
          source_type: :curated,
          position: 42,
          visible: true,
          max_items: 20
        })

      update_attrs = %{
        position: 43,
        visible: false,
        title: "some updated title"
      }

      assert {:ok, %Row{} = row} = Catalog.update_row(scope, row, update_attrs)
      assert row.position == 43
      assert row.visible == false
      assert row.title == "some updated title"
    end

    test "update_row/3 with invalid data returns error changeset", %{scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "some title",
          source_type: :curated,
          position: 42,
          visible: true,
          max_items: 20
        })

      assert {:error, :validation, %Ecto.Changeset{}} =
               Catalog.update_row(scope, row, %{title: nil})

      assert Catalog.get_row!(row.id).title == "some title"
    end

    test "delete_row/2 soft-deletes the row", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "some title",
          source_type: :curated,
          position: 42,
          visible: true,
          max_items: 20
        })

      assert {:ok, %Row{} = deleted} = Catalog.delete_row(scope, row)
      assert deleted.deleted_at != nil
      assert %{results: []} = Catalog.list_rows(org)
    end

    test "restore_row/1 restores a soft-deleted row", %{scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "some title",
          source_type: :curated,
          position: 42,
          visible: true,
          max_items: 20
        })

      {:ok, deleted} = Catalog.delete_row(scope, row)
      assert {:ok, %Row{} = restored} = Catalog.restore_row(deleted)
      assert restored.deleted_at == nil
    end

    test "list_rows_including_deleted/0 returns soft-deleted rows", %{scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "some title",
          source_type: :curated,
          position: 42,
          visible: true,
          max_items: 20
        })

      {:ok, _deleted} = Catalog.delete_row(scope, row)
      assert [found] = Catalog.list_rows_including_deleted()
      assert found.id == row.id
    end

    test "change_row/1 returns a row changeset" do
      row = %Row{}
      assert %Ecto.Changeset{} = Catalog.change_row(row)
    end
  end
end
