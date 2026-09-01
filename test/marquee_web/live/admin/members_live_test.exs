defmodule MarqueeWeb.Admin.MembersLiveTest do
  use MarqueeWeb.ConnCase, async: true

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
      {:ok, updated} = Marquee.Viewers.get_viewer(org, viewer.id)
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

      {:ok, updated} = Marquee.Viewers.get_viewer(org, viewer.id)
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

      {:ok, updated} = Marquee.Viewers.get_viewer(org, viewer.id)
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

      {:ok, updated} = Marquee.Viewers.get_viewer(org, viewer.id)
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

      {:ok, updated} = Marquee.Viewers.get_viewer(org, viewer.id)
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

      {:ok, updated} = Marquee.Viewers.get_viewer(org, viewer.id)
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

    test "editor role cannot see impersonate button", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :editor)
      viewer = insert(:viewer, organization: org)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")
      refute has_element?(view, "[data-test='impersonate-viewer-#{viewer.id}']")
    end

    test "viewer_support role can see impersonate button", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :viewer_support)
      viewer = insert(:viewer, organization: org)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")
      assert has_element?(view, "[data-test='impersonate-viewer-#{viewer.id}']")
    end

    test "admin role can see impersonate button", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)
      viewer = insert(:viewer, organization: org)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")
      assert has_element?(view, "[data-test='impersonate-viewer-#{viewer.id}']")
    end
  end

  describe "search and filters" do
    test "search by display name", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)
      _v1 = insert(:viewer, organization: org, display_name: "Alice Smith", email: "a@test.com")
      _v2 = insert(:viewer, organization: org, display_name: "Bob Jones", email: "b@test.com")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")

      html = render_keyup(view, "search", %{"search" => "Alice"})
      assert html =~ "Alice Smith"
      refute html =~ "Bob Jones"
    end

    test "filter by status shows only matching viewers", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)
      _active = insert(:viewer, organization: org, email: "active@test.com", status: :active)

      _suspended =
        insert(:viewer, organization: org, email: "suspended@test.com", status: :suspended)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")

      html = render_change(view, "filter", %{"status" => "suspended", "subscription" => ""})
      assert html =~ "suspended@test.com"
      refute html =~ "active@test.com"
    end

    test "filter by subscription shows only matching viewers", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)

      _subscribed =
        insert(:viewer, organization: org, email: "sub@test.com", subscription_status: "active")

      _trial =
        insert(:viewer, organization: org, email: "trial@test.com", subscription_status: "trial")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")

      html = render_change(view, "filter", %{"status" => "", "subscription" => "trial"})
      assert html =~ "trial@test.com"
      refute html =~ "sub@test.com"
    end

    test "clearing filter shows all viewers", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)
      _active = insert(:viewer, organization: org, email: "active@test.com", status: :active)

      _suspended =
        insert(:viewer, organization: org, email: "suspended@test.com", status: :suspended)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")

      render_change(view, "filter", %{"status" => "suspended", "subscription" => ""})
      html = render_change(view, "filter", %{"status" => "", "subscription" => ""})
      assert html =~ "active@test.com"
      assert html =~ "suspended@test.com"
    end

    test "tenant isolation: other org viewers not shown", %{conn: _conn} do
      org = insert(:organization)
      other_org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)
      _own_viewer = insert(:viewer, organization: org, email: "own@test.com")
      _other_viewer = insert(:viewer, organization: other_org, email: "other@test.com")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/members")
      assert html =~ "own@test.com"
      refute html =~ "other@test.com"
    end
  end

  describe "pagination" do
    test "shows pagination controls when more than one page", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)

      for i <- 1..26 do
        insert(:viewer, organization: org, email: "viewer#{i}@test.com")
      end

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")

      assert has_element?(view, "[data-test='viewer-pagination']")
      assert has_element?(view, "[data-test='viewer-next-page']")
      assert has_element?(view, "[data-test='viewer-prev-page']")
    end

    test "navigating to next page shows different viewers", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)

      for i <- 1..26 do
        insert(:viewer,
          organization: org,
          email: "viewer#{String.pad_leading("#{i}", 2, "0")}@test.com"
        )
      end

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")

      html_page1 = render(view)
      assert html_page1 =~ "Page 1 of 2"

      html_page2 = render_click(view, "page", %{"page" => "2"})
      assert html_page2 =~ "Page 2 of 2"
    end

    test "does not show pagination with few viewers", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)
      insert(:viewer, organization: org, email: "only@test.com")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")

      refute has_element?(view, "[data-test='viewer-pagination']")
    end

    test "filter resets page to 1", %{conn: _conn} do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :admin)

      for i <- 1..26 do
        insert(:viewer, organization: org, email: "viewer#{i}@test.com", status: :active)
      end

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/members")
      render_click(view, "page", %{"page" => "2"})

      html = render_change(view, "filter", %{"status" => "active", "subscription" => ""})
      assert html =~ "Page 1 of"
    end
  end
end
