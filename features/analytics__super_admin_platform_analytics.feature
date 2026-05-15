Feature: Super Admin Platform Analytics

  Background:
    Given I am logged in as a super admin

  Scenario: Super admin views platform-wide overview
    When I navigate to /super/analytics
    Then I see platform-wide MRR, total organization count, and new signups over time

  Scenario: Super admin views revenue by organization
    When I view the platform analytics
    Then I see MRR broken down by organization

  Scenario: Super admin views top-performing organizations
    When I view the platform analytics
    Then I see a ranked list of top-performing organizations by subscriber count or MRR
