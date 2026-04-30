defmodule BobineWeb.Viewer.PodcastsLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /podcasts" do
    test "renders podcast grid when shows exist", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:podcast_show, organization: org, title: "The Deep Dive", published: true)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/podcasts")
      assert html =~ "Podcasts"
      assert html =~ ~s(data-test="sv-podcast-grid")
      assert html =~ "The Deep Dive"
    end

    test "renders empty state when no published shows", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/podcasts")
      assert html =~ ~s(data-test="sv-empty-state")
      assert html =~ "No podcasts yet"
    end

    test "does not show unpublished shows", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:podcast_show, organization: org, title: "Hidden Show", published: false)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/podcasts")
      refute html =~ "Hidden Show"
    end

    test "each show card links to show detail page", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      show = insert(:podcast_show, organization: org, slug: "my-show", published: true)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/podcasts")
      assert html =~ ~s(/podcasts/#{show.slug})
    end

    test "accessible without login", %{conn: _conn} do
      org = insert(:organization)
      insert(:podcast_show, organization: org, title: "Public Show", published: true)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, _view, html} = live(conn, ~p"/podcasts")
      assert html =~ "Public Show"
    end
  end
end
