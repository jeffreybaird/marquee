defmodule BobineWeb.E2E.AdminDashboardTest do
  use BobineWeb.WallabyCase

  @moduletag :e2e

  # These E2E tests verify things LiveViewTest cannot cover:
  #   - The LiveSocket connects and JS executes in a real browser
  #   - Sidebar navigation renders and highlights the active link via CSS
  #   - Full HTTP stack: SetOrganization plug + AssignScope hook chain end-to-end
  #   - Real browser redirect behavior for unauthenticated access
  #
  # Org resolution: since Wallaby talks to localhost, we use ?org=<slug> to resolve
  # the tenant (the test env fallback supports this param).

  describe "admin dashboard shell" do
    test "authenticated admin can load the dashboard in a real browser", %{session: session} do
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user, role: :admin)

      session
      |> log_in_session(user, org)
      |> assert_has(Query.css("[data-test='org-name']", text: org.name))
      |> assert_has(Query.css("[data-test='admin-nav-content']"))
      |> assert_has(Query.css("[data-test='admin-nav-catalog']"))
    end

    test "sidebar nav link navigates to the content page", %{session: session} do
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user, role: :admin)

      session
      |> log_in_session(user, org)
      |> assert_has(Query.css("[data-test='admin-nav-content']"))
      |> Wallaby.Browser.click(Query.css("[data-test='admin-nav-content']"))
      |> assert_has(Query.css("h1", text: "Content"))
    end

    test "unauthenticated browser is redirected to login", %{session: session} do
      org = insert(:organization)

      session
      |> Wallaby.Browser.visit("/admin?org=#{org.slug}")
      |> assert_has(Query.css("h1", text: "Log in"))
    end
  end
end
