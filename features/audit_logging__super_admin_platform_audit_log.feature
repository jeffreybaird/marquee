Feature: Super Admin Platform Audit Log

  Background:
    Given I am logged in as a super admin

  Scenario: Super admin views platform-wide audit log
    When I navigate to /super/audit-log
    Then I see audit events across all organizations

  Scenario: Super admin filters platform audit log by organization
    Given the platform audit log has entries from multiple organizations
    When I filter by a specific organization
    Then only entries from that organization are shown

  Scenario: Super admin views super admin action in audit log
    Given a super admin action such as granting super admin access occurred
    When I view the platform audit log
    Then that action appears as an audit entry with the super admin as actor
