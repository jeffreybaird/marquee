defmodule MarqueeWeb.Admin.AuditLogLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  setup :verify_on_exit!

  describe "render" do
    test "renders audit log page with table", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      user = membership.user
      insert(:audit_log, organization: org, user: user, action: "video.created")

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/audit-log")

      assert html =~ "Audit Log"
      assert has_element?(view, "[data-test='audit-log-table']")
    end

    test "displays audit log rows", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      user = membership.user
      log = insert(:audit_log, organization: org, user: user, action: "video.created")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/audit-log")

      assert has_element?(view, "[data-test='audit-log-row-#{log.id}']")
    end

    test "shows empty state when no logs", %{conn: _conn} do
      membership = insert(:membership, role: :admin)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/audit-log")

      assert has_element?(view, "[data-test='empty-state']")
    end

    test "shows filter dropdowns", %{conn: _conn} do
      membership = insert(:membership, role: :admin)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/audit-log")

      assert has_element?(view, "[data-test='filter-action']")
      assert has_element?(view, "[data-test='filter-actor']")
      assert has_element?(view, "[data-test='filter-resource-type']")
      assert has_element?(view, "[data-test='filter-from']")
      assert has_element?(view, "[data-test='filter-to']")
      assert has_element?(view, "[data-test='filter-search']")
    end
  end

  describe "filtering" do
    test "filter by action shows matching logs only", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization

      log_a = insert(:audit_log, organization: org, action: "video.created")
      log_b = insert(:audit_log, organization: org, action: "video.deleted")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/audit-log")

      view
      |> form("form", %{action: "video.created"})
      |> render_change()

      assert has_element?(view, "[data-test='audit-log-row-#{log_a.id}']")
      refute has_element?(view, "[data-test='audit-log-row-#{log_b.id}']")
    end

    test "filter by actor shows matching logs only", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      user_a = insert(:user)
      user_b = insert(:user)

      log_a = insert(:audit_log, organization: org, user: user_a)
      log_b = insert(:audit_log, organization: org, user: user_b)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/audit-log")

      view
      |> form("form", %{user_id: user_a.id})
      |> render_change()

      assert has_element?(view, "[data-test='audit-log-row-#{log_a.id}']")
      refute has_element?(view, "[data-test='audit-log-row-#{log_b.id}']")
    end

    test "filter by resource_type shows matching logs only", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization

      log_v = insert(:audit_log, organization: org, resource_type: "Video")
      log_c = insert(:audit_log, organization: org, resource_type: "Collection")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/audit-log")

      view
      |> form("form", %{resource_type: "Video"})
      |> render_change()

      assert has_element?(view, "[data-test='audit-log-row-#{log_v.id}']")
      refute has_element?(view, "[data-test='audit-log-row-#{log_c.id}']")
    end

    test "clicking actor sets actor filter", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      user = insert(:user)
      log = insert(:audit_log, organization: org, user: user)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/audit-log")

      view
      |> element("[data-test='actor-link-#{log.id}']")
      |> render_click()

      assert has_element?(view, "[data-test='audit-log-row-#{log.id}']")
    end

    test "clicking action sets action filter", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      log = insert(:audit_log, organization: org, action: "video.created")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/audit-log")

      view
      |> element("[data-test='action-link-#{log.id}']")
      |> render_click()

      assert has_element?(view, "[data-test='audit-log-row-#{log.id}']")
    end
  end

  describe "expand row" do
    test "clicking expand shows metadata for the row", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      log = insert(:audit_log, organization: org, metadata: %{"ip" => "1.2.3.4"})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/audit-log")

      refute has_element?(view, "[data-test='metadata-row-#{log.id}']")

      view
      |> element("[data-test='expand-btn-#{log.id}']")
      |> render_click()

      assert has_element?(view, "[data-test='metadata-row-#{log.id}']")
    end

    test "clicking expand again collapses the row", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      log = insert(:audit_log, organization: org)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/audit-log")

      view |> element("[data-test='expand-btn-#{log.id}']") |> render_click()
      assert has_element?(view, "[data-test='metadata-row-#{log.id}']")

      view |> element("[data-test='expand-btn-#{log.id}']") |> render_click()
      refute has_element?(view, "[data-test='metadata-row-#{log.id}']")
    end
  end

  describe "cursor load-more" do
    test "load more button appends logs", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization

      # Insert 51 logs so first page (50) has a cursor
      for i <- 1..51 do
        t = DateTime.add(~U[2026-04-01 00:00:00Z], i, :second)
        insert(:audit_log, organization: org, inserted_at: t)
      end

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/audit-log")

      assert has_element?(view, "[data-test='load-more-btn']")

      view |> element("[data-test='load-more-btn']") |> render_click()

      refute has_element?(view, "[data-test='load-more-btn']")
    end
  end

  describe "CSV export" do
    test "clicking export CSV triggers export and shows flash", %{conn: _conn} do
      membership = insert(:membership, role: :admin)

      stub(Marquee.Storage.MockSpacesClient, :put_object, fn _key, _body, _ct -> :ok end)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/audit-log")

      view |> element("[data-test='export-csv-btn']") |> render_click()

      # Job runs inline; after success the view updates flash to "Export ready"
      html = render(view)
      assert html =~ "Export queued" or html =~ "Export ready"
    end
  end

  describe "access control" do
    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")

      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/audit-log")
      assert path == ~p"/users/log-in"
    end

    test "viewer_support role can access audit log", %{conn: _conn} do
      membership = insert(:membership, role: :viewer_support)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/audit-log")
      assert html =~ "Audit Log"
    end
  end

  describe "tenant isolation" do
    test "org A cannot see org B's audit logs", %{conn: _conn} do
      membership_a = insert(:membership, role: :admin)
      org_b = insert(:organization)

      log_b = insert(:audit_log, organization: org_b, action: "secret.action")

      {:ok, view, _html} = live(conn_for(membership_a), ~p"/admin/audit-log")

      refute has_element?(view, "[data-test='audit-log-row-#{log_b.id}']")
    end
  end
end
