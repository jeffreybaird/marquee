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

