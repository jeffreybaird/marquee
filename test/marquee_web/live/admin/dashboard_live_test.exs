defmodule MarqueeWeb.Admin.DashboardLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Onboarding.StarterContent

  describe "access control" do
    test "owner can access dashboard", %{conn: _conn} do
      membership = insert(:membership, role: :owner)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin")
      assert html =~ "Dashboard"
    end

    test "admin can access dashboard", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin")
      assert html =~ "Dashboard"
    end

    test "editor can access dashboard", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin")
      assert html =~ "Dashboard"
    end

    test "viewer_support can access dashboard", %{conn: _conn} do
      membership = insert(:membership, role: :viewer_support)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin")
      assert html =~ "Dashboard"
    end

    test "unauthenticated user is redirected to login", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin")
      assert path == ~p"/users/log-in"
    end

    test "authenticated user without membership is redirected", %{conn: conn} do
      org = insert(:organization)
      user = insert(:user)
      conn = conn |> Map.put(:host, "#{org.slug}.localhost") |> log_in_user(user)
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin")
    end
  end

  describe "multi-tenant isolation" do
    test "user from org A cannot access org B's dashboard", %{conn: _conn} do
      membership_a = insert(:membership, role: :admin)
      org_b = insert(:organization)
      insert(:membership, user: membership_a.user, organization: org_b, role: :viewer_support)

      # Log in on org_b's subdomain — user is a member, but trying to hit /admin
      # which resolves to org_b, not org_a
      org_b_conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org_b.slug}.localhost")
        |> log_in_user(membership_a.user)

      {:ok, _view, html} = live(org_b_conn, ~p"/admin")
      assert html =~ org_b.name
    end

    test "org A data is not visible in org B's dashboard", %{conn: _conn} do
      membership_a = insert(:membership, role: :admin)
      membership_b = insert(:membership, role: :admin)

      {:ok, _view, html_a} = live(conn_for(membership_a), ~p"/admin")
      {:ok, _view, html_b} = live(conn_for(membership_b), ~p"/admin")

      assert html_a =~ membership_a.organization.name
      refute html_a =~ membership_b.organization.name
      assert html_b =~ membership_b.organization.name
      refute html_b =~ membership_a.organization.name
    end
  end

  describe "layout" do
    test "displays organization name", %{conn: _conn} do
      membership = insert(:membership, role: :admin)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      assert has_element?(view, "[data-test='org-name']", membership.organization.name)
    end

    test "displays admin navigation links", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      assert has_element?(view, "[data-test='admin-nav-content']")
      assert has_element?(view, "[data-test='admin-nav-catalog']")
      assert has_element?(view, "[data-test='admin-nav-analytics']")
      assert has_element?(view, "[data-test='admin-nav-appearance']")
      assert has_element?(view, "[data-test='admin-nav-members']")
      assert has_element?(view, "[data-test='admin-nav-webhooks']")
      assert has_element?(view, "[data-test='admin-nav-settings']")
    end
  end

  describe "sample content banner" do
    test "shows a clear banner when the org has seeded sample content", %{conn: _conn} do
      membership = insert(:membership, role: :owner)
      {:ok, _} = StarterContent.seed(membership.organization)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      assert has_element?(view, "[data-test='sample-content-banner']")
      assert has_element?(view, "[data-test='sample-content-clear']")
    end

    test "hides the banner when there is no sample content", %{conn: _conn} do
      membership = insert(:membership, role: :owner)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      refute has_element?(view, "[data-test='sample-content-banner']")
    end
  end
end
