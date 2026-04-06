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
      |> assert_has(Query.css(".phx-connected"))
      |> assert_has(Query.css("[data-test='impersonate-btn']"))
      |> Wallaby.Browser.click(Query.css("[data-test='impersonate-btn']"))
      |> assert_has(Query.css("[data-test='impersonation-banner']"))
      |> assert_has(Query.text("Target Org"))
    end

    test "impersonated admin dashboard shows the correct org's data", %{session: session} do
      super_admin = insert(:super_admin)
      org = insert(:organization, name: "Impersonated Org")
      insert(:video, organization: org, title: "Org Video", mux_status: "ready")

      session =
        session
        |> log_in_session(super_admin)
        |> Wallaby.Browser.visit("/super/organizations/#{org.id}")

      # Wait for LiveView + Phoenix JS to fully initialize.
      # The impersonate button uses method="post" which requires Phoenix JS
      # to intercept the click and submit a hidden form. Waiting for the
      # phx-connected class on the LiveView root ensures JS is ready.
      session = assert_has(session, Query.css(".phx-connected"))
      session = assert_has(session, Query.css("[data-test='impersonate-btn']"))

      # DEBUG: screenshot before clicking impersonate
      Wallaby.Browser.take_screenshot(session, name: "before-impersonate-click")

      session =
        session
        |> Wallaby.Browser.click(Query.css("[data-test='impersonate-btn']"))

      # DEBUG: screenshot after clicking impersonate (should be admin dashboard)
      Wallaby.Browser.take_screenshot(session, name: "after-impersonate-click")

      # Wait for admin dashboard to fully load after POST redirect
      session = assert_has(session, Query.css("[data-test='impersonation-banner']"))

      # Navigate to content page while impersonating
      session
      |> Wallaby.Browser.click(Query.css("[data-test='admin-nav-content']"))
      |> assert_has(Query.text("Org Video"))
    end
  end
end
