defmodule BobineWeb.Viewer.WatchLiveEventsTest do
  use BobineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bobine.Engagement

  setup do
    if :ets.whereis(:bobine_go_back) == :undefined do
      :ets.new(:bobine_go_back, [:named_table, :public, :set])
    end

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

  describe "toggle_queue" do
    test "toggles queue panel open and closed", %{org: org, viewer: viewer, video: video} do
      other = insert(:video, organization: org, mux_status: "ready", mux_playback_id: "pb_tq")
      {:ok, _} = Engagement.add_to_queue(org, viewer, other)

      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      # Queue should be open by default when it has items
      assert html =~ "open"

      view |> element(~s([data-test="toggle-queue-btn"])) |> render_click()
      html = render(view)
      refute html =~ ~r/sv-queue-panel[^"]*open/
    end
  end

  describe "playback_ended / skip_to_next" do
    test "skip_to_next advances to next video in queue", %{org: org, viewer: viewer, video: video} do
      next_video =
        insert(:video,
          organization: org,
          title: "Next Video",
          mux_status: "ready",
          mux_playback_id: "pb_next",
          visibility: "subscribers_only",
          duration: 60.0
        )

      {:ok, _} = Engagement.add_to_queue(org, viewer, next_video)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      view |> element(~s([data-test="skip-next-btn"])) |> render_click()

      html = render(view)
      assert html =~ "Next Video"
    end

    test "skip_to_next enables go_back", %{org: org, viewer: viewer, video: video} do
      next_video =
        insert(:video,
          organization: org,
          title: "Next Video",
          mux_status: "ready",
          mux_playback_id: "pb_next2",
          visibility: "subscribers_only",
          duration: 60.0
        )

      {:ok, _} = Engagement.add_to_queue(org, viewer, next_video)

      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      # Go back should not be available initially
      refute html =~ ~s(data-test="go-back-btn")

      view |> element(~s([data-test="skip-next-btn"])) |> render_click()

      html = render(view)
      assert html =~ ~s(data-test="go-back-btn")
    end

    test "skip_to_next with empty queue shows empty queue state", %{viewer: viewer, video: video} do
      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")

      # No skip button when queue is empty — verify it's not present
      refute has_element?(view, ~s([data-test="skip-next-btn"]))
    end

    test "playback_ended advances to next video", %{org: org, viewer: viewer, video: video} do
      next_video =
        insert(:video,
          organization: org,
          title: "Auto Next",
          mux_status: "ready",
          mux_playback_id: "pb_auto",
          visibility: "subscribers_only",
          duration: 90.0
        )

      {:ok, _} = Engagement.add_to_queue(org, viewer, next_video)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")

      render_hook(view, "playback_ended", %{"video_id" => video.id})

      html = render(view)
      assert html =~ "Auto Next"
    end
  end

  describe "go_back" do
    test "go_back returns to previous video after skip", %{org: org, viewer: viewer, video: video} do
      next_video =
        insert(:video,
          organization: org,
          title: "Skipped To",
          mux_status: "ready",
          mux_playback_id: "pb_skip",
          visibility: "subscribers_only",
          duration: 60.0
        )

      {:ok, _} = Engagement.add_to_queue(org, viewer, next_video)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      view |> element(~s([data-test="skip-next-btn"])) |> render_click()

      # Should now show "Skipped To"
      html = render(view)
      assert html =~ "Skipped To"

      # Go back to "Main Video"
      view |> element(~s([data-test="go-back-btn"])) |> render_click()

      html = render(view)
      assert html =~ "Main Video"
      # Go back should no longer be available after going back
      refute html =~ ~s(data-test="go-back-btn")
    end
  end

  describe "go_back_expired timer" do
    test "go_back disappears after timer fires", %{org: org, viewer: viewer, video: video} do
      next_video =
        insert(:video,
          organization: org,
          title: "Next Timer",
          mux_status: "ready",
          mux_playback_id: "pb_timer",
          visibility: "subscribers_only",
          duration: 60.0
        )

      {:ok, _} = Engagement.add_to_queue(org, viewer, next_video)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      view |> element(~s([data-test="skip-next-btn"])) |> render_click()

      assert has_element?(view, ~s([data-test="go-back-btn"]))

      # Simulate the timer expiration
      send(view.pid, :go_back_expired)
      # Give the process time to handle the message
      Process.sleep(50)

      html = render(view)
      refute html =~ ~s(data-test="go-back-btn")
    end
  end

  describe "playback_progress" do
    test "records progress for viewer", %{viewer: viewer, video: video} do
      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")

      render_hook(view, "playback_progress", %{
        "video_id" => video.id,
        "position" => 45.5
      })

      # Should not crash — progress is buffered
      html = render(view)
      assert html =~ "Main Video"
    end
  end

  describe "add_to_queue duplicate handling" do
    test "adding duplicate shows flash message", %{org: org, viewer: viewer, video: video} do
      {:ok, _} = Engagement.add_to_queue(org, viewer, video)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      view |> element(~s([data-test="add-to-queue-btn"])) |> render_click()

      html = render(view)
      assert html =~ "Already in your queue"
    end
  end

  describe "favorite and watchlist initial state on load" do
    test "favorite button shows filled state when already favorited", %{org: org, viewer: viewer, video: video} do
      {:ok, :added} = Engagement.toggle_favorite(org, viewer, video)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      assert html =~ "hero-heart-solid"
    end

    test "watchlist button shows filled state when already in watchlist", %{org: org, viewer: viewer, video: video} do
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, video)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      assert html =~ "hero-bookmark-solid"
    end

    test "favorite button shows unfilled when not favorited", %{viewer: viewer, video: video} do
      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      refute html =~ "hero-heart-solid"
    end

    test "watchlist button shows unfilled when not in watchlist", %{viewer: viewer, video: video} do
      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      refute html =~ "hero-bookmark-solid"
    end
  end

  describe "watchlist toggle round-trip" do
    test "add then remove from watchlist", %{viewer: viewer, video: video} do
      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")

      # Add to watchlist
      view |> element(~s([data-test="watchlist-btn"])) |> render_click()
      html = render(view)
      assert html =~ "hero-bookmark-solid"

      # Remove from watchlist
      view |> element(~s([data-test="watchlist-btn"])) |> render_click()
      html = render(view)
      refute html =~ "hero-bookmark-solid"
    end
  end

  describe "favorite toggle round-trip" do
    test "add then remove then re-add favorite", %{viewer: viewer, video: video} do
      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")

      # Add favorite
      view |> element(~s([data-test="favorite-btn"])) |> render_click()
      assert render(view) =~ "hero-heart-solid"

      # Remove favorite
      view |> element(~s([data-test="favorite-btn"])) |> render_click()
      refute render(view) =~ "hero-heart-solid"

      # Re-add (soft-delete restore)
      view |> element(~s([data-test="favorite-btn"])) |> render_click()
      assert render(view) =~ "hero-heart-solid"
    end
  end
end
