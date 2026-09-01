defmodule MarqueeWeb.Super.AuditLogLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  setup :verify_on_exit!

  describe "render" do
    test "super admin can access platform audit log", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      {:ok, _view, html} = live(conn, ~p"/super/audit-log")

      assert html =~ "Platform Audit Log"
    end

    test "shows logs from all organizations", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org_a = insert(:organization)
      org_b = insert(:organization)
      log_a = insert(:audit_log, organization: org_a, action: "video.created")
      log_b = insert(:audit_log, organization: org_b, action: "collection.updated")

      {:ok, view, _html} = live(conn, ~p"/super/audit-log")

      assert has_element?(view, "[data-test='audit-log-row-#{log_a.id}']")
      assert has_element?(view, "[data-test='audit-log-row-#{log_b.id}']")
    end

    test "shows organization filter dropdown", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      {:ok, view, _html} = live(conn, ~p"/super/audit-log")

      assert has_element?(view, "[data-test='filter-org']")
    end

    test "shows organization column in table", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)
      insert(:audit_log, organization: org)

      {:ok, _view, html} = live(conn, ~p"/super/audit-log")

      assert html =~ "Organization"
    end
  end

  describe "org filter" do
    test "filtering by organization shows only that org's logs", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org_a = insert(:organization)
      org_b = insert(:organization)
      log_a = insert(:audit_log, organization: org_a)
      log_b = insert(:audit_log, organization: org_b)

      {:ok, view, _html} = live(conn, ~p"/super/audit-log")

      # Send filter event directly (bypasses select value validation since
      # filter_options cache may not include newly-created test orgs)
      render_click(view, "filter", %{"organization_id" => org_a.id})

      assert has_element?(view, "[data-test='audit-log-row-#{log_a.id}']")
      refute has_element?(view, "[data-test='audit-log-row-#{log_b.id}']")
    end
  end

  describe "CSV export" do
    test "clicking export CSV triggers export and shows flash", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      stub(Marquee.Storage.MockSpacesClient, :put_object, fn _key, _body, _ct -> :ok end)

      {:ok, view, _html} = live(conn, ~p"/super/audit-log")

      view |> element("[data-test='export-csv-btn']") |> render_click()

      html = render(view)
      assert html =~ "Export queued" or html =~ "Export ready"
    end
  end

  describe "access control" do
    test "non-super-admin is redirected", %{conn: _conn} do
      user = insert(:user, is_super_admin: false)
      membership = insert(:membership, user: user)

      assert {:error, {:redirect, _}} = live(conn_for(membership), ~p"/super/audit-log")
    end

    test "unauthenticated user is redirected to login" do
      conn = build_conn()
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/super/audit-log")
    end
  end
end
