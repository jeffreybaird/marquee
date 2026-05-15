Feature: Organization Audit Log

  Background:
    Given I am logged in as an organization owner or admin

  Scenario: Operator views the audit log
    When I navigate to /admin/audit-log
    Then I see a chronological trail of all actions taken in my organization
    And who acted, when, what resource changed, and from which IP address

  Scenario: Operator filters audit log by actor
    Given the audit log has entries from multiple users
    When I filter by a specific actor
    Then only entries from that user are shown

  Scenario: Operator filters audit log by action type
    Given the audit log has entries of various action types
    When I filter by action type such as create, update, or delete
    Then only entries matching that action type are shown

  Scenario: Operator filters audit log by resource type
    Given the audit log has entries for various resource types
    When I filter by resource type
    Then only entries for that resource type are shown

  Scenario: Operator expands an audit log entry
    Given the audit log has entries
    When I expand an entry
    Then I see the full diff showing exactly what fields changed

  Scenario: Operator loads more audit log entries
    Given the audit log has more entries than fit on one page
    When I click to load more
    Then additional entries are appended to the list

  Scenario: Operator exports filtered audit log as CSV
    Given I have applied filters to the audit log
    When I click export CSV
    Then a CSV file containing the filtered entries is downloaded

  Scenario: Operator audit log captures impersonation context
    Given a super admin impersonated an operator and made a change
    When I view the audit log entry for that change
    Then I can see both the impersonating user and the acted-as user

