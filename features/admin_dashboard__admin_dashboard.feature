Feature: Admin Dashboard

  Background:
    Given I am logged in as an operator

  Scenario: Operator views the dashboard
    When I navigate to /admin/
    Then I see quick stats including subscriber count, video count, and MRR
    And I see links to all admin sections

  Scenario: Dashboard stats reflect current organization data
    Given my organization has subscribers, videos, and revenue
    When I view the dashboard
    Then the displayed stats match the current organization data

  Scenario: Operator can open the member-facing site
    When I navigate to /admin/
    Then I see a link to view the member-facing site

  Scenario: Operator previewing the site lands on the member home, not the admin dashboard
    Given my organization has a published video in a visible row
    When I open the member-facing site preview
    Then I see the member-facing home instead of the admin dashboard

  Scenario: Operator sees setup nudges on a freshly created organization
    When I navigate to /admin/
    Then I see a setup nudge prompting me to connect Stripe

  Scenario: Operator dismisses a setup nudge and it stays hidden
    When I navigate to /admin/
    And I dismiss the connect-Stripe setup nudge
    Then the connect-Stripe nudge no longer appears
    And the connect-Stripe nudge stays hidden after I reload the dashboard

