defmodule MarqueeWeb.Viewer.ShortsLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Accounts.Scope
  alias Marquee.{Content, Engagement, Repo}

  defp shorts_org(attrs \\ []) do
    insert(
      :organization,
      Keyword.merge([shorts_feed_enabled: true, shorts_feed_access: "public"], attrs)
    )
  end

  defp editor_scope(org) do
    membership =
      insert(:membership, organization: org, user: insert(:user), role: :editor)
      |> Repo.preload([:user, :organization])

    Scope.for_user(membership.user) |> Scope.with_organization(org, membership)
  end

  defp seed_feed(org, count, attrs \\ []) do
    scope = editor_scope(org)

    for n <- 1..count do
      video =
        insert(
          :video,
          Keyword.merge(
            [
              organization: org,
              title: "Short #{n}",
              mux_status: "ready",
              mux_playback_id: "pb-short-#{n}-#{System.unique_integer([:positive])}",
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

  defp article(video), do: ~s(article[data-video-id="#{video.id}"])

  defp article_count(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#shorts-feed article")
    |> Enum.count()
  end

  defp attr_of(view, selector, name) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute(name)
  end

  describe "feed availability and navigation" do
    test "a disabled feed redirects to home with a flash" do
      org = shorts_org(shorts_feed_enabled: false)
      seed_feed(org, 1)

      assert {:error, {kind, %{to: "/"} = redirect}} = live(anon_conn(org), ~p"/shorts")
      assert kind in [:redirect, :live_redirect]
      assert map_size(Map.get(redirect, :flash, %{})) > 0
    end

    test "with no resolved organization (platform host) it redirects to home" do
      # Plain localhost with no subdomain, ?org param or session org.
      conn = build_conn() |> Map.put(:host, "localhost") |> init_test_session(%{})

      assert {:error, {kind, %{to: "/"}}} = live(conn, ~p"/shorts")
      assert kind in [:redirect, :live_redirect]
    end

    test "the Shorts nav item is hidden while the feed is disabled" do
      org = shorts_org(shorts_feed_enabled: false)
      viewer = insert(:subscribed_viewer, organization: org)

      {:ok, home, _} = live(conn_for_viewer(viewer), ~p"/")
      refute has_element?(home, ~s([data-test="nav-shorts"]))

      {:ok, browse, _} = live(anon_conn(org), ~p"/browse")
      refute has_element?(browse, ~s([data-test="nav-shorts"]))
    end

    test "the Shorts nav item is shown while the feed is enabled" do
      org = shorts_org()
      viewer = insert(:subscribed_viewer, organization: org)

      {:ok, home, _} = live(conn_for_viewer(viewer), ~p"/")
      assert has_element?(home, ~s([data-test="nav-shorts"][href="/shorts"]), "Shorts")

      {:ok, browse, _} = live(anon_conn(org), ~p"/browse")
      assert has_element?(browse, ~s([data-test="nav-shorts"]))
    end

    test "the Shorts nav item is marked current on /shorts" do
      org = shorts_org()
      seed_feed(org, 1)

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")
      assert has_element?(view, ~s([data-test="nav-shorts"][aria-current="page"]))
    end
  end

  describe "empty feed" do
    test "shows an empty state and no clips" do
      org = shorts_org()

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")

      assert has_element?(view, ~s([data-test="shorts-empty"]))
      assert article_count(view) == 0
    end
  end

  describe "first page" do
    test "renders the feed container with feed semantics" do
      org = shorts_org()
      seed_feed(org, 3)

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")

      assert has_element?(view, ~s(#shorts-feed[role="feed"][phx-hook="ShortsFeed"][aria-label]))
      assert has_element?(view, ~s(#shorts-feed[aria-busy]))
      assert has_element?(view, ~s(#shorts-feed[data-has-more="false"]))
      refute has_element?(view, ~s([data-test="shorts-empty"]))
    end

    test "each clip is a labelled article positioned within the feed" do
      org = shorts_org()
      videos = seed_feed(org, 3)

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")

      for {video, index} <- Enum.with_index(videos, 1) do
        assert has_element?(
                 view,
                 ~s(#{article(video)}[aria-posinset="#{index}"][aria-setsize="3"])
               )

        assert has_element?(view, ~s(#{article(video)}[data-index]))
        [label_id] = attr_of(view, article(video), "aria-labelledby")
        assert has_element?(view, ~s([id="#{label_id}"]), video.title)
      end
    end

    test "playable clips carry the playback id and a Mux poster without smartcrop" do
      org = shorts_org()
      [video] = seed_feed(org, 1)

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")

      assert has_element?(
               view,
               ~s(#{article(video)}[data-playback-id="#{video.mux_playback_id}"])
             )

      assert has_element?(view, ~s(#{article(video)} img[alt]))
      article_html = view |> element(article(video)) |> render()
      assert article_html =~ "image.mux.com/#{video.mux_playback_id}"
      refute article_html =~ "smartcrop"
    end

    test "server renders the DOM the ShortsFeed hook drives for each playable clip" do
      org = shorts_org()
      videos = seed_feed(org, 2)

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")

      for v <- videos do
        a = article(v)
        assert has_element?(view, ~s(#{a}[tabindex="-1"]))

        assert has_element?(
                 view,
                 ~s(#{a} button[data-shorts-toggle-play][aria-pressed][aria-label])
               )

        assert has_element?(
                 view,
                 ~s(#{a} button[data-shorts-toggle-mute][aria-pressed][aria-label])
               )

        assert has_element?(view, ~s(#{a} [data-player-slot][phx-update="ignore"][id]))

        assert has_element?(
                 view,
                 ~s(#{a} [data-test="short-error-#{v.id}"][hidden] button[data-shorts-retry])
               )
      end
    end

    test "page-level controls and states live outside the feed" do
      org = shorts_org()
      seed_feed(org, 2)

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")

      assert has_element?(view, ~s(button[data-test="shorts-tap-to-play"][hidden]))
      refute has_element?(view, ~s(#shorts-feed [data-test="shorts-tap-to-play"]))

      assert has_element?(view, ~s([data-test="shorts-loading"][aria-live="polite"]))
      refute has_element?(view, ~s(#shorts-feed [data-test="shorts-loading"]))

      assert has_element?(view, ~s(button[data-shorts-prev][aria-label]))
      assert has_element?(view, ~s(button[data-shorts-next][aria-label]))
      refute has_element?(view, ~s(#shorts-feed [data-shorts-prev]))
      refute has_element?(view, ~s(#shorts-feed [data-shorts-next]))
    end

    test "provides a polite clip announcer outside the feed" do
      org = shorts_org()
      seed_feed(org, 1)

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")
      assert has_element?(view, ~s([data-shorts-live][aria-live="polite"]))
      refute has_element?(view, ~s(#shorts-feed [data-shorts-live]))
    end

    test "never shows another organization's clips" do
      org = shorts_org()
      [mine] = seed_feed(org, 1)
      other = shorts_org()
      [theirs] = seed_feed(other, 1, title: "Rival Short")

      {:ok, view, html} = live(anon_conn(org), ~p"/shorts")

      assert has_element?(view, article(mine))
      refute has_element?(view, article(theirs))
      refute html =~ "Rival Short"
      refute html =~ theirs.mux_playback_id
    end

    test "ineligible feed items are not shown" do
      org = shorts_org()
      [good, broken] = seed_feed(org, 2)
      {:ok, _} = Content.mark_video_errored(broken.mux_asset_id, %{})

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")

      assert has_element?(view, article(good))
      refute has_element?(view, article(broken))
    end
  end

  describe "load_more" do
    test "appends the next page and then reaches the end state" do
      org = shorts_org()
      videos = seed_feed(org, 10)

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")

      assert article_count(view) == 8
      assert has_element?(view, ~s(#shorts-feed[data-has-more="true"]))
      refute has_element?(view, ~s([data-test="shorts-end"]))

      render_hook(view, "load_more", %{})

      assert article_count(view) == 10
      assert has_element?(view, ~s(#shorts-feed[data-has-more="false"]))
      assert has_element?(view, ~s([data-test="shorts-end"]))

      for {video, index} <- Enum.with_index(videos, 1) do
        assert has_element?(
                 view,
                 ~s(#{article(video)}[aria-posinset="#{index}"][aria-setsize="10"])
               )
      end
    end

    test "is ignored once there is nothing more to load" do
      org = shorts_org()
      seed_feed(org, 3)

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")
      render_hook(view, "load_more", %{})
      render_hook(view, "load_more", %{})

      assert article_count(view) == 3
      assert has_element?(view, ~s([data-test="shorts-end"]))
    end
  end

  describe "aspect ratio" do
    test "portrait, landscape and unknown clips expose orientation and their own ratio" do
      org = shorts_org()
      scope = editor_scope(org)

      [tall, wide, unknown] =
        for ratio <- ["9:16", "16:9", nil] do
          video = insert(:video, organization: org, mux_status: "ready", aspect_ratio: ratio)
          {:ok, _} = Content.add_short_feed_video(scope, video)
          video
        end

      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")

      assert has_element?(view, ~s(#{article(tall)}[data-orientation="portrait"]))
      assert has_element?(view, ~s(#{article(wide)}[data-orientation="landscape"]))
      assert has_element?(view, ~s(#{article(unknown)}[data-orientation="unknown"]))

      assert view |> element(article(tall)) |> render() =~ ~r{aspect-ratio:\s*9 / 16}
      assert view |> element(article(wide)) |> render() =~ ~r{aspect-ratio:\s*16 / 9}
      assert view |> element(article(unknown)) |> render() =~ ~r{aspect-ratio:\s*9 / 16}

      for video <- [tall, wide, unknown] do
        refute view |> element(article(video)) |> render() =~ "smartcrop"
      end
    end
  end

  describe "favorite and watchlist" do
    setup do
      org = shorts_org()
      [video] = seed_feed(org, 1)
      viewer = insert(:subscribed_viewer, organization: org)
      %{org: org, video: video, viewer: viewer}
    end

    test "favorite toggles aria-pressed and persists", %{org: org, video: video, viewer: viewer} do
      {:ok, view, _} = live(conn_for_viewer(viewer), ~p"/shorts")
      button = ~s([data-test="short-favorite-#{video.id}"])

      assert has_element?(view, ~s(button#{button}[aria-pressed="false"][aria-label]))

      view |> element(button) |> render_click()
      assert has_element?(view, ~s(#{button}[aria-pressed="true"]))
      assert Engagement.favorited?(org, viewer, video)

      view |> element(button) |> render_click()
      assert has_element?(view, ~s(#{button}[aria-pressed="false"]))
      refute Engagement.favorited?(org, viewer, video)
    end

    test "watchlist toggles aria-pressed and persists", %{org: org, video: video, viewer: viewer} do
      {:ok, view, _} = live(conn_for_viewer(viewer), ~p"/shorts")
      button = ~s([data-test="short-watchlist-#{video.id}"])

      assert has_element?(view, ~s(button#{button}[aria-pressed="false"][aria-label]))

      view |> element(button) |> render_click()
      assert has_element?(view, ~s(#{button}[aria-pressed="true"]))
      assert Engagement.in_watchlist?(org, viewer, video)

      view |> element(button) |> render_click()
      assert has_element?(view, ~s(#{button}[aria-pressed="false"]))
      refute Engagement.in_watchlist?(org, viewer, video)
    end

    test "initial pressed state reflects saved activity", %{
      org: org,
      video: video,
      viewer: viewer
    } do
      {:ok, _, :added} = Engagement.toggle_favorite(org, viewer, video)
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, video)

      {:ok, view, _} = live(conn_for_viewer(viewer), ~p"/shorts")

      assert has_element?(view, ~s([data-test="short-favorite-#{video.id}"][aria-pressed="true"]))

      assert has_element?(
               view,
               ~s([data-test="short-watchlist-#{video.id}"][aria-pressed="true"])
             )
    end

    test "a signed-out visitor is sent to /login", %{org: org, video: video} do
      {:ok, view, _} = live(anon_conn(org), ~p"/shorts")

      for kind <- ["favorite", "watchlist"] do
        selector = ~s([data-test="short-#{kind}-#{video.id}"])

        if has_element?(view, ~s(a#{selector}[href="/login"])) do
          :ok
        else
          assert {:error, {redirect_kind, %{to: "/login"}}} =
                   view |> element(selector) |> render_click()

          assert redirect_kind in [:redirect, :live_redirect]
        end
      end
    end

    test "cannot favorite another organization's video by forging the id", %{
      org: org,
      viewer: viewer
    } do
      other = shorts_org()
      [foreign] = seed_feed(other, 1)

      {:ok, view, _} = live(conn_for_viewer(viewer), ~p"/shorts")
      render_click(view, "toggle_favorite", %{"video-id" => foreign.id})

      refute Engagement.favorited?(other, viewer, foreign)
      refute Engagement.favorited?(org, viewer, foreign)
    end
  end
end
