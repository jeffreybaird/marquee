defmodule MarqueeWeb.E2E.ImpersonationE2ETest do
  use MarqueeWeb.WallabyCase

  @moduletag :e2e

  describe "impersonation flow in browser" do
    test "clicking impersonate navigates to org's admin dashboard", %{session: session} do
      super_admin = insert(:super_admin)
      org = insert(:organization, name: "Target Org")

      session
      |> log_in_session(super_admin)
      |> Wallaby.Browser.visit("/super/organizations/#{org.id}")
      |> assert_has(Query.text("Target Org"))
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

      # Wait for the page content to render before clicking impersonate.
      # The impersonate button uses method="post" which requires Phoenix JS
      # to intercept the click and submit a hidden form.
      session = assert_has(session, Query.text("Impersonated Org"))
      session = assert_has(session, Query.css("[data-test='impersonate-btn']"))

      session =
        session
        |> Wallaby.Browser.click(Query.css("[data-test='impersonate-btn']"))

      # Wait for admin dashboard to fully load after POST redirect
      session = assert_has(session, Query.css("[data-test='impersonation-banner']"))

      # Navigate to content page while impersonating
      session
      |> Wallaby.Browser.click(Query.css("[data-test='admin-nav-content']"))
      |> assert_has(Query.text("Org Video"))
    end
  end
end
