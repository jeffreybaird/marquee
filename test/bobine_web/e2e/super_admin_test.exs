defmodule BobineWeb.E2E.SuperAdminTest do
  use BobineWeb.WallabyCase

  @moduletag :e2e

  describe "super admin dashboard" do
    test "super admin can access /super in a real browser", %{session: session} do
      super_admin = insert(:super_admin)

      session
      |> Wallaby.Browser.resize_window(1280, 800)
      |> log_in_session(super_admin)
      |> Wallaby.Browser.visit("/super")
      |> assert_has(Query.css("[data-test='super-admin-badge']"))
      |> assert_has(Query.css("[data-test='stat-total-orgs']"))
    end

    test "super admin can navigate to organizations list", %{session: session} do
      super_admin = insert(:super_admin)
      insert(:organization, name: "Test Org E2E")

      session
      |> Wallaby.Browser.resize_window(1280, 800)
      |> log_in_session(super_admin)
      |> Wallaby.Browser.visit("/super/organizations")
      |> assert_has(Query.css("[data-test='org-table']"))
      |> assert_has(Query.text("Test Org E2E"))
    end

    test "non-super-admin is redirected away from /super", %{session: session} do
      user = insert(:user, is_super_admin: false)

      session
      |> Wallaby.Browser.resize_window(1280, 800)
      |> log_in_session(user)
      |> Wallaby.Browser.visit("/super")
      |> refute_has(Query.css("[data-test='super-admin-badge']"))
    end
  end

  describe "impersonation" do
    test "super admin can impersonate an org via browser", %{session: session} do
      super_admin = insert(:super_admin)
      org = insert(:organization, name: "Impersonate Target")

      session
      |> Wallaby.Browser.resize_window(1280, 800)
      |> log_in_session(super_admin)
      |> Wallaby.Browser.visit("/super/organizations/#{org.id}")
      |> assert_has(Query.css("[data-test='impersonate-btn']"))
    end
  end
end
