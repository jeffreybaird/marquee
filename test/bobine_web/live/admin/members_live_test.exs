defmodule BobineWeb.Admin.MembersLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "access control" do
    test "admin can access members page", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/members")
      assert html =~ "Members"
    end

    test "viewer_support can access members page", %{conn: _conn} do
      membership = insert(:membership, role: :viewer_support)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/members")
      assert html =~ "Members"
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/members")
      assert path == ~p"/users/log-in"
    end

    test "displays organization name", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")
      assert has_element?(view, "[data-test='org-name']", membership.organization.name)
    end
  end

  describe "viewer tab" do
    test "shows viewer accounts in the viewer list", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)

      _viewer =
        insert(:viewer, organization: org, email: "alice@example.com", display_name: "Alice")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/members")
      assert html =~ "alice@example.com"
      assert html =~ "Alice"
    end
  end

  describe "viewer management actions" do
    test "suspend viewer changes status", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)
      viewer = insert(:viewer, organization: org, status: :active)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")

      assert has_element?(view, "[data-test='suspend-viewer-#{viewer.id}']")
      render_click(view, "suspend_viewer", %{"id" => viewer.id})

      # Verify the viewer was suspended in the DB
      {:ok, updated} = Bobine.Viewers.get_viewer(org, viewer.id)
      assert updated.status == :suspended

      # Reactivate button should now be visible
      assert has_element?(view, "[data-test='reactivate-viewer-#{viewer.id}']")
    end

    test "ban viewer changes status", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)
      viewer = insert(:viewer, organization: org, status: :active)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")

      assert has_element?(view, "[data-test='ban-viewer-#{viewer.id}']")
      render_click(view, "ban_viewer", %{"id" => viewer.id})

      {:ok, updated} = Bobine.Viewers.get_viewer(org, viewer.id)
      assert updated.status == :banned
      assert has_element?(view, "[data-test='reactivate-viewer-#{viewer.id}']")
    end

    test "reactivate suspended viewer", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)
      viewer = insert(:viewer, organization: org, status: :suspended)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")

      assert has_element?(view, "[data-test='reactivate-viewer-#{viewer.id}']")
      render_click(view, "reactivate_viewer", %{"id" => viewer.id})

      {:ok, updated} = Bobine.Viewers.get_viewer(org, viewer.id)
      assert updated.status == :active
      assert has_element?(view, "[data-test='suspend-viewer-#{viewer.id}']")
    end

    test "grant access to unsubscribed viewer", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)
      viewer = insert(:viewer, organization: org, subscription_status: "none")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")

      assert has_element?(view, "[data-test='grant-access-#{viewer.id}']")
      render_click(view, "grant_access", %{"id" => viewer.id})

      {:ok, updated} = Bobine.Viewers.get_viewer(org, viewer.id)
      assert updated.subscription_status == "active"
      assert has_element?(view, "[data-test='revoke-access-#{viewer.id}']")
    end

    test "revoke access from subscribed viewer", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)
      viewer = insert(:subscribed_viewer, organization: org)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")

      assert has_element?(view, "[data-test='revoke-access-#{viewer.id}']")
      render_click(view, "revoke_access", %{"id" => viewer.id})

      {:ok, updated} = Bobine.Viewers.get_viewer(org, viewer.id)
      assert updated.subscription_status == "none"
      assert has_element?(view, "[data-test='grant-access-#{viewer.id}']")
    end
  end

  describe "viewer management role-based access" do
    test "viewer_support role can take viewer actions", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :viewer_support)
      viewer = insert(:viewer, organization: org, status: :active)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")

      assert has_element?(view, "[data-test='suspend-viewer-#{viewer.id}']")
      assert has_element?(view, "[data-test='ban-viewer-#{viewer.id}']")

      render_click(view, "suspend_viewer", %{"id" => viewer.id})

      {:ok, updated} = Bobine.Viewers.get_viewer(org, viewer.id)
      assert updated.status == :suspended
    end

    test "editor role can view viewers but not take actions", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :editor)
      viewer = insert(:viewer, organization: org, status: :active)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")

      # Editor can see the viewer list
      html = render(view)
      assert html =~ viewer.email

      # But should NOT see action buttons
      refute has_element?(view, "[data-test='suspend-viewer-#{viewer.id}']")
      refute has_element?(view, "[data-test='ban-viewer-#{viewer.id}']")
      refute has_element?(view, "[data-test='grant-access-#{viewer.id}']")
    end
  end
end
