defmodule BobineWeb.E2E.FullUserJourneyTest do
  use BobineWeb.WallabyCase

  @moduletag :e2e

  describe "magic link login to admin dashboard" do
    test "user logs in via magic link and lands on admin dashboard", %{session: session} do
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user, role: :admin)

      session
      |> log_in_session(user, org)
      |> assert_has(Query.css("[data-test='org-name']", text: org.name))
      |> assert_has(Query.css("h1", text: "Dashboard"))
    end
  end

  describe "sidebar navigation highlights active page" do
    test "content link is highlighted when on content page", %{session: session} do
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user, role: :admin)

      session =
        session
        |> Wallaby.Browser.resize_window(1280, 800)
        |> log_in_session(user, org)
        |> Wallaby.Browser.visit("/admin/content?org=#{org.slug}")

      # The active nav link should have a distinct style (bg-primary class)
      content_link = Wallaby.Browser.find(session, Query.css("[data-test='admin-nav-content']"))
      classes = Wallaby.Element.attr(content_link, "class")
      assert classes =~ "bg-admin-accent"
    end

    test "all sidebar links navigate to their pages", %{session: session} do
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user, role: :admin)

      pages = [
        {"admin-nav-dashboard", "Dashboard"},
        {"admin-nav-content", "Content"},
        {"admin-nav-collections", "Collections"},
        {"admin-nav-tags", "Tags"},
        {"admin-nav-catalog", "Catalog"},
        {"admin-nav-analytics", "Analytics"},
        {"admin-nav-appearance", "Appearance"},
        {"admin-nav-members", "Members"},
        {"admin-nav-webhooks", "Webhooks"},
        {"admin-nav-settings", "Settings"}
      ]

      # Ensure viewport is wide enough for the sidebar to be visible (lg breakpoint)
      session = Wallaby.Browser.resize_window(session, 1280, 800)
      session = log_in_session(session, user, org)
      # Wait for the admin dashboard to fully render before navigating
      session = assert_has(session, Query.css("h1", text: "Dashboard"))

      for {data_test, title} <- pages do
        session
        |> Wallaby.Browser.click(Query.css("[data-test='#{data_test}']"))
        |> assert_has(Query.css("h1", text: title))
      end
    end
  end

  describe "viewer pages via magic link" do
    test "viewer registration form renders", %{session: session} do
      org = insert(:organization)

      session
      |> Wallaby.Browser.visit("/register?org=#{org.slug}")
      |> assert_has(Query.css("[data-test='register-form']"))
      |> assert_has(Query.css("[data-test='register-email-input']"))
    end

    test "viewer login form renders", %{session: session} do
      org = insert(:organization)

      session
      |> Wallaby.Browser.visit("/login?org=#{org.slug}")
      |> assert_has(Query.css("[data-test='login-form']"))
      |> assert_has(Query.css("[data-test='login-email-input']"))
    end
  end
end
