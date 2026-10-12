defmodule MarqueeWeb.Viewer.ShortsLiveAccessTest do
  @moduledoc """
  Feed-level access for /shorts. The organization's `shorts_feed_access`
  decides every clip; each video's own visibility is ignored in the feed.
  A locked clip must never leak its Mux playback id or any image.mux.com URL.
  """
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Accounts.Scope
  alias Marquee.{Content, Repo, Viewers}

  defp shorts_org(access, attrs \\ []) do
    insert(
      :organization,
      Keyword.merge([shorts_feed_enabled: true, shorts_feed_access: access], attrs)
    )
  end

  defp owner_scope(org) do
    membership =
      insert(:membership, organization: org, user: insert(:user), role: :owner)
      |> Repo.preload([:user, :organization])

    Scope.for_user(membership.user) |> Scope.with_organization(org, membership)
  end

  defp seed_feed(org, count, attrs \\ []) do
    scope = owner_scope(org)

    for n <- 1..count do
      video =
        insert(
          :video,
          Keyword.merge(
            [
              organization: org,
              title: "Gated Short #{n}",
              mux_status: "ready",
              mux_playback_id: "pbsecret#{n}x#{System.unique_integer([:positive])}",
              duration: 20.0,
              aspect_ratio: "9:16"
            ],
            attrs
          )
        )

      {:ok, _} = Content.add_short_feed_video(scope, video)
      video
    end
  end

  defp anon_conn(org) do
    build_conn() |> Map.put(:host, "#{org.slug}.localhost") |> init_test_session(%{})
  end

  defp future, do: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second)
  defp past, do: DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

  # Returns a conn for the given viewer state on `org`.
  defp conn_for_state(:logged_out, org), do: anon_conn(org)

  defp conn_for_state(:free, org),
    do: conn_for_viewer(insert(:viewer, organization: org, subscription_status: "none"))

  defp conn_for_state(:subscribed, org),
    do: conn_for_viewer(insert(:subscribed_viewer, organization: org))

  defp conn_for_state(:complimentary, org) do
    viewer = insert(:viewer, organization: org, subscription_status: "none")
    {:ok, granted} = Viewers.grant_access(owner_scope(org), viewer)
    conn_for_viewer(granted)
  end

  defp conn_for_state(:trial_valid, org) do
    conn_for_viewer(
      insert(:viewer, organization: org, subscription_status: "trial", trial_expires_at: future())
    )
  end

  defp conn_for_state(:trial_expired, org) do
    conn_for_viewer(
      insert(:viewer, organization: org, subscription_status: "trial", trial_expires_at: past())
    )
  end

  defp conn_for_state(:past_due, org),
    do: conn_for_viewer(insert(:viewer, organization: org, subscription_status: "past_due"))

  defp conn_for_state(:canceled, org),
    do: conn_for_viewer(insert(:viewer, organization: org, subscription_status: "canceled"))

  defp conn_for_state(:banned, org) do
    conn_for_viewer(
      insert(:viewer, organization: org, subscription_status: "active", status: :banned)
    )
  end

  defp conn_for_state(:expired, org),
    do: conn_for_viewer(insert(:viewer, organization: org, subscription_status: "expired"))

  defp conn_for_state(:suspended, org) do
    conn_for_viewer(
      insert(:viewer, organization: org, subscription_status: "active", status: :suspended)
    )
  end

  defp article(video), do: ~s(article[data-video-id="#{video.id}"])

  defp assert_playable(view, video) do
    assert has_element?(view, ~s(#{article(video)}[data-playback-id="#{video.mux_playback_id}"]))
    refute has_element?(view, ~s([data-test="short-locked-#{video.id}"]))
  end

  defp assert_locked(view, video, cta_href) do
    html = render(view)
    assert has_element?(view, article(video))
    assert has_element?(view, ~s([data-test="short-locked-#{video.id}"]))
    refute has_element?(view, ~s(#{article(video)}[data-playback-id]))
    refute has_element?(view, ~s(#{article(video)} [data-player-slot]))
    refute html =~ video.mux_playback_id

    case cta_href do
      nil ->
        refute has_element?(view, ~s([data-test="short-locked-#{video.id}"] a[href="/subscribe"]))
        refute has_element?(view, ~s([data-test="short-locked-#{video.id}"][href="/subscribe"]))

      href ->
        assert has_element?(view, ~s([data-test="short-locked-#{video.id}"] a[href="#{href}"])) or
                 has_element?(view, ~s(a[data-test="short-locked-#{video.id}"][href="#{href}"])),
               "expected a #{href} call to action for a locked clip"
    end
  end

  @matrix %{
    "public" => [
      logged_out: :playable,
      free: :playable,
      subscribed: :playable,
      complimentary: :playable,
      trial_valid: :playable,
      trial_expired: :playable,
      past_due: :playable,
      canceled: :playable,
      expired: :playable,
      suspended: {:locked, nil},
      banned: {:locked, nil}
    ],
    "free_with_account" => [
      logged_out: {:locked, "/login"},
      free: :playable,
      subscribed: :playable,
      complimentary: :playable,
      trial_valid: :playable,
      trial_expired: :playable,
      past_due: :playable,
      canceled: :playable,
      expired: :playable,
      suspended: {:locked, nil},
      banned: {:locked, nil}
    ],
    "subscribers_only" => [
      logged_out: {:locked, "/login"},
      free: {:locked, "/subscribe"},
      subscribed: :playable,
      complimentary: :playable,
      trial_valid: :playable,
      trial_expired: {:locked, "/subscribe"},
      past_due: {:locked, "/account/payment-issue"},
      canceled: {:locked, "/subscribe"},
      expired: {:locked, "/subscribe"},
      suspended: {:locked, nil},
      banned: {:locked, nil}
    ]
  }

  for {level, cases} <- @matrix, {state, expected} <- cases do
    @level level
    @state state
    @expected expected

    test "#{level} feed, #{state} viewer: #{inspect(expected)}" do
      org = shorts_org(@level)
      videos = seed_feed(org, 2)

      {:ok, view, html} = live(conn_for_state(@state, org), ~p"/shorts")

      case @expected do
        :playable ->
          Enum.each(videos, &assert_playable(view, &1))

        {:locked, href} ->
          Enum.each(videos, &assert_locked(view, &1, href))
          refute html =~ "image.mux.com"
          refute render(view) =~ "image.mux.com"
      end
    end
  end

  describe "locked clips after load_more" do
    test "the next page leaks no playback ids or Mux image URLs" do
      org = shorts_org("subscribers_only")
      videos = seed_feed(org, 10)

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")
      render_hook(view, "load_more", %{})

      html = render(view)
      refute html =~ "image.mux.com"

      for video <- videos do
        assert has_element?(view, article(video))
        refute html =~ video.mux_playback_id
        assert has_element?(view, ~s([data-test="short-locked-#{video.id}"]))
      end
    end
  end

  describe "locked poster" do
    test "uses the operator's portrait thumbnail when one exists" do
      org = shorts_org("subscribers_only")

      [video] =
        seed_feed(org, 1, portrait_thumbnail_url: "https://cdn.example.com/posters/tall.jpg")

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")

      assert view |> element(article(video)) |> render() =~
               "https://cdn.example.com/posters/tall.jpg"

      assert has_element?(view, ~s(#{article(video)} img[alt]))
    end
  end

  describe "locked poster never falls back to a Mux URL" do
    # Operators, starter content and the subscriber-demo catalog often store a
    # Mux-hosted portrait thumbnail. For a locked clip that URL is a bearer
    # link to the playback id, so the branded placeholder must render instead.
    defp mux_poster_attrs(:image, pb),
      do: [
        mux_playback_id: pb,
        portrait_thumbnail_url: "https://image.mux.com/#{pb}/thumbnail.webp?width=720"
      ]

    defp mux_poster_attrs(:stream, pb),
      do: [mux_playback_id: pb, portrait_thumbnail_url: "https://stream.mux.com/#{pb}/low.mp4"]

    defp insert_locked_mux_poster_clip(org, kind) do
      pb = "pbmuxposter#{kind}x#{System.unique_integer([:positive])}"

      video =
        insert(
          :video,
          [organization: org, title: "Mux Poster #{kind}", mux_status: "ready", duration: 20.0] ++
            mux_poster_attrs(kind, pb)
        )

      {:ok, _} = Content.add_short_feed_video(owner_scope(org), video)
      video
    end

    defp assert_no_mux_leak(view, video) do
      html = render(view)
      refute html =~ "image.mux.com"
      refute html =~ "stream.mux.com"
      refute html =~ video.mux_playback_id
      assert has_element?(view, ~s([data-test="short-locked-#{video.id}"]))
      assert has_element?(view, ~s(#{article(video)} [data-short-placeholder]))
      refute has_element?(view, ~s(#{article(video)} img[data-short-poster]))
    end

    for kind <- [:image, :stream] do
      @kind kind

      test "initial render uses the placeholder for a #{kind}.mux.com thumbnail" do
        org = shorts_org("subscribers_only")
        video = insert_locked_mux_poster_clip(org, @kind)

        {:ok, view, html} = live(anon_conn(org), ~p"/shorts")

        refute html =~ video.mux_playback_id
        assert_no_mux_leak(view, video)
      end

      test "a #{kind}.mux.com thumbnail on page two does not leak after load_more" do
        org = shorts_org("subscribers_only")
        seed_feed(org, 8)
        video = insert_locked_mux_poster_clip(org, @kind)

        {:ok, view, html} = live(anon_conn(org), ~p"/shorts")
        refute has_element?(view, article(video))
        refute html =~ video.mux_playback_id

        render_hook(view, "load_more", %{})

        assert has_element?(view, article(video))
        assert_no_mux_leak(view, video)
      end

      test "a #{kind}.mux.com thumbnail does not leak after a favorite re-render" do
        org = shorts_org("subscribers_only")
        [neighbour] = seed_feed(org, 1)
        video = insert_locked_mux_poster_clip(org, @kind)
        viewer = insert(:viewer, organization: org, subscription_status: "none")

        {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/shorts")
        assert_no_mux_leak(view, video)

        render_click(view, "toggle_favorite", %{"video-id" => video.id})
        assert_no_mux_leak(view, video)

        render_click(view, "toggle_favorite", %{"video-id" => neighbour.id})
        assert_no_mux_leak(view, video)
      end
    end
  end

  describe "feed level overrides per-video visibility" do
    test "a subscribers-only video plays in a public feed for a signed-out visitor" do
      org = shorts_org("public")
      [video] = seed_feed(org, 1, visibility: "subscribers_only")

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")
      assert_playable(view, video)
    end

    test "a public video is locked in a subscribers-only feed for a signed-out visitor" do
      org = shorts_org("subscribers_only")
      [video] = seed_feed(org, 1, visibility: "public")

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")
      assert_locked(view, video, "/login")
    end
  end

  describe "subscriber demo viewer" do
    test "sees only the organization's demo clips, never others shown locked" do
      org = shorts_org("subscribers_only")
      [demo_clip, other_clip] = seed_feed(org, 2)

      org =
        org
        |> Ecto.Changeset.change(
          features: %{"subscriber_demo" => true, "subscriber_demo_video_ids" => [demo_clip.id]}
        )
        |> Repo.update!()

      expires = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_iso8601()

      viewer =
        insert(:subscribed_viewer,
          organization: org,
          metadata: %{"subscriber_demo" => true, "subscriber_demo_expires_at" => expires}
        )

      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/shorts")

      assert_playable(view, demo_clip)
      refute has_element?(view, article(other_clip))
      refute html =~ other_clip.mux_playback_id
      refute html =~ other_clip.title
      assert has_element?(view, ~s(#{article(demo_clip)}[aria-setsize="1"]))
    end
  end

  describe "member preview" do
    test "an admin previewing as a member sees playable clips" do
      org = shorts_org("subscribers_only")
      [video] = seed_feed(org, 1)
      user = insert(:user)
      insert(:membership, organization: org, user: user, role: :admin)

      conn = build_conn() |> log_in_user(user) |> get("/?org=#{org.slug}&preview=member")
      {:ok, view, _} = live(recycle(conn), "/shorts")

      assert has_element?(view, "[data-test=impersonation-banner]", "Member preview")
      assert_playable(view, video)
    end
  end
end
