defmodule MarqueeWeb.Viewer.ShortsLiveEventsTest do
  # async: false — the progress buffer is a shared ETS table and telemetry
  # handlers are global.
  use MarqueeWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Marquee.Accounts.Scope
  alias Marquee.Buffers.{EngagementBuffer, ProgressBuffer}
  alias Marquee.{Content, Engagement, Repo}
  alias Marquee.Engagement.{PlaybackDropOff, Progress, WatchHistory}

  setup do
    ProgressBuffer.clear()
    # Drain entries left by earlier tests before asserting on rows.
    :ok = EngagementBuffer.flush()

    org = insert(:organization, shorts_feed_enabled: true, shorts_feed_access: "subscribers_only")
    viewer = insert(:subscribed_viewer, organization: org)
    %{org: org, viewer: viewer}
  end

  defp owner_scope(org) do
    membership =
      insert(:membership, organization: org, user: insert(:user), role: :owner)
      |> Repo.preload([:user, :organization])

    Scope.for_user(membership.user) |> Scope.with_organization(org, membership)
  end

  defp seed_feed(org, count) do
    scope = owner_scope(org)

    for n <- 1..count do
      video =
        insert(:video,
          organization: org,
          title: "Event Short #{n}",
          mux_status: "ready",
          duration: 30.0,
          aspect_ratio: "9:16"
        )

      {:ok, _} = Content.add_short_feed_video(scope, video)
      video
    end
  end

  defp attach_viewed_handler do
    handler_id = "shorts-viewed-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:marquee, :video, :viewed],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:video_viewed, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp buffered(org, viewer, video), do: ProgressBuffer.get_viewer(org.id, viewer.id, video.id)

  defp completed?(org, viewer, video) do
    match?(
      %{completed: true},
      Repo.get_by(Progress, organization_id: org.id, viewer_id: viewer.id, video_id: video.id)
    )
  end

  defp history?(viewer, video) do
    Repo.exists?(
      from h in WatchHistory, where: h.viewer_id == ^viewer.id and h.video_id == ^video.id
    )
  end

  defp drop_off?(viewer, video) do
    Repo.exists?(
      from d in PlaybackDropOff, where: d.viewer_id == ^viewer.id and d.video_id == ^video.id
    )
  end

  defp push_all_events(view, video) do
    for event <- ["playback_started", "playback_progress", "playback_paused"] do
      render_hook(view, event, %{"video_id" => video.id, "position" => 12.5})
    end

    render_hook(view, "playback_clip_activated", %{"video_id" => video.id})

    render_hook(view, "playback_drop_off", %{
      "video_id" => video.id,
      "max_position" => 12.5,
      "video_duration" => 30.0
    })

    render_hook(view, "playback_ended", %{"video_id" => video.id})
  end

  # Flushes both buffers first so "nothing written" also covers entries that
  # might have been buffered instead of written directly.
  defp assert_nothing_written(org, viewer, video) do
    :ok = EngagementBuffer.flush()
    assert buffered(org, viewer, video) == nil
    refute completed?(org, viewer, video)
    refute history?(viewer, video)
    refute drop_off?(viewer, video)
    video_id = video.id
    refute_received {:video_viewed, _, %{video_id: ^video_id}}
  end

  describe "playable clip events" do
    test "progress and pause write to the progress buffer", %{org: org, viewer: viewer} do
      [video] = seed_feed(org, 1)
      {:ok, view, _} = live(conn_for_viewer(viewer), ~p"/shorts")

      render_hook(view, "playback_started", %{"video_id" => video.id})
      render_hook(view, "playback_progress", %{"video_id" => video.id, "position" => 7.5})
      assert %{position: 7.5} = buffered(org, viewer, video)

      render_hook(view, "playback_paused", %{"video_id" => video.id, "position" => 9.0})
      assert %{position: 9.0} = buffered(org, viewer, video)

      # Buffered, not written directly to Postgres.
      refute Repo.get_by(Progress, viewer_id: viewer.id, video_id: video.id)

      :ok = ProgressBuffer.flush()
      assert Repo.get_by(Progress, viewer_id: viewer.id, video_id: video.id).position == 9.0
    end

    test "progress beyond the duration is clamped", %{org: org, viewer: viewer} do
      [video] = seed_feed(org, 1)
      {:ok, view, _} = live(conn_for_viewer(viewer), ~p"/shorts")

      render_hook(view, "playback_progress", %{"video_id" => video.id, "position" => 99.0})
      assert %{position: 30.0} = buffered(org, viewer, video)
    end

    test "ended marks the clip completed and records watch history", %{
      org: org,
      viewer: viewer
    } do
      [video] = seed_feed(org, 1)
      {:ok, view, _} = live(conn_for_viewer(viewer), ~p"/shorts")

      render_hook(view, "playback_ended", %{"video_id" => video.id})

      # Buffered: nothing reaches Postgres until the engagement buffer flushes.
      refute completed?(org, viewer, video)
      refute history?(viewer, video)

      :ok = EngagementBuffer.flush()

      assert completed?(org, viewer, video)
      assert history?(viewer, video)
      assert Engagement.get_progress(org, viewer, video).completed
    end

    test "drop-off is recorded", %{org: org, viewer: viewer} do
      [video] = seed_feed(org, 1)
      {:ok, view, _} = live(conn_for_viewer(viewer), ~p"/shorts")

      render_hook(view, "playback_drop_off", %{
        "video_id" => video.id,
        "max_position" => 12.0,
        "video_duration" => 30.0
      })

      # Buffered: nothing reaches Postgres until the engagement buffer flushes.
      refute drop_off?(viewer, video)

      :ok = EngagementBuffer.flush()

      drop_off = Repo.get_by(PlaybackDropOff, viewer_id: viewer.id, video_id: video.id)
      assert drop_off.organization_id == org.id
      assert drop_off.max_position == 12.0
    end

    test "activating a clip emits the video-viewed metric", %{org: org, viewer: viewer} do
      [video] = seed_feed(org, 1)
      attach_viewed_handler()
      {:ok, view, _} = live(conn_for_viewer(viewer), ~p"/shorts")

      video_id = video.id
      org_id = org.id
      render_hook(view, "playback_clip_activated", %{"video_id" => video.id})

      assert_receive {:video_viewed, %{count: 1}, %{video_id: ^video_id, org_id: ^org_id}}
    end
  end

  describe "ignored events" do
    test "events for a clip locked to this viewer write nothing", %{org: org} do
      [video] = seed_feed(org, 1)
      unsubscribed = insert(:viewer, organization: org, subscription_status: "none")
      attach_viewed_handler()

      {:ok, view, _} = live(conn_for_viewer(unsubscribed), ~p"/shorts")
      push_all_events(view, video)

      assert_nothing_written(org, unsubscribed, video)
    end

    test "events for a clip not yet loaded are ignored until it loads", %{
      org: org,
      viewer: viewer
    } do
      videos = seed_feed(org, 10)
      ninth = Enum.at(videos, 8)
      attach_viewed_handler()

      {:ok, view, _} = live(conn_for_viewer(viewer), ~p"/shorts")
      push_all_events(view, ninth)
      assert_nothing_written(org, viewer, ninth)

      render_hook(view, "load_more", %{})
      render_hook(view, "playback_progress", %{"video_id" => ninth.id, "position" => 5.0})
      assert %{position: 5.0} = buffered(org, viewer, ninth)
    end

    test "events for another organization's video are ignored", %{org: org, viewer: viewer} do
      seed_feed(org, 1)
      other = insert(:organization, shorts_feed_enabled: true, shorts_feed_access: "public")
      [foreign] = seed_feed(other, 1)
      attach_viewed_handler()

      {:ok, view, _} = live(conn_for_viewer(viewer), ~p"/shorts")
      push_all_events(view, foreign)
      :ok = EngagementBuffer.flush()

      assert ProgressBuffer.get_viewer(org.id, viewer.id, foreign.id) == nil
      assert ProgressBuffer.get_viewer(other.id, viewer.id, foreign.id) == nil
      refute history?(viewer, foreign)
      refute drop_off?(viewer, foreign)
      refute Repo.exists?(from p in Progress, where: p.video_id == ^foreign.id)
      foreign_id = foreign.id
      refute_received {:video_viewed, _, %{video_id: ^foreign_id}}
    end

    test "events with an unknown video id are ignored", %{org: org, viewer: viewer} do
      seed_feed(org, 1)
      {:ok, view, _} = live(conn_for_viewer(viewer), ~p"/shorts")

      bogus = Ecto.UUID.generate()
      render_hook(view, "playback_progress", %{"video_id" => bogus, "position" => 3.0})
      render_hook(view, "playback_ended", %{"video_id" => bogus})
      :ok = EngagementBuffer.flush()

      assert ProgressBuffer.get_viewer(org.id, viewer.id, bogus) == nil
      assert has_element?(view, "#shorts-feed")
    end
  end

  describe "read-only sessions" do
    test "member preview writes nothing", %{org: org} do
      [video] = seed_feed(org, 1)
      user = insert(:user)
      insert(:membership, organization: org, user: user, role: :admin)
      attach_viewed_handler()

      conn = build_conn() |> log_in_user(user) |> get("/?org=#{org.slug}&preview=member")
      preview_viewer_id = get_session(conn, :member_preview_viewer_id)
      {:ok, view, _} = live(recycle(conn), "/shorts")

      push_all_events(view, video)
      :ok = EngagementBuffer.flush()

      assert ProgressBuffer.list_viewer_entries(org.id, preview_viewer_id) == []
      refute Repo.exists?(from p in Progress, where: p.video_id == ^video.id)
      refute Repo.exists?(from h in WatchHistory, where: h.video_id == ^video.id)
      refute Repo.exists?(from d in PlaybackDropOff, where: d.video_id == ^video.id)
    end

    test "operator impersonation writes nothing for the impersonated viewer", %{
      org: org,
      viewer: viewer
    } do
      [video] = seed_feed(org, 1)
      membership = insert(:membership, organization: org, role: :admin)

      {:ok, view, _} = live(conn_for_impersonating_viewer(membership, viewer), ~p"/shorts")
      push_all_events(view, video)
      :ok = EngagementBuffer.flush()

      assert buffered(org, viewer, video) == nil
      refute completed?(org, viewer, video)
      refute history?(viewer, video)
      refute drop_off?(viewer, video)
    end
  end
end
