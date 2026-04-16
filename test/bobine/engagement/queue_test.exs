defmodule Bobine.Engagement.QueueTest do
  use Bobine.DataCase, async: false

  alias Bobine.Engagement

  setup do
    # Ensure the ETS table exists for go-back state
    if :ets.whereis(:bobine_go_back) == :undefined do
      :ets.new(:bobine_go_back, [:named_table, :public, :set])
    end

    org = insert(:organization)
    viewer = insert(:subscribed_viewer, organization: org)

    videos =
      for i <- 1..5 do
        insert(:video,
          organization: org,
          title: "Video #{i}",
          mux_status: "ready",
          duration: 100.0
        )
      end

    %{org: org, viewer: viewer, videos: videos}
  end

  describe "add_to_queue/4" do
    test "adds video to the end of the queue", %{org: org, viewer: viewer, videos: [v1 | _]} do
      assert {:ok, item} = Engagement.add_to_queue(org, viewer, v1)
      assert item.video_id == v1.id
      assert item.position == 0
    end

    test "appends subsequent videos after the first", %{
      org: org,
      viewer: viewer,
      videos: [v1, v2 | _]
    } do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, item2} = Engagement.add_to_queue(org, viewer, v2)

      assert item2.position == 1
    end

    test "returns error for duplicate video", %{org: org, viewer: viewer, videos: [v1 | _]} do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      assert {:error, :already_in_queue} = Engagement.add_to_queue(org, viewer, v1)
    end

    test "records source of addition", %{org: org, viewer: viewer, videos: [v1 | _]} do
      {:ok, item} = Engagement.add_to_queue(org, viewer, v1, "search")
      assert item.video.id == v1.id

      # Verify the source was saved by checking the queue
      %{results: [queue_item]} = Engagement.list_queue(org, viewer)
      assert queue_item.added_from == "search"
    end
  end

  describe "play_next/4" do
    test "inserts at position 0 and shifts others down", %{
      org: org,
      viewer: viewer,
      videos: [v1, v2, v3 | _]
    } do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)

      {:ok, item} = Engagement.play_next(org, viewer, v3)
      assert item.video_id == v3.id

      %{results: queue} = Engagement.list_queue(org, viewer)
      assert Enum.map(queue, & &1.video_id) == [v3.id, v1.id, v2.id]
    end

    test "with video already in queue moves it to position 0", %{
      org: org,
      viewer: viewer,
      videos: [v1, v2, v3 | _]
    } do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v3)

      # v3 is at position 2, move to front
      {:ok, _} = Engagement.play_next(org, viewer, v3)

      %{results: queue} = Engagement.list_queue(org, viewer)
      assert Enum.map(queue, & &1.video_id) == [v3.id, v1.id, v2.id]
    end
  end

  describe "list_queue/2" do
    test "returns items in position order", %{org: org, viewer: viewer, videos: [v1, v2, v3 | _]} do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v3)

      %{results: queue} = Engagement.list_queue(org, viewer)
      assert length(queue) == 3
      assert Enum.map(queue, & &1.video_id) == [v1.id, v2.id, v3.id]
    end

    test "returns empty list when queue is empty", %{org: org, viewer: viewer} do
      assert %{results: [], total: 0} = Engagement.list_queue(org, viewer)
    end
  end

  describe "remove_from_queue/3" do
    test "hard-deletes the item", %{org: org, viewer: viewer, videos: [v1, v2 | _]} do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)

      :ok = Engagement.remove_from_queue(org, viewer, v1)

      %{results: queue} = Engagement.list_queue(org, viewer)
      assert length(queue) == 1
      assert hd(queue).video_id == v2.id
    end

    test "recompacts positions (no gaps)", %{org: org, viewer: viewer, videos: [v1, v2, v3 | _]} do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v3)

      :ok = Engagement.remove_from_queue(org, viewer, v2)

      %{results: queue} = Engagement.list_queue(org, viewer)
      positions = Enum.map(queue, & &1.position)
      assert positions == [0, 1]
    end
  end

  describe "clear_queue/2" do
    test "removes all items", %{org: org, viewer: viewer, videos: [v1, v2 | _]} do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)

      :ok = Engagement.clear_queue(org, viewer)

      assert %{results: [], total: 0} = Engagement.list_queue(org, viewer)
    end
  end

  describe "queue_count/2" do
    test "returns correct count", %{org: org, viewer: viewer, videos: [v1, v2 | _]} do
      assert Engagement.queue_count(org, viewer) == 0

      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      assert Engagement.queue_count(org, viewer) == 1

      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)
      assert Engagement.queue_count(org, viewer) == 2
    end
  end

  describe "peek_next/2" do
    test "returns the item at lowest position without removing", %{
      org: org,
      viewer: viewer,
      videos: [v1, v2 | _]
    } do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)

      next = Engagement.peek_next(org, viewer)
      assert next.video_id == v1.id

      # Still in queue
      assert Engagement.queue_count(org, viewer) == 2
    end

    test "returns nil when queue is empty", %{org: org, viewer: viewer} do
      assert Engagement.peek_next(org, viewer) == nil
    end
  end

  describe "advance_queue/3" do
    test "removes the completed video and returns next AND previous", %{
      org: org,
      viewer: viewer,
      videos: [v1, v2 | _]
    } do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)

      {:ok, result} = Engagement.advance_queue(org, viewer, v1)

      assert result.next_video.id == v2.id
      assert result.previous_video.id == v1.id

      # v1 should be removed from the queue
      %{results: queue} = Engagement.list_queue(org, viewer)
      assert length(queue) == 1
      assert hd(queue).video_id == v2.id
    end

    test "returns nil for next_video when queue is empty after removal", %{
      org: org,
      viewer: viewer,
      videos: [v1 | _]
    } do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)

      {:ok, result} = Engagement.advance_queue(org, viewer, v1)

      assert result.next_video == nil
      assert result.previous_video.id == v1.id
    end

    test "stores go-back state in ETS", %{org: org, viewer: viewer, videos: [v1, v2 | _]} do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)

      {:ok, _result} = Engagement.advance_queue(org, viewer, v1)

      state = Engagement.get_go_back_state(org, viewer)
      assert state != nil
      assert state.video_id == v1.id
    end
  end

  describe "go_back_in_queue/2" do
    test "re-inserts previous video at front of queue", %{
      org: org,
      viewer: viewer,
      videos: [v1, v2 | _]
    } do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)

      {:ok, _} = Engagement.advance_queue(org, viewer, v1)

      {:ok, result} = Engagement.go_back_in_queue(org, viewer)
      assert result.video.id == v1.id

      %{results: queue} = Engagement.list_queue(org, viewer)
      assert hd(queue).video_id == v1.id
    end

    test "returns the video and its resume position", %{
      org: org,
      viewer: viewer,
      videos: [v1, v2 | _]
    } do
      # Create a progress record
      insert(:progress, organization: org, viewer: viewer, video: v1, position: 45.0)

      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)
      {:ok, _} = Engagement.advance_queue(org, viewer, v1)

      {:ok, result} = Engagement.go_back_in_queue(org, viewer)
      assert result.resume_position == 45.0
    end

    test "within 60 seconds succeeds", %{org: org, viewer: viewer, videos: [v1, v2 | _]} do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)
      {:ok, _} = Engagement.advance_queue(org, viewer, v1)

      assert {:ok, _} = Engagement.go_back_in_queue(org, viewer)
    end

    test "after 60 seconds returns go_back_expired", %{
      org: org,
      viewer: viewer,
      videos: [v1, v2 | _]
    } do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)
      {:ok, _} = Engagement.advance_queue(org, viewer, v1)

      # Manually expire the go-back state
      key = {:go_back, org.id, viewer.id}
      [{^key, state}] = :ets.lookup(:bobine_go_back, key)
      expired_state = %{state | advanced_at: DateTime.add(DateTime.utc_now(), -61, :second)}
      :ets.insert(:bobine_go_back, {key, expired_state})

      assert {:error, :go_back_expired} = Engagement.go_back_in_queue(org, viewer)
    end

    test "with no previous advance returns no_go_back_available", %{org: org, viewer: viewer} do
      assert {:error, :no_go_back_available} = Engagement.go_back_in_queue(org, viewer)
    end

    test "clears the go-back state after use (can't go back twice)", %{
      org: org,
      viewer: viewer,
      videos: [v1, v2 | _]
    } do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)
      {:ok, _} = Engagement.advance_queue(org, viewer, v1)

      {:ok, _} = Engagement.go_back_in_queue(org, viewer)
      assert {:error, :no_go_back_available} = Engagement.go_back_in_queue(org, viewer)
    end
  end

  describe "add_collection_to_queue/3" do
    test "adds all collection videos in order", %{org: org, viewer: viewer} do
      collection = insert(:collection, organization: org)
      v1 = insert(:video, organization: org, mux_status: "ready")
      v2 = insert(:video, organization: org, mux_status: "ready")
      v3 = insert(:video, organization: org, mux_status: "ready")

      insert(:collection_item, organization: org, collection: collection, video: v1, position: 0)
      insert(:collection_item, organization: org, collection: collection, video: v2, position: 1)
      insert(:collection_item, organization: org, collection: collection, video: v3, position: 2)

      {:ok, count} = Engagement.add_collection_to_queue(org, viewer, collection)
      assert count == 3

      %{results: queue} = Engagement.list_queue(org, viewer)
      assert Enum.map(queue, & &1.video_id) == [v1.id, v2.id, v3.id]
    end

    test "skips videos already in queue", %{org: org, viewer: viewer} do
      collection = insert(:collection, organization: org)
      v1 = insert(:video, organization: org, mux_status: "ready")
      v2 = insert(:video, organization: org, mux_status: "ready")

      insert(:collection_item, organization: org, collection: collection, video: v1, position: 0)
      insert(:collection_item, organization: org, collection: collection, video: v2, position: 1)

      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, count} = Engagement.add_collection_to_queue(org, viewer, collection)
      assert count == 1

      %{results: queue} = Engagement.list_queue(org, viewer)
      assert length(queue) == 2
    end

    test "appends after existing queue items", %{org: org, viewer: viewer, videos: [existing | _]} do
      collection = insert(:collection, organization: org)
      v1 = insert(:video, organization: org, mux_status: "ready")

      insert(:collection_item, organization: org, collection: collection, video: v1, position: 0)

      {:ok, _} = Engagement.add_to_queue(org, viewer, existing)
      {:ok, _} = Engagement.add_collection_to_queue(org, viewer, collection)

      %{results: queue} = Engagement.list_queue(org, viewer)
      assert hd(queue).video_id == existing.id
      assert List.last(queue).video_id == v1.id
    end
  end

  describe "reorder_queue/3" do
    test "updates all positions", %{org: org, viewer: viewer, videos: [v1, v2, v3 | _]} do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v3)

      # Reverse order
      :ok = Engagement.reorder_queue(org, viewer, [v3.id, v2.id, v1.id])

      %{results: queue} = Engagement.list_queue(org, viewer)
      assert Enum.map(queue, & &1.video_id) == [v3.id, v2.id, v1.id]
    end

    test "with same order is a no-op", %{org: org, viewer: viewer, videos: [v1, v2 | _]} do
      {:ok, _} = Engagement.add_to_queue(org, viewer, v1)
      {:ok, _} = Engagement.add_to_queue(org, viewer, v2)

      :ok = Engagement.reorder_queue(org, viewer, [v1.id, v2.id])

      %{results: queue} = Engagement.list_queue(org, viewer)
      assert Enum.map(queue, & &1.video_id) == [v1.id, v2.id]
    end
  end

  describe "multi-tenant isolation" do
    test "viewer A's queue on org X is not visible to viewer B on org X", %{
      org: org,
      videos: [v1 | _]
    } do
      viewer_a = insert(:subscribed_viewer, organization: org)
      viewer_b = insert(:subscribed_viewer, organization: org)

      {:ok, _} = Engagement.add_to_queue(org, viewer_a, v1)

      assert %{results: [], total: 0} = Engagement.list_queue(org, viewer_b)
    end

    test "viewer A's queue on org X is not visible from org Y", %{videos: [_v1 | _]} do
      org_x = insert(:organization)
      org_y = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org_x)

      video = insert(:video, organization: org_x, mux_status: "ready")
      {:ok, _} = Engagement.add_to_queue(org_x, viewer, video)

      assert %{results: [], total: 0} = Engagement.list_queue(org_y, viewer)
    end
  end
end
