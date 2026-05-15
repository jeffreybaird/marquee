Feature: Super Admin Dashboard

  Background:
    Given I am logged in as a super admin

  Scenario: Super admin views the platform dashboard
    When I navigate to /super/
    Then I see platform-level stats
    And I see links to organizations, users, analytics, and the audit log
