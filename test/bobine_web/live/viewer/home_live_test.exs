defmodule BobineWeb.Viewer.HomeLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET / with org resolved" do
    test "renders org name", %{conn: _conn} do
      org = insert(:organization, name: "My Studio")
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      {:ok, _view, html} = live(conn_for(membership), ~p"/")
      assert html =~ "My Studio"
    end

    test "renders row titles on the homepage", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      video = insert(:video, organization: org, mux_status: "ready")

      row =
        insert(:row,
          organization: org,
          title: "Featured Films",
          source_type: :curated,
          visible: true,
          position: 0
        )

      insert(:row_item, organization: org, row: row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for(membership), ~p"/")
      assert html =~ "Featured Films"
    end

    test "renders multiple row titles in order", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      # Insert a video so :recent rows have content
      insert(:video, organization: org, mux_status: "ready")

      insert(:row,
        organization: org,
        title: "New Releases",
        source_type: :recent,
        visible: true,
        position: 0
      )

      insert(:row,
        organization: org,
        title: "Staff Picks",
        source_type: :recent,
        visible: true,
        position: 1
      )

      {:ok, _view, html} = live(conn_for(membership), ~p"/")
      assert html =~ "New Releases"
      assert html =~ "Staff Picks"
    end

    test "does not render hidden rows", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      # Insert a video so :recent rows have content
      insert(:video, organization: org, mux_status: "ready")

      insert(:row,
        organization: org,
        title: "Visible Row",
        source_type: :recent,
        visible: true,
        position: 0
      )

      insert(:row,
        organization: org,
        title: "Hidden Row",
        source_type: :recent,
        visible: false,
        position: 1
      )

      {:ok, _view, html} = live(conn_for(membership), ~p"/")
      assert html =~ "Visible Row"
      refute html =~ "Hidden Row"
    end

    test "lists ready videos within a row", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      video =
        insert(:video,
          organization: org,
          title: "Featured Video",
          mux_status: "ready",
          mux_playback_id: "pb_123"
        )

      row =
        insert(:row,
          organization: org,
          title: "Curated",
          source_type: :curated,
          visible: true,
          position: 0
        )

      insert(:row_item, organization: org, row: row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for(membership), ~p"/")
      assert html =~ "Featured Video"
      assert html =~ ~p"/watch/#{video.id}"
    end

    test "does not show videos from other orgs", %{conn: _conn} do
      org = insert(:organization)
      other_org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      insert(:video, organization: other_org, title: "Other Org Video", mux_status: "ready")

      insert(:row,
        organization: org,
        title: "Our Videos",
        source_type: :recent,
        visible: true,
        position: 0
      )

      {:ok, _view, html} = live(conn_for(membership), ~p"/")
      refute html =~ "Other Org Video"
    end

    test "shows empty state when no rows exist", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      {:ok, _view, html} = live(conn_for(membership), ~p"/")
      assert html =~ "No videos available"
    end
  end

  describe "GET / as a viewer" do
    test "renders row titles on the homepage", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      # Insert a video so :recent row has content
      insert(:video, organization: org, mux_status: "ready")

      insert(:row,
        organization: org,
        title: "Trending Now",
        source_type: :recent,
        visible: true,
        position: 0
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "Trending Now"
    end

    test "renders videos within rows", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, title: "My Movie", mux_status: "ready")

      row =
        insert(:row,
          organization: org,
          title: "Curated Picks",
          source_type: :curated,
          visible: true,
          position: 0
        )

      insert(:row_item, organization: org, row: row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "Curated Picks"
      assert html =~ "My Movie"
    end

    test "does not render hidden rows", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      # Insert a video so :recent row has content
      insert(:video, organization: org, mux_status: "ready")

      insert(:row,
        organization: org,
        title: "Public Row",
        source_type: :recent,
        visible: true,
        position: 0
      )

      insert(:row,
        organization: org,
        title: "Secret Row",
        source_type: :recent,
        visible: false,
        position: 1
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "Public Row"
      refute html =~ "Secret Row"
    end

    test "shows empty state when no rows exist", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "No videos available"
    end
  end

  describe "GET / super admin redirect" do
    test "super admin with no org resolved is redirected to /super", %{conn: conn} do
      super_admin = insert(:super_admin)
      conn = log_in_user(conn, super_admin)

      # Visit / without org resolution (no subdomain, no ?org param)
      assert {:error, {:live_redirect, %{to: "/super"}}} = live(conn, ~p"/")
    end
  end

  describe "homepage layout and data-test attributes" do
    test "viewer layout is rendered", %{conn: _conn} do
      org = insert(:organization, name: "Test Platform")
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="viewer-layout")
      assert html =~ ~s(data-test="viewer-header")
    end

    test "navigation shows correct items", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="viewer-nav")
      assert html =~ ~s(data-test="nav-home")
      assert html =~ ~s(data-test="nav-browse")
      assert html =~ ~s(data-test="nav-collections")
    end

    test "profile avatar visible when logged in", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, display_name: "Jane")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="profile-avatar")
      refute html =~ ~s(data-test="sign-in-link")
    end

    test "sign in link visible when not logged in", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      {:ok, _view, html} = live(conn_for(membership), ~p"/")
      assert html =~ ~s(data-test="sign-in-link")
      refute html =~ ~s(data-test="profile-avatar")
    end

    test "org name appears in the header brand", %{conn: _conn} do
      org = insert(:organization, name: "StreamCo")
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "StreamCo"
      assert html =~ ~s(data-test="viewer-brand-logo")
    end
  end

  describe "hero carousel" do
    test "hero carousel section is present when videos exist", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:video, organization: org, title: "Hero Vid", mux_status: "ready")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="hero-carousel")
    end

    test "hero slide elements match the number of hero items", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      for i <- 1..3 do
        insert(:video, organization: org, title: "Video #{i}", mux_status: "ready")
      end

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="hero-slide-0")
      assert html =~ ~s(data-test="hero-slide-1")
      assert html =~ ~s(data-test="hero-slide-2")
    end

    test "hero has pagination dots", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:video, organization: org, mux_status: "ready")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="hero-pagination")
      assert html =~ ~s(data-test="hero-dot-0")
    end

    test "hero has primary CTA", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:video, organization: org, mux_status: "ready")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="hero-primary-cta-0")
      assert html =~ "Watch Now"
    end
  end

  describe "catalog rows" do
    test "catalog rows section is present", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, mux_status: "ready")

      row =
        insert(:row,
          organization: org,
          title: "Test Row",
          source_type: :curated,
          visible: true,
          position: 0
        )

      insert(:row_item, organization: org, row: row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="catalog-rows")
    end

    test "rows with no content are not rendered", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      insert(:row,
        organization: org,
        title: "Empty Row",
        source_type: :curated,
        visible: true,
        position: 0
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      refute html =~ "Empty Row"
    end

    test "content cards have correct links to /watch/:id", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, title: "Linked Video", mux_status: "ready")

      row =
        insert(:row,
          organization: org,
          title: "Watch Row",
          source_type: :curated,
          visible: true,
          position: 0
        )

      insert(:row_item, organization: org, row: row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="content-card-#{video.id}")
      assert html =~ "/watch/#{video.id}"
    end

    test "content row has data-test with row id", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, mux_status: "ready")

      row =
        insert(:row,
          organization: org,
          title: "ID Row",
          source_type: :curated,
          visible: true,
          position: 0
        )

      insert(:row_item, organization: org, row: row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="content-row-#{row.id}")
    end
  end

  describe "multi-tenant isolation" do
    test "homepage shows only the current org's content", %{conn: _conn} do
      org = insert(:organization)
      other_org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      insert(:video, organization: org, title: "Org Video", mux_status: "ready")
      insert(:video, organization: other_org, title: "Other Video", mux_status: "ready")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      refute html =~ "Other Video"
    end
  end

  describe "unauthenticated visitor" do
    test "homepage renders for unauthenticated visitor", %{conn: _conn} do
      org = insert(:organization, name: "Public Platform")
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      {:ok, _view, html} = live(conn_for(membership), ~p"/")
      assert html =~ "Public Platform"
      assert html =~ ~s(data-test="viewer-layout")
    end
  end
end
