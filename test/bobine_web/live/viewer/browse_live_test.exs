defmodule BobineWeb.Viewer.BrowseLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /browse" do
    test "renders browse page with grid", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:video, organization: org, title: "Browse Video", mux_status: "ready")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse")
      assert html =~ "Browse"
      assert html =~ ~s(data-test="sv-browse-grid")
      assert html =~ "Browse Video"
    end

    test "renders search input", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse")
      assert html =~ ~s(data-test="sv-search-input")
    end

    test "renders sort selector", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse")
      assert html =~ ~s(data-test="sv-filter-sort")
    end

    test "shows empty state when no videos", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse")
      assert html =~ ~s(data-test="sv-empty-state")
      assert html =~ "No videos found"
    end

    test "search filters videos by title", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:video, organization: org, title: "Alpha Video", mux_status: "ready")
      insert(:video, organization: org, title: "Beta Movie", mux_status: "ready")

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/browse")

      html = render_change(view, "filter", %{"search" => "Alpha", "sort" => "newest"})
      assert html =~ "Alpha Video"
      refute html =~ "Beta Movie"
    end

    test "sort changes order", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:video, organization: org, title: "Zebra", mux_status: "ready")
      insert(:video, organization: org, title: "Aardvark", mux_status: "ready")

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/browse")

      html = render_change(view, "filter", %{"search" => "", "sort" => "alphabetical"})
      aardvark_pos = :binary.match(html, "Aardvark") |> elem(0)
      zebra_pos = :binary.match(html, "Zebra") |> elem(0)
      assert aardvark_pos < zebra_pos
    end

    test "does not show videos from other org", %{conn: _conn} do
      org = insert(:organization)
      other_org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      insert(:video, organization: org, title: "Our Video", mux_status: "ready")
      insert(:video, organization: other_org, title: "Other Video", mux_status: "ready")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse")
      assert html =~ "Our Video"
      refute html =~ "Other Video"
    end
  end

  describe "GET /browse?tag=TAG_ID" do
    test "pre-filters videos by tag from query param", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      tag = insert(:tag, organization: org, name: "horror")

      tagged_video = insert(:video, organization: org, title: "Scary Movie", mux_status: "ready")
      insert(:video_tag, organization: org, video: tagged_video, tag: tag)

      insert(:video, organization: org, title: "Comedy Show", mux_status: "ready")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse?#{[tag: tag.id]}")
      assert html =~ "Scary Movie"
      refute html =~ "Comedy Show"
    end

    test "tag filter select reflects the active tag", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      tag = insert(:tag, organization: org, name: "action")

      video = insert(:video, organization: org, title: "Action Film", mux_status: "ready")
      insert(:video_tag, organization: org, video: video, tag: tag)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/browse?#{[tag: tag.id]}")
      assert html =~ ~s(selected)
    end
  end

  describe "filter event with tag" do
    test "selecting a tag filters videos", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      tag = insert(:tag, organization: org, name: "drama")

      tagged = insert(:video, organization: org, title: "Drama Film", mux_status: "ready")
      insert(:video_tag, organization: org, video: tagged, tag: tag)

      insert(:video, organization: org, title: "Other Film", mux_status: "ready")

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/browse")

      html =
        render_change(view, "filter", %{
          "search" => "",
          "sort" => "newest",
          "tag" => tag.id
        })

      assert html =~ "Drama Film"
      refute html =~ "Other Film"
    end

    test "clearing tag filter shows all videos", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      tag = insert(:tag, organization: org, name: "scifi")

      tagged = insert(:video, organization: org, title: "Space Movie", mux_status: "ready")
      insert(:video_tag, organization: org, video: tagged, tag: tag)

      insert(:video, organization: org, title: "Earth Movie", mux_status: "ready")

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/browse?#{[tag: tag.id]}")

      html =
        render_change(view, "filter", %{
          "search" => "",
          "sort" => "newest",
          "tag" => ""
        })

      assert html =~ "Space Movie"
      assert html =~ "Earth Movie"
    end
  end
end
