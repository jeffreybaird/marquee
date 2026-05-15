Feature: Operator Viewer Management

  Background:
    Given I am logged in as an operator with viewer management permissions

  Scenario: Operator views the viewer list
    When I navigate to the viewers tab in /admin/members
    Then I see a paginated list of all viewers

  Scenario: Operator searches for a viewer
    Given viewers exist in the organization
    When I type a search query in the viewer search box
    Then the viewer list filters to matching results

  Scenario: Operator suspends a viewer
    Given a viewer exists with active status
    When I suspend that viewer
    Then the viewer cannot access gated content
    And their status shows as suspended

  Scenario: Operator bans a viewer
    Given a viewer exists
    When I ban that viewer
    Then the viewer is permanently blocked from the platform
    And their status shows as banned

  Scenario: Operator reactivates a suspended viewer
    Given a viewer is suspended
    When I reactivate that viewer
    Then their status returns to active
    And they can access content again

  Scenario: Operator grants early access to a viewer
    Given a viewer does not have an active subscription
    When I grant early access to that viewer
    Then the viewer can access gated content without a paid subscription

  Scenario: Operator grants early access with an expiry date
    Given a viewer does not have an active subscription
    When I grant early access with a specific expiry date
    Then the viewer can access content until that expiry date

  Scenario: Operator revokes early access from a viewer
    Given a viewer has early access granted
    When I revoke their early access
    Then the viewer loses early access
    And must subscribe to access gated content

