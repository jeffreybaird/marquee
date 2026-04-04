defmodule BobineWeb.Viewer.WatchLiveQueueTest do
  use BobineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bobine.Buffers.ProgressBuffer
  alias Bobine.Engagement

  setup do
    # Ensure the ETS table exists for go-back state
    if :ets.whereis(:bobine_go_back) == :undefined do
      :ets.new(:bobine_go_back, [:named_table, :public, :set])
    end

    ProgressBuffer.clear()

    org = insert(:organization)
    viewer = insert(:subscribed_viewer, organization: org)

    video =
      insert(:video,
        organization: org,
        title: "Main Video",
        mux_status: "ready",
        mux_playback_id: "pb_main",
        visibility: "subscribers_only",
        duration: 100.0
      )

    %{org: org, viewer: viewer, video: video}
  end

  describe "queue panel" do
    test "renders empty queue state", %{viewer: viewer, video: video} do
      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      assert html =~ ~s(data-test="queue-empty")
      assert html =~ "Your queue is empty"
    end

    test "renders queue items after the panel is opened", %{
      org: org,
      viewer: viewer,
      video: video
    } do
      other_video =
        insert(:video,
          organization: org,
          title: "Queued Video",
          mux_status: "ready",
          mux_playback_id: "pb_queued"
        )

      {:ok, _} = Engagement.add_to_queue(org, viewer, other_video)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      view |> element(~s([data-test="toggle-queue-btn"])) |> render_click()

      html = render(view)
      assert html =~ "Queued Video"
      assert html =~ ~s(data-test="queue-list")
    end

    test "add to queue adds video and opens panel", %{viewer: viewer, video: video} do
      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")

      view |> element(~s([data-test="add-to-queue-btn"])) |> render_click()

      html = render(view)
      assert html =~ ~s(data-test="queue-list")
      assert html =~ ~s(data-test="queue-item-#{video.id}")
    end

    test "play next inserts at front", %{org: org, viewer: viewer, video: video} do
      other =
        insert(:video,
          organization: org,
          title: "Other",
          mux_status: "ready",
          mux_playback_id: "pb_other"
        )

      {:ok, _} = Engagement.add_to_queue(org, viewer, other)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      view |> element(~s([data-test="play-next-btn"])) |> render_click()

      html = render(view)
      # The main video should be first (position 0)
      assert html =~ ~s(data-test="queue-item-#{video.id}")
    end

    test "remove from queue removes item", %{org: org, viewer: viewer, video: video} do
      other =
        insert(:video,
          organization: org,
          title: "To Remove",
          mux_status: "ready",
          mux_playback_id: "pb_remove"
        )

      {:ok, _} = Engagement.add_to_queue(org, viewer, other)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      view |> element(~s([data-test="toggle-queue-btn"])) |> render_click()
      view |> element(~s([data-test="queue-remove-#{other.id}"])) |> render_click()

      # Assert the queue panel specifically — the video may still appear in related videos
      queue_html = view |> element(~s([data-test="queue-panel"])) |> render()
      refute queue_html =~ "To Remove"
    end

    test "clear queue empties the queue", %{org: org, viewer: viewer, video: video} do
      other = insert(:video, organization: org, mux_status: "ready", mux_playback_id: "pb_c")
      {:ok, _} = Engagement.add_to_queue(org, viewer, other)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      view |> element(~s([data-test="toggle-queue-btn"])) |> render_click()
      view |> element(~s([data-test="clear-queue-btn"])) |> render_click()

      html = render(view)
      assert html =~ ~s(data-test="queue-empty")
    end

    test "next button only visible when queue has items", %{viewer: viewer, video: video} do
      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      refute html =~ ~s(data-test="skip-next-btn")
    end

    test "next button visible when queue has items", %{org: org, viewer: viewer, video: video} do
      other = insert(:video, organization: org, mux_status: "ready", mux_playback_id: "pb_n")
      {:ok, _} = Engagement.add_to_queue(org, viewer, other)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      assert html =~ ~s(data-test="skip-next-btn")
    end
  end

  describe "favorites and watchlist toggles" do
    test "favorite toggle changes heart state", %{viewer: viewer, video: video} do
      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      refute html =~ "hero-heart-solid"

      view |> element(~s([data-test="favorite-btn"])) |> render_click()

      html = render(view)
      assert html =~ "hero-heart-solid"
    end

    test "watchlist toggle changes bookmark state", %{viewer: viewer, video: video} do
      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      refute html =~ "hero-bookmark-solid"

      view |> element(~s([data-test="watchlist-btn"])) |> render_click()

      html = render(view)
      assert html =~ "hero-bookmark-solid"
    end
  end

  describe "video actions data-test attributes" do
    test "all required data-test attributes present", %{org: org, viewer: viewer, video: video} do
      other = insert(:video, organization: org, mux_status: "ready", mux_playback_id: "pb_dt")
      {:ok, _} = Engagement.add_to_queue(org, viewer, other)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")

      assert html =~ ~s(data-test="video-actions")
      assert html =~ ~s(data-test="add-to-queue-btn")
      assert html =~ ~s(data-test="play-next-btn")
      assert html =~ ~s(data-test="favorite-btn")
      assert html =~ ~s(data-test="watchlist-btn")
      assert html =~ ~s(data-test="queue-panel")
      assert html =~ ~s(data-test="toggle-queue-btn")
    end
  end
end
