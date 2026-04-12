defmodule BobineWeb.Admin.AnalyticsLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  # ---------------------------------------------------------------------------
  # Access control
  # ---------------------------------------------------------------------------

  describe "access control" do
    test "admin can access analytics page", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/analytics")
      assert html =~ "Analytics"
    end

    test "owner can access analytics page", %{conn: _conn} do
      membership = insert(:membership, role: :owner)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/analytics")
      assert html =~ "Analytics"
    end

    test "editor can access analytics page", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/analytics")
      assert html =~ "Analytics"
    end

    test "viewer_support can access analytics page", %{conn: _conn} do
      membership = insert(:membership, role: :viewer_support)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/analytics")
      assert html =~ "Analytics"
    end

    test "unauthenticated user is redirected to login", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/analytics")
      assert path == ~p"/users/log-in"
    end
  end

  # ---------------------------------------------------------------------------
  # Mount and render
  # ---------------------------------------------------------------------------

  describe "mount and render" do
    test "displays KPI cards", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      assert has_element?(view, "[data-test='kpi-active-subscribers']")
      assert has_element?(view, "[data-test='kpi-mrr']")
      assert has_element?(view, "[data-test='kpi-total-views']")
      assert has_element?(view, "[data-test='kpi-avg-watch-time']")
    end

    test "displays period selector buttons", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      assert has_element?(view, "[data-test='period-selector-7']")
      assert has_element?(view, "[data-test='period-selector-30']")
      assert has_element?(view, "[data-test='period-selector-90']")
    end

    test "displays chart canvases", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      assert has_element?(view, "[data-test='subscriber-chart']")
      assert has_element?(view, "[data-test='revenue-chart']")
    end

    test "displays churn indicators section", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      assert has_element?(view, "[data-test='churn-dunning']")
      assert has_element?(view, "[data-test='churn-cancellations']")
      assert has_element?(view, "[data-test='churn-trial-conversion']")
    end

    test "displays content table sort headers", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      assert has_element?(view, "[data-test='sort-col-title']")
      assert has_element?(view, "[data-test='sort-col-unique_viewers']")
      assert has_element?(view, "[data-test='sort-col-completion_rate']")
      assert has_element?(view, "[data-test='sort-col-watchlist_adds']")
      assert has_element?(view, "[data-test='sort-col-favorites']")
    end

    test "shows empty state when no content exists", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")
      assert has_element?(view, "[data-test='content-empty-state']")
    end

    test "displays org name in sidebar", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")
      assert has_element?(view, "[data-test='org-name']", membership.organization.name)
    end
  end

  # ---------------------------------------------------------------------------
  # Period selector
  # ---------------------------------------------------------------------------

  describe "set_period event" do
    test "changing period re-renders the page" do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      html = render_click(view, "set_period", %{"period" => "7"})
      assert html =~ "Analytics"
    end

    test "30-day period selector is default active" do
      membership = insert(:membership, role: :admin)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/analytics")

      assert html =~ "btn-primary"
    end

    test "selecting 90-day period updates active button" do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      _html = render_click(view, "set_period", %{"period" => "90"})
      html = render(view)
      assert html =~ "90d"
    end
  end

  # ---------------------------------------------------------------------------
  # Content table sorting
  # ---------------------------------------------------------------------------

  describe "sort_content event" do
    test "sorting by a column re-renders content table" do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      html = render_click(view, "sort_content", %{"col" => "unique_viewers"})
      assert html =~ "Analytics"
    end

    test "clicking same column toggles sort direction" do
      membership = insert(:membership, role: :admin)

      _video = insert(:video, organization: membership.organization)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      render_click(view, "sort_content", %{"col" => "unique_viewers"})
      html = render_click(view, "sort_content", %{"col" => "unique_viewers"})
      assert html =~ "Analytics"
    end

    test "shows content rows for videos" do
      membership = insert(:membership, role: :admin)
      video = insert(:video, organization: membership.organization)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      assert has_element?(view, "[data-test='content-row-#{video.id}']")
    end
  end

  # ---------------------------------------------------------------------------
  # Pagination
  # ---------------------------------------------------------------------------

  describe "content pagination" do
    test "paginates content when more than 20 videos" do
      membership = insert(:membership, role: :admin)
      for _ <- 1..25, do: insert(:video, organization: membership.organization)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")
      assert has_element?(view, "[data-test='content-pagination']")
    end

    test "navigating to next page works" do
      membership = insert(:membership, role: :admin)
      for _ <- 1..25, do: insert(:video, organization: membership.organization)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      html = render_click(view, "content_page", %{"page" => "2"})
      assert html =~ "Analytics"
    end
  end

  # ---------------------------------------------------------------------------
  # Multi-tenant isolation
  # ---------------------------------------------------------------------------

  describe "tenant isolation" do
    test "org A data is not visible in org B's dashboard" do
      membership_a = insert(:membership, role: :admin)
      membership_b = insert(:membership, role: :admin)

      insert(:viewer_subscription,
        organization: membership_b.organization,
        status: "past_due"
      )

      {:ok, _view_a, html_a} = live(conn_for(membership_a), ~p"/admin/analytics")
      {:ok, _view_b, html_b} = live(conn_for(membership_b), ~p"/admin/analytics")

      assert html_a =~ membership_a.organization.name
      refute html_a =~ membership_b.organization.name
      assert html_b =~ membership_b.organization.name
      refute html_b =~ membership_a.organization.name
    end

    test "org A videos not visible in org B analytics" do
      membership_a = insert(:membership, role: :admin)
      membership_b = insert(:membership, role: :admin)

      video_a = insert(:video, organization: membership_a.organization)

      {:ok, view_b, _html} = live(conn_for(membership_b), ~p"/admin/analytics")
      refute has_element?(view_b, "[data-test='content-row-#{video_a.id}']")
    end
  end

  # ---------------------------------------------------------------------------
  # KPI values
  # ---------------------------------------------------------------------------

  describe "kpi values with data" do
    test "shows active subscriber count" do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      plan = insert(:plan, organization: org, amount: 999, interval: :monthly)
      insert(:viewer_subscription, organization: org, plan: plan, status: "active")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      assert has_element?(view, "[data-test='kpi-active-subscribers']", "1")
    end

    test "renders top drop-off bucket cell for each video" do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      video = insert(:video, organization: org)

      insert(:video_drop_off_bucket,
        organization: org,
        video: video,
        bucket: 6,
        count: 4
      )

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      cell = element(view, "[data-test='drop-off-cell-#{video.id}']")
      assert render(cell) =~ "60–70s"
      assert render(cell) =~ "(4)"
    end

    test "shows em-dash when video has no drop-off data" do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      video = insert(:video, organization: org)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      cell = element(view, "[data-test='drop-off-cell-#{video.id}']")
      assert render(cell) =~ "—"
    end

    test "mounts without crashing when progress rows have float averages" do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      video = insert(:video, organization: org)

      for position <- [60.0, 75.0, 90.0] do
        insert(:progress,
          organization: org,
          video: video,
          user: build(:user),
          position: position,
          duration: 120.0
        )
      end

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      assert has_element?(view, "[data-test='kpi-avg-watch-time']")
      assert has_element?(view, "[data-test='content-row-#{video.id}']")
    end
  end

  # ---------------------------------------------------------------------------
  # Series analytics links
  # ---------------------------------------------------------------------------

  describe "series analytics section" do
    test "renders links to series analytics when org has series" do
      membership = insert(:membership, role: :admin)
      series = insert(:series, organization: membership.organization, title: "My Show")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/analytics")

      assert has_element?(view, "[data-test='series-analytics-link-#{series.id}']", "My Show")
    end

    test "hides series section when org has no series" do
      membership = insert(:membership, role: :admin)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/analytics")

      refute html =~ "View retention"
    end
  end
end
