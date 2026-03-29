defmodule BobineWeb.Admin.ContentLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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
  end
end
