defmodule MarqueeWeb.Admin.DashboardLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Accounts
  alias Marquee.Onboarding.StarterContent
  alias Marquee.Repo

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

  describe "overview stats" do
    test "renders KPI cards", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      assert has_element?(view, "[data-test='kpi-active-subscribers']")
      assert has_element?(view, "[data-test='kpi-mrr']")
      assert has_element?(view, "[data-test='kpi-total-views']")
      assert has_element?(view, "[data-test='kpi-published-videos']")
    end

    test "published-videos KPI reflects the org's published count", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      insert(:video, organization: org, published: true)
      insert(:video, organization: org, published: false)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      assert has_element?(view, "[data-test='kpi-published-videos']", "1")
    end

    test "recent uploads show an empty state when there are no videos", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      assert has_element?(view, "[data-test='recent-uploads-empty']")
    end
  end

  describe "setup nudges" do
    test "a fresh org sees setup nudges at the top", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      assert has_element?(view, "[data-test='dashboard-nudges']")
      assert has_element?(view, "[data-test='nudge-connect_stripe']")
      assert has_element?(view, "[data-test='nudge-create_plan']")
    end

    test "dismissing a nudge removes it from the view", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      view
      |> element("[data-test='dismiss-nudge-connect_stripe']")
      |> render_click()

      refute has_element?(view, "[data-test='nudge-connect_stripe']")
    end

    test "a dismissed nudge stays gone after reload", %{conn: _conn} do
      membership = insert(:membership, role: :admin)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      view
      |> element("[data-test='dismiss-nudge-connect_stripe']")
      |> render_click()

      {:ok, reloaded, _html} = live(conn_for(membership), ~p"/admin")
      refute has_element?(reloaded, "[data-test='nudge-connect_stripe']")
      # other nudges remain
      assert has_element?(reloaded, "[data-test='nudge-create_plan']")
    end

    test "a nudge disappears once its setup step is complete", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      insert(:plan, organization: org, active: true)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      refute has_element?(view, "[data-test='nudge-create_plan']")
    end
  end

  describe "layout" do
    test "displays a link to view the member-facing site in a new tab", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      # The link carries the org slug + preview intent so operators land on
      # the org's viewer home instead of being redirected back to /admin.
      slug = membership.organization.slug

      assert has_element?(
               view,
               "[data-test='admin-view-site'][href='/?org=#{slug}&preview=member'][target='_blank']"
             )
    end

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

  describe "guided admin tour" do
    test "auto-starts and offers a restart link for an operator who hasn't seen it", %{
      conn: _conn
    } do
      membership = insert(:membership, role: :owner, admin_tour_completed_at: nil)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      assert has_element?(view, "#admin-guided-tour[data-auto-start='true']")
      assert has_element?(view, "[data-test='restart-tour']")
    end

    test "does not auto-start for an operator who already completed it", %{conn: _conn} do
      # Factory memberships default to already-toured.
      membership = insert(:membership, role: :owner)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      assert has_element?(view, "#admin-guided-tour[data-auto-start='false']")
      # The restart link is always available so the tour can be replayed.
      assert has_element?(view, "[data-test='restart-tour']")
    end

    test "passes the organization name to the tour as the brand", %{conn: _conn} do
      membership = insert(:membership, role: :owner)
      org = Repo.preload(membership, :organization).organization

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      assert has_element?(view, "#admin-guided-tour[data-tour-brand='#{org.name}']")
    end

    test "completing the tour records it on the membership", %{conn: _conn} do
      membership = insert(:membership, role: :owner, admin_tour_completed_at: nil)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      refute Accounts.admin_tour_completed?(Repo.reload!(membership))

      render_hook(view, "tour_completed", %{})

      assert Accounts.admin_tour_completed?(Repo.reload!(membership))
      assert has_element?(view, "#admin-guided-tour[data-auto-start='false']")
    end

    test "the restart link pushes a start-tour event", %{conn: _conn} do
      membership = insert(:membership, role: :owner)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin")

      view |> element("[data-test='restart-tour']") |> render_click()

      assert_push_event(view, "start-tour", %{})
    end
  end
end
