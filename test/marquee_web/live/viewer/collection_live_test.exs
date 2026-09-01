defmodule MarqueeWeb.Viewer.CollectionLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /collections/:slug" do
    test "renders collection title and description", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      collection =
        insert(:collection,
          organization: org,
          title: "Sci-Fi Classics",
          description: "The best of science fiction",
          slug: "sci-fi-classics"
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/collections/#{collection.slug}")
      assert html =~ "Sci-Fi Classics"
      assert html =~ "The best of science fiction"
      assert html =~ ~s(data-test="sv-collection-title")
    end

    test "shows videos in the collection ordered by position", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      collection = insert(:collection, organization: org, slug: "action")

      video1 =
        insert(:video, organization: org, title: "First Video", mux_status: "ready")

      video2 =
        insert(:video, organization: org, title: "Second Video", mux_status: "ready")

      insert(:collection_item,
        organization: org,
        collection: collection,
        video: video2,
        position: 1
      )

      insert(:collection_item,
        organization: org,
        collection: collection,
        video: video1,
        position: 0
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/collections/#{collection.slug}")
      assert html =~ "First Video"
      assert html =~ "Second Video"
    end

    test "non-existent collection slug redirects", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), ~p"/collections/does-not-exist")
    end

    test "shows play first button when videos exist", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      collection = insert(:collection, organization: org, slug: "plays")
      video = insert(:video, organization: org, mux_status: "ready")

      insert(:collection_item,
        organization: org,
        collection: collection,
        video: video,
        position: 0
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/collections/#{collection.slug}")
      assert html =~ ~s(data-test="sv-collection-play-first")
      assert html =~ "Play first"
    end

    test "shows empty state when no videos", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      collection = insert(:collection, organization: org, slug: "empty-col")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/collections/#{collection.slug}")
      assert html =~ ~s(data-test="sv-empty-state")
      assert html =~ "No videos in this collection"
    end
  end
end
