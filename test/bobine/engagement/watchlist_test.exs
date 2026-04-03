defmodule Bobine.Engagement.WatchlistTest do
  use Bobine.DataCase, async: true

  alias Bobine.Engagement

  setup do
    org = insert(:organization)
    viewer = insert(:subscribed_viewer, organization: org)
    video = insert(:video, organization: org, mux_status: "ready")

    %{org: org, viewer: viewer, video: video}
  end

  describe "add_to_watchlist/3" do
    test "creates a watchlist item", %{org: org, viewer: viewer, video: video} do
      assert {:ok, item} = Engagement.add_to_watchlist(org, viewer, video)
      assert item.viewer_id == viewer.id
      assert item.video_id == video.id
    end

    test "returns error for duplicate video", %{org: org, viewer: viewer, video: video} do
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, video)
      assert {:error, :already_in_watchlist} = Engagement.add_to_watchlist(org, viewer, video)
    end

    test "restores soft-deleted item rather than creating duplicate", %{org: org, viewer: viewer, video: video} do
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, video)
      {:ok, _} = Engagement.remove_from_watchlist(org, viewer, video)

      # Should restore, not create new
      assert {:ok, restored} = Engagement.add_to_watchlist(org, viewer, video)
      assert restored.deleted_at == nil
    end
  end

  describe "remove_from_watchlist/3" do
    test "soft-deletes the item", %{org: org, viewer: viewer, video: video} do
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, video)
      {:ok, deleted} = Engagement.remove_from_watchlist(org, viewer, video)
      assert deleted.deleted_at != nil
    end

    test "returns error if not found", %{org: org, viewer: viewer, video: video} do
      assert {:error, :not_found} = Engagement.remove_from_watchlist(org, viewer, video)
    end
  end

  describe "in_watchlist?/3" do
    test "returns true when video is in watchlist", %{org: org, viewer: viewer, video: video} do
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, video)
      assert Engagement.in_watchlist?(org, viewer, video) == true
    end

    test "returns false when video is not in watchlist", %{org: org, viewer: viewer, video: video} do
      assert Engagement.in_watchlist?(org, viewer, video) == false
    end

    test "returns false for soft-deleted items", %{org: org, viewer: viewer, video: video} do
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, video)
      {:ok, _} = Engagement.remove_from_watchlist(org, viewer, video)
      assert Engagement.in_watchlist?(org, viewer, video) == false
    end
  end

  describe "list_watchlist/3" do
    test "returns a pagination struct", %{org: org, viewer: viewer} do
      v1 = insert(:video, organization: org, mux_status: "ready")
      v2 = insert(:video, organization: org, mux_status: "ready")

      {:ok, _} = Engagement.add_to_watchlist(org, viewer, v1)
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, v2)

      result = Engagement.list_watchlist(org, viewer)
      assert result.total == 2
      assert length(result.results) == 2
    end
  end

  describe "multi-tenant isolation" do
    test "viewer's watchlist is not visible from another org", %{viewer: _viewer, video: _video} do
      org_a = insert(:organization)
      org_b = insert(:organization)
      viewer_a = insert(:subscribed_viewer, organization: org_a)
      video_a = insert(:video, organization: org_a)

      {:ok, _} = Engagement.add_to_watchlist(org_a, viewer_a, video_a)

      result = Engagement.list_watchlist(org_b, viewer_a)
      assert result.results == []
    end
  end
end
