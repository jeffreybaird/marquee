defmodule Marquee.Engagement.FavoritesTest do
  use Marquee.DataCase, async: true

  alias Marquee.Engagement

  setup do
    org = insert(:organization)
    viewer = insert(:subscribed_viewer, organization: org)
    video = insert(:video, organization: org, mux_status: "ready")

    %{org: org, viewer: viewer, video: video}
  end

  describe "toggle_favorite/3" do
    test "adds when not favorited, returns {:ok, id, :added}", %{
      org: org,
      viewer: viewer,
      video: video
    } do
      assert {:ok, id, :added} = Engagement.toggle_favorite(org, viewer, video)
      assert is_binary(id)
      assert Engagement.favorited?(org, viewer, video) == true
    end

    test "removes when favorited, returns {:ok, id, :removed}", %{
      org: org,
      viewer: viewer,
      video: video
    } do
      {:ok, _id, :added} = Engagement.toggle_favorite(org, viewer, video)
      assert {:ok, id, :removed} = Engagement.toggle_favorite(org, viewer, video)
      assert is_binary(id)
      assert Engagement.favorited?(org, viewer, video) == false
    end

    test "re-adds after removal (restores soft-deleted)", %{
      org: org,
      viewer: viewer,
      video: video
    } do
      {:ok, _id, :added} = Engagement.toggle_favorite(org, viewer, video)
      {:ok, _id, :removed} = Engagement.toggle_favorite(org, viewer, video)
      {:ok, _id, :added} = Engagement.toggle_favorite(org, viewer, video)
      assert Engagement.favorited?(org, viewer, video) == true
    end
  end

  describe "get_favorite_for_viewer/3" do
    test "returns nil when none exists", %{org: org, viewer: viewer, video: video} do
      assert Engagement.get_favorite_for_viewer(org, viewer, video) == nil
    end

    test "returns the record after toggle_favorite inserts it", %{
      org: org,
      viewer: viewer,
      video: video
    } do
      {:ok, id, :added} = Engagement.toggle_favorite(org, viewer, video)
      fav = Engagement.get_favorite_for_viewer(org, viewer, video)
      assert fav.id == id
      assert fav.deleted_at == nil
    end

    test "returns the soft-deleted record after toggle removes it", %{
      org: org,
      viewer: viewer,
      video: video
    } do
      {:ok, _id, :added} = Engagement.toggle_favorite(org, viewer, video)
      {:ok, _id, :removed} = Engagement.toggle_favorite(org, viewer, video)

      fav = Engagement.get_favorite_for_viewer(org, viewer, video)
      assert fav.deleted_at != nil
    end
  end

  describe "favorited?/3" do
    test "returns true when favorited", %{org: org, viewer: viewer, video: video} do
      {:ok, _id, :added} = Engagement.toggle_favorite(org, viewer, video)
      assert Engagement.favorited?(org, viewer, video) == true
    end

    test "returns false when not favorited", %{org: org, viewer: viewer, video: video} do
      assert Engagement.favorited?(org, viewer, video) == false
    end
  end

  describe "list_favorites/3" do
    test "returns a pagination struct with favorited videos", %{org: org, viewer: viewer} do
      v1 = insert(:video, organization: org, mux_status: "ready")
      v2 = insert(:video, organization: org, mux_status: "ready")

      {:ok, _id, :added} = Engagement.toggle_favorite(org, viewer, v1)
      {:ok, _id, :added} = Engagement.toggle_favorite(org, viewer, v2)

      result = Engagement.list_favorites(org, viewer)
      assert result.total == 2
      assert length(result.results) == 2
    end

    test "excludes soft-deleted favorites", %{org: org, viewer: viewer, video: video} do
      {:ok, _id, :added} = Engagement.toggle_favorite(org, viewer, video)
      {:ok, _id, :removed} = Engagement.toggle_favorite(org, viewer, video)

      result = Engagement.list_favorites(org, viewer)
      assert result.total == 0
    end
  end

  describe "multi-tenant isolation" do
    test "favorites from one org not visible in another" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org_a)
      video = insert(:video, organization: org_a)

      {:ok, _id, :added} = Engagement.toggle_favorite(org_a, viewer, video)

      result = Engagement.list_favorites(org_b, viewer)
      assert result.results == []
    end
  end
end
