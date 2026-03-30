defmodule BobineWeb.Admin.ContentLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "responsive layout" do
    test "mobile sidebar toggle elements are present", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")

      # Mobile header with hamburger button exists
      assert html =~ ~s(data-test="org-name-mobile")
      assert html =~ "hero-bars-3"

      # Sidebar with nav links exists
      assert html =~ ~s(id="admin-sidebar")
      assert html =~ ~s(id="admin-overlay")
      assert html =~ ~s(data-test="admin-nav-content")
    end

    test "sidebar open uses JS.remove_class not checkbox peer", %{conn: _conn} do
      # Regression: the CSS-only peer-checked approach broke under LiveView
      # DOM patching. The fix uses phx-click with JS commands instead.
      membership = insert(:membership, role: :editor)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")

      # Must NOT have a checkbox-based drawer (the broken approach)
      refute html =~ ~s(id="admin-drawer")
      # Must use phx-click JS commands on the hamburger button
      assert html =~ "phx-click"
    end
  end

  describe "access control" do
    test "admin can access content page", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ "Content"
    end

    test "editor can access content page", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ "Content"
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/content")
      assert path == ~p"/users/log-in"
    end
  end

  describe "video list" do
    test "renders video list for the organization", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      video = insert(:video, organization: org, title: "Test Video", mux_status: "ready")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ "Test Video"
      assert html =~ ~s(data-test="video-row-#{video.id}")
    end

    test "shows empty state when no videos exist", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ ~s(data-test="empty-state")
      assert html =~ "No videos yet"
    end

    test "videos from other organizations are not visible", %{conn: _conn} do
      org = insert(:organization)
      other_org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      insert(:video, organization: other_org, title: "Other Org Video")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      refute html =~ "Other Org Video"
    end

    test "upload button is visible for editors", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ ~s(data-test="upload-btn")
    end

    test "delete button soft-deletes the video", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      video = insert(:video, organization: org, title: "To Delete")

      # The MuxAssetCleanup job runs inline and calls delete_asset
      Mox.stub(Bobine.Content.MockMuxClient, :delete_asset, fn _asset_id -> :ok end)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")

      html =
        view
        |> element(~s([data-test="delete-video-#{video.id}"]))
        |> render_click()

      refute html =~ "To Delete"
    end

    test "upload_error event is handled without crashing the LiveView", %{conn: _conn} do
      # This tests the fix for the bug where the modal closed before the
      # MuxUploader hook could read the file, causing "No file selected" error.
      # The LiveView must handle this gracefully — not crash.
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")

      # Simulate the MuxUploader hook reporting an error via pushEvent
      # The LiveView should handle this without crashing
      assert render_hook(view, "upload_error", %{
               "video_id" => Ecto.UUID.generate(),
               "error" => "No file selected"
             })

      # The LiveView should still be alive and rendering
      assert render(view) =~ "Content"
    end

    test "upload_complete event closes modal", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")

      # Open modal first
      render_click(view, "open_upload")
      assert render(view) =~ ~s(data-test="upload-modal")

      # Simulate upload completion
      render_hook(view, "upload_complete", %{
        "video_id" => Ecto.UUID.generate()
      })

      # Modal should be closed after upload completes
      refute render(view) =~ ~s(data-test="upload-modal")
    end

    test "search filters video list by title", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      insert(:video, organization: org, title: "Alpha Video")
      insert(:video, organization: org, title: "Beta Film")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")

      html = render_change(view, "search", %{"search" => "Alpha"})
      assert html =~ "Alpha Video"
      refute html =~ "Beta Film"
    end

    test "video title links to watch page for ready videos", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      video = insert(:video, organization: org, title: "Watchable", mux_status: "ready")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ ~p"/watch/#{video.id}"
    end
  end

  describe "RBAC on content management" do
    test "viewer_support can view content list", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :viewer_support)

      insert(:video, organization: org, title: "Visible Video")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ "Visible Video"
    end

    test "viewer_support cannot see upload button", %{conn: _conn} do
      # viewer_support should have read-only access — no upload capability
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :viewer_support)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      refute html =~ ~s(data-test="upload-btn")
    end

    test "viewer_support cannot see delete button", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :viewer_support)
      video = insert(:video, organization: org, title: "Protected Video")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      refute html =~ ~s(data-test="delete-video-#{video.id}")
    end
  end
end
