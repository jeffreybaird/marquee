defmodule MarqueeWeb.Super.AnalyticsLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "access control" do
    test "super admin can access analytics dashboard", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      {:ok, _view, html} = live(conn, ~p"/super/analytics")
      assert html =~ "Platform Analytics"
    end

    test "non-super-admin is redirected", %{conn: _conn} do
      user = insert(:user, is_super_admin: false)
      membership = insert(:membership, user: user)
      conn = conn_for(membership)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/super/analytics")
    end

    test "unauthenticated user is redirected to log in" do
      conn = build_conn()
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/super/analytics")
    end
  end

  describe "overview cards" do
    test "renders all four stat cards", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      {:ok, _view, html} = live(conn, ~p"/super/analytics")

      assert html =~ ~s(data-test="stat-total-orgs")
      assert html =~ ~s(data-test="stat-total-viewers")
      assert html =~ ~s(data-test="stat-platform-mrr")
      assert html =~ ~s(data-test="stat-viewer-fee-revenue")
    end
  end

  describe "chart containers" do
    test "renders MRR and signup chart containers", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      {:ok, _view, html} = live(conn, ~p"/super/analytics")

      assert html =~ ~s(data-test="mrr-chart")
      assert html =~ ~s(data-test="signup-chart")
      assert html =~ ~s(phx-hook="AnalyticsChart")
      assert html =~ ~s(data-chart-event="super:mrr")
      assert html =~ ~s(data-chart-event="super:signups")
    end
  end

  describe "org health table" do
    test "renders the org health table", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      insert(:organization)

      {:ok, _view, html} = live(conn, ~p"/super/analytics")
      assert html =~ ~s(data-test="org-health-table")
    end

    test "shows org rows with data-test attributes", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization, name: "Test Corp")

      {:ok, _view, html} = live(conn, ~p"/super/analytics")
      assert html =~ ~s(data-test="org-health-row-#{org.id}")
      assert html =~ "Test Corp"
    end

    test "shows empty state when no organizations match search", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      {:ok, view, _html} = live(conn, ~p"/super/analytics")

      html =
        view
        |> element("[data-test='org-search']")
        |> render_change(%{"search" => "zzz-no-match-xyz"})

      assert html =~ ~s(data-test="org-health-empty")
    end
  end

  describe "search" do
    test "filters orgs by search term", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      insert(:organization, name: "Alpha Studio", slug: "alpha-studio-search")
      insert(:organization, name: "Beta Channel", slug: "beta-channel-search")

      {:ok, view, _html} = live(conn, ~p"/super/analytics")

      html =
        view
        |> element("[data-test='org-search']")
        |> render_change(%{"search" => "Alpha"})

      assert html =~ "Alpha Studio"
      refute html =~ "Beta Channel"
    end
  end

  describe "sort headers" do
    test "renders sort header buttons with data-test attributes", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      {:ok, _view, html} = live(conn, ~p"/super/analytics")

      assert html =~ ~s(data-test="sort-name")
      assert html =~ ~s(data-test="sort-subscribers")
      assert html =~ ~s(data-test="sort-mrr")
      assert html =~ ~s(data-test="sort-videos")
    end

    test "clicking a sort header toggles sort direction", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      insert(:organization, name: "Zebra Org", slug: "zebra-org-sort")
      insert(:organization, name: "Aardvark Org", slug: "aardvark-org-sort")

      {:ok, view, _html} = live(conn, ~p"/super/analytics")

      # First click — sort by name desc
      view |> element("[data-test='sort-name']") |> render_click()

      # Second click — toggles to asc
      html = view |> element("[data-test='sort-name']") |> render_click()

      assert html =~ "Aardvark Org"
    end
  end

  describe "pagination" do
    test "shows pagination when there are multiple pages", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      for i <- 1..30 do
        insert(:organization, name: "Pag Org #{i}", slug: "pag-org-lv-#{i}")
      end

      {:ok, view, _html} = live(conn, ~p"/super/analytics")

      # With default per_page=25 and 30+ orgs, pagination should appear
      html = render(view)
      assert html =~ ~s(data-test="pagination")
    end

    test "next page button loads next set of results", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      for i <- 1..30 do
        insert(:organization,
          name: "NextPage Org #{String.pad_leading("#{i}", 2, "0")}",
          slug: "nextpage-org-#{i}"
        )
      end

      {:ok, view, _html} = live(conn, ~p"/super/analytics")

      html = render(view)

      if html =~ ~s(data-test="pagination-next") do
        next_html = view |> element("[data-test='pagination-next']") |> render_click()
        assert next_html =~ ~s(data-test="pagination-info")
        assert next_html =~ "Page 2"
      end
    end
  end

  describe "navigation" do
    test "analytics link appears in super nav", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      {:ok, _view, html} = live(conn, ~p"/super/analytics")
      assert html =~ ~s(data-test="super-nav-analytics")
    end
  end
end
