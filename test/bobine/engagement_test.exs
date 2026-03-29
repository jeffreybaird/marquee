defmodule Bobine.EngagementTest do
  use Bobine.DataCase

  alias Bobine.Engagement

  describe "watchlist_items" do
    alias Bobine.Engagement.WatchlistItem

    import Bobine.EngagementFixtures

    @invalid_attrs %{organization_id: nil, user_id: nil, video_id: nil}

    setup do
      org = insert(:organization)
      user = insert(:user)
      video = insert(:video, organization: org)
      %{org: org, user: user, video: video}
    end

    test "list_watchlist_items/0 returns all watchlist_items" do
      watchlist_item = watchlist_item_fixture()
      assert %{results: [^watchlist_item]} = Engagement.list_watchlist_items()
    end

    test "get_watchlist_item!/1 returns the watchlist_item with given id" do
      watchlist_item = watchlist_item_fixture()
      assert Engagement.get_watchlist_item!(watchlist_item.id) == watchlist_item
    end

    test "create_watchlist_item/1 with valid data creates a watchlist_item", %{
      org: org,
      user: user,
      video: video
    } do
      valid_attrs = %{
        position: 42,
        auto_remove_on_watch: true,
        organization_id: org.id,
        user_id: user.id,
        video_id: video.id
      }

      assert {:ok, %WatchlistItem{} = watchlist_item} =
               Engagement.create_watchlist_item(valid_attrs)

      assert watchlist_item.position == 42
      assert watchlist_item.auto_remove_on_watch == true
    end

    test "create_watchlist_item/1 with invalid data returns error changeset" do
      assert {:error, :validation, %Ecto.Changeset{}} =
               Engagement.create_watchlist_item(@invalid_attrs)
    end

    test "update_watchlist_item/2 with valid data updates the watchlist_item" do
      watchlist_item = watchlist_item_fixture()
      update_attrs = %{position: 43, auto_remove_on_watch: false}

      assert {:ok, %WatchlistItem{} = watchlist_item} =
               Engagement.update_watchlist_item(watchlist_item, update_attrs)

      assert watchlist_item.position == 43
      assert watchlist_item.auto_remove_on_watch == false
    end

    test "update_watchlist_item/2 with invalid data returns error changeset" do
      watchlist_item = watchlist_item_fixture()

      assert {:error, :validation, %Ecto.Changeset{}} =
               Engagement.update_watchlist_item(watchlist_item, @invalid_attrs)

      assert watchlist_item == Engagement.get_watchlist_item!(watchlist_item.id)
    end

    test "delete_watchlist_item/1 soft-deletes the watchlist_item" do
      watchlist_item = watchlist_item_fixture()
      assert {:ok, %WatchlistItem{} = deleted} = Engagement.delete_watchlist_item(watchlist_item)
      assert deleted.deleted_at != nil
      assert %{results: []} = Engagement.list_watchlist_items()
    end

    test "restore_watchlist_item/1 restores a soft-deleted watchlist_item" do
      watchlist_item = watchlist_item_fixture()
      {:ok, deleted} = Engagement.delete_watchlist_item(watchlist_item)
      assert {:ok, %WatchlistItem{} = restored} = Engagement.restore_watchlist_item(deleted)
      assert restored.deleted_at == nil
    end

    test "list_watchlist_items_including_deleted/0 returns soft-deleted items" do
      watchlist_item = watchlist_item_fixture()
      {:ok, _deleted} = Engagement.delete_watchlist_item(watchlist_item)
      assert [found] = Engagement.list_watchlist_items_including_deleted()
      assert found.id == watchlist_item.id
    end

    test "change_watchlist_item/1 returns a watchlist_item changeset" do
      watchlist_item = watchlist_item_fixture()
      assert %Ecto.Changeset{} = Engagement.change_watchlist_item(watchlist_item)
    end
  end
end
