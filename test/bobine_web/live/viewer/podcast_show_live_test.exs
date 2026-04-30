defmodule BobineWeb.Viewer.PodcastShowLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /podcasts/:slug" do
    test "renders show title and episodes", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      show = insert(:podcast_show, organization: org, title: "Tech Talk", published: true)

      insert(:podcast_episode,
        show: show,
        organization: org,
        title: "Episode One",
        status: "published"
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/podcasts/#{show.slug}")
      assert html =~ "Tech Talk"
      assert html =~ "Episode One"
      assert html =~ ~s(data-test="sv-episode-list")
    end

    test "redirects to /podcasts when show not found", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      assert {:error, {:live_redirect, %{to: "/podcasts"}}} =
               live(conn_for_viewer(viewer), ~p"/podcasts/nonexistent")
    end

    test "shows subscribe prompt for viewer without access", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "none")
      show = insert(:podcast_show, organization: org, published: true, access_mode: "any_active")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/podcasts/#{show.slug}")
      assert html =~ ~s(data-test="sv-podcast-subscribe-prompt")
    end

    test "shows login prompt for unauthenticated user", %{conn: _conn} do
      org = insert(:organization)
      show = insert(:podcast_show, organization: org, published: true)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, _view, html} = live(conn, ~p"/podcasts/#{show.slug}")
      assert html =~ ~s(data-test="sv-podcast-login-prompt")
    end

    test "shows feed URL for viewer with access", %{conn: _conn} do
      org = insert(:organization)
      plan = insert(:plan, organization: org)
      viewer = insert(:viewer, organization: org, subscription_status: "active")

      _sub =
        insert(:viewer_subscription,
          organization: org,
          viewer: viewer,
          plan: plan,
          status: "active"
        )

      show = insert(:podcast_show, organization: org, published: true, access_mode: "any_active")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/podcasts/#{show.slug}")
      assert html =~ ~s(data-test="sv-podcast-feed-section")
      assert html =~ "feed.xml"
    end

    test "shows episode count", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      show = insert(:podcast_show, organization: org, published: true)
      insert(:podcast_episode, show: show, organization: org, status: "published")
      insert(:podcast_episode, show: show, organization: org, status: "published")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/podcasts/#{show.slug}")
      assert html =~ ~s(data-test="sv-episode-list-section")
    end

    test "empty state when no episodes", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      show = insert(:podcast_show, organization: org, published: true)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/podcasts/#{show.slug}")
      assert html =~ ~s(data-test="sv-empty-state")
      assert html =~ "No episodes yet"
    end

    test "back link to podcasts list", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      show = insert(:podcast_show, organization: org, published: true)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/podcasts/#{show.slug}")
      assert html =~ "/podcasts"
      assert html =~ "Podcasts"
    end
  end
end
