defmodule BobineWeb.Super.OrganizationsLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /super/organizations" do
    test "lists all organizations", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org_a = insert(:organization, name: "Alpha Studio", slug: "alpha-studio")
      org_b = insert(:organization, name: "Beta Channel", slug: "beta-channel")

      {:ok, _view, html} = live(conn, ~p"/super/organizations")
      assert html =~ org_a.name
      assert html =~ org_b.name
    end

    test "search filters results", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      insert(:organization, name: "Alpha Studio", slug: "alpha-studio")
      insert(:organization, name: "Beta Channel", slug: "beta-channel")

      {:ok, view, _html} = live(conn, ~p"/super/organizations")

      html = view |> element("[data-test='org-search']") |> render_change(%{search: "Alpha"})
      assert html =~ "Alpha Studio"
      refute html =~ "Beta Channel"
    end

    test "shows New Organization button", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      {:ok, _view, html} = live(conn, ~p"/super/organizations")
      assert html =~ ~s(data-test="new-org-btn")
    end

    test "non-super-admin cannot access", %{conn: _conn} do
      user = insert(:user, is_super_admin: false)
      membership = insert(:membership, user: user)
      conn = conn_for(membership)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/super/organizations")
    end
  end
end
