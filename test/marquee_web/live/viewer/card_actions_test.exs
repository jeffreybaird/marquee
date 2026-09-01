defmodule MarqueeWeb.Viewer.CardActionsTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "card rendering" do
    test "renders popup with video info on content card", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      insert(:video,
        organization: org,
        title: "Test Popup Video",
        description: "A great video description",
        duration: 3661.0,
        mux_status: "ready"
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse")

      assert html =~ ~s(data-test="sv-card-popup-)
      assert html =~ "Test Popup Video"
      assert html =~ "A great video description"
    end

    test "portrait-variant rows omit hover preview popup + CardFocus hook", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      video =
        insert(:video,
          organization: org,
          title: "Portrait Video",
          mux_status: "ready",
          mux_playback_id: "pb_portrait"
        )

      row =
        insert(:row,
          organization: org,
          title: "Portrait Row",
          source_type: :curated,
          card_variant: "poster_portrait",
          visible: true,
          position: 0
        )

      insert(:row_item, organization: org, row: row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")

      assert html =~ ~s(data-card-variant="poster_portrait")
      refute html =~ ~s(data-test="sv-card-popup-#{video.id}")
      refute html =~ ~s(phx-hook="CardFocus")
    end

    test "renders action buttons for authenticated viewer", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, title: "Action Video", mux_status: "ready")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse")

      assert html =~ ~s(data-test="sv-card-watchlist-#{video.id}")
      assert html =~ ~s(data-test="sv-card-favorite-#{video.id}")
      assert html =~ ~s(data-test="sv-card-queue-#{video.id}")
    end

    test "renders action buttons even without viewer session", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      _membership = insert(:membership, user: user, organization: org, role: :admin)
      video = insert(:video, organization: org, title: "No Auth Video", mux_status: "ready")

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")
        |> log_in_user(user)

      {:ok, _view, html} = live(conn, ~p"/browse")

      assert html =~ ~s(data-test="sv-card-watchlist-#{video.id}")
      assert html =~ ~s(data-test="sv-card-favorite-#{video.id}")
      assert html =~ ~s(data-test="sv-card-queue-#{video.id}")
    end
  end

  describe "card_add_to_watchlist event" do
    test "adds video to watchlist with optimistic UI", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, mux_status: "ready")

      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/browse")

      # Initially not in watchlist
      refute html =~ ~s(aria-pressed="true")

      html =
        view
        |> element(~s([data-test="sv-card-watchlist-#{video.id}"]))
        |> render_click()

      # Button now shows active state
      assert html =~ ~s(hero-bookmark-solid)

      # Verify persisted
      assert Marquee.Engagement.in_watchlist?(org, viewer, video)
    end

    test "no-ops when already in watchlist", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, mux_status: "ready")

      Marquee.Engagement.add_to_watchlist(org, viewer, video)

      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/browse")

      # Already active on load
      assert html =~ ~s(hero-bookmark-solid)

      # Click again — stays active, no error
      html =
        view
        |> element(~s([data-test="sv-card-watchlist-#{video.id}"]))
        |> render_click()

      assert html =~ ~s(hero-bookmark-solid)
    end
  end

  describe "card_toggle_favorite event" do
    test "favorites a video with optimistic UI", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, mux_status: "ready")

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/browse")

      html =
        view
        |> element(~s([data-test="sv-card-favorite-#{video.id}"]))
        |> render_click()

      # Filled heart icon
      assert html =~ ~s(hero-heart-solid)
      assert Marquee.Engagement.favorited?(org, viewer, video)
    end

    test "unfavorites when already favorited", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, mux_status: "ready")

      Marquee.Engagement.toggle_favorite(org, viewer, video)

      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/browse")
      assert html =~ ~s(hero-heart-solid)

      html =
        view
        |> element(~s([data-test="sv-card-favorite-#{video.id}"]))
        |> render_click()

      # Back to outline heart
      refute html =~ ~s(hero-heart-solid)
      refute Marquee.Engagement.favorited?(org, viewer, video)
    end
  end

  describe "card_add_to_queue event" do
    test "adds video to queue with optimistic UI", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, mux_status: "ready")

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/browse")

      html =
        view
        |> element(~s([data-test="sv-card-queue-#{video.id}"]))
        |> render_click()

      assert html =~ ~s(hero-queue-list-solid)

      %{results: queue} = Marquee.Engagement.list_queue(org, viewer)
      assert Enum.any?(queue, &(&1.video_id == video.id))
    end

    test "no-ops when already in queue", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, mux_status: "ready")

      Marquee.Engagement.add_to_queue(org, viewer, video)

      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/browse")
      assert html =~ ~s(hero-queue-list-solid)

      html =
        view
        |> element(~s([data-test="sv-card-queue-#{video.id}"]))
        |> render_click()

      assert html =~ ~s(hero-queue-list-solid)
    end
  end
end
