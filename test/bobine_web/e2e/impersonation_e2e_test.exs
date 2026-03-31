defmodule BobineWeb.E2E.ImpersonationE2ETest do
  use BobineWeb.WallabyCase

  @moduletag :e2e

  describe "impersonation flow in browser" do
    test "clicking impersonate navigates to org's admin dashboard", %{session: session} do
      super_admin = insert(:super_admin)
      org = insert(:organization, name: "Target Org")

      session
      |> log_in_session(super_admin)
      |> Wallaby.Browser.visit("/super/organizations/#{org.id}")
      |> assert_has(Query.css("[data-test='impersonate-btn']"))
      |> Wallaby.Browser.click(Query.css("[data-test='impersonate-btn']"))
      |> assert_has(Query.css("[data-test='impersonation-banner']"))
      |> assert_has(Query.text("Target Org"))
    end

    test "impersonated admin dashboard shows the correct org's data", %{session: session} do
      super_admin = insert(:super_admin)
      org = insert(:organization, name: "Impersonated Org")
      insert(:video, organization: org, title: "Org Video", mux_status: "ready")

      session
      |> log_in_session(super_admin)
      |> Wallaby.Browser.visit("/super/organizations/#{org.id}")
      |> Wallaby.Browser.click(Query.css("[data-test='impersonate-btn']"))
      # Wait for admin dashboard to fully load after redirect
      |> assert_has(Query.css("[data-test='admin-nav-content']"))
      # Navigate to content page while impersonating
      |> Wallaby.Browser.click(Query.css("[data-test='admin-nav-content']"))
      |> assert_has(Query.text("Org Video"))
    end
  end
end
