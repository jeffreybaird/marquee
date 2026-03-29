defmodule BobineWeb.Super.OrganizationShowLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /super/organizations/:id" do
    test "displays org details", %{conn: conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization, name: "Show Org", custom_domain: "show.example.com")

      {:ok, _view, html} = live(conn, ~p"/super/organizations/#{org.id}")
      assert html =~ "Show Org"
      assert html =~ "show.example.com"
    end

    test "shows member list", %{conn: conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user, role: :editor)

      {:ok, _view, html} = live(conn, ~p"/super/organizations/#{org.id}")
      assert html =~ user.email
      assert html =~ "editor"
    end

    test "impersonate button is present", %{conn: conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)

      {:ok, _view, html} = live(conn, ~p"/super/organizations/#{org.id}")
      assert html =~ ~s(data-test="impersonate-btn")
    end

    test "non-super-admin cannot access", %{conn: conn} do
      user = insert(:user, is_super_admin: false)
      membership = insert(:membership, user: user)
      conn = conn_for(membership)
      org = insert(:organization)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/super/organizations/#{org.id}")
    end
  end
end
