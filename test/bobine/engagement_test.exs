defmodule Bobine.EngagementTest do
  use Bobine.DataCase

  alias Bobine.Engagement

  describe "watchlist_items" do
    alias Bobine.Engagement.WatchlistItem

    import Bobine.EngagementFixtures

    @invalid_attrs %{position: nil, auto_remove_on_watch: nil}

    test "list_watchlist_items/0 returns all watchlist_items" do
      watchlist_item = watchlist_item_fixture()
      assert Engagement.list_watchlist_items() == [watchlist_item]
    end

    test "get_watchlist_item!/1 returns the watchlist_item with given id" do
      watchlist_item = watchlist_item_fixture()
      assert Engagement.get_watchlist_item!(watchlist_item.id) == watchlist_item
    end

    test "create_watchlist_item/1 with valid data creates a watchlist_item" do
      valid_attrs = %{position: 42, auto_remove_on_watch: true}

      assert {:ok, %WatchlistItem{} = watchlist_item} = Engagement.create_watchlist_item(valid_attrs)
      assert watchlist_item.position == 42
      assert watchlist_item.auto_remove_on_watch == true
    end

    test "create_watchlist_item/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Engagement.create_watchlist_item(@invalid_attrs)
    end

    test "update_watchlist_item/2 with valid data updates the watchlist_item" do
      watchlist_item = watchlist_item_fixture()
      update_attrs = %{position: 43, auto_remove_on_watch: false}

      assert {:ok, %WatchlistItem{} = watchlist_item} = Engagement.update_watchlist_item(watchlist_item, update_attrs)
      assert watchlist_item.position == 43
      assert watchlist_item.auto_remove_on_watch == false
    end

    test "update_watchlist_item/2 with invalid data returns error changeset" do
      watchlist_item = watchlist_item_fixture()
      assert {:error, %Ecto.Changeset{}} = Engagement.update_watchlist_item(watchlist_item, @invalid_attrs)
      assert watchlist_item == Engagement.get_watchlist_item!(watchlist_item.id)
    end

    test "delete_watchlist_item/1 deletes the watchlist_item" do
      watchlist_item = watchlist_item_fixture()
      assert {:ok, %WatchlistItem{}} = Engagement.delete_watchlist_item(watchlist_item)
      assert_raise Ecto.NoResultsError, fn -> Engagement.get_watchlist_item!(watchlist_item.id) end
    end

    test "change_watchlist_item/1 returns a watchlist_item changeset" do
      watchlist_item = watchlist_item_fixture()
      assert %Ecto.Changeset{} = Engagement.change_watchlist_item(watchlist_item)
    end
  end
end
