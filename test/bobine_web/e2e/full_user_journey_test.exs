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
        |> log_in_session(user, org)
        |> Wallaby.Browser.visit("/admin/content?org=#{org.slug}")

      # The active nav link should have a distinct style (bg-primary class)
      content_link = Wallaby.Browser.find(session, Query.css("[data-test='admin-nav-content']"))
      classes = Wallaby.Element.attr(content_link, "class")
      assert classes =~ "bg-primary"
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
        {"admin-nav-branding", "Branding"},
        {"admin-nav-members", "Members"},
        {"admin-nav-webhooks", "Webhooks"},
        {"admin-nav-settings", "Settings"}
      ]

      session = log_in_session(session, user, org)

      for {data_test, title} <- pages do
        session
        |> Wallaby.Browser.click(Query.css("[data-test='#{data_test}']"))
        |> assert_has(Query.css("h1", text: title))
      end
    end
  end

  describe "viewer pages exist" do
    test "/watchlist page renders for authenticated user", %{session: session} do
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user)

      session
      |> log_in_session(user, org)
      |> Wallaby.Browser.visit("/watchlist?org=#{org.slug}")
      |> assert_has(Query.css("h1", text: "Watchlist"))
    end

    test "/account page renders for authenticated user", %{session: session} do
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user)

      session
      |> log_in_session(user, org)
      |> Wallaby.Browser.visit("/account?org=#{org.slug}")
      |> assert_has(Query.css("h1", text: "Account"))
    end
  end
end
