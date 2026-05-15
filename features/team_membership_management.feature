Feature: Team Membership Management

  Scenario: Operator with owner role views team members
    Given I am an organization owner
    When I navigate to /admin/members
    Then I see all members listed with their roles

  Scenario: Operator with admin role views team members
    Given I am an organization admin
    When I navigate to /admin/members
    Then I see all members listed with their roles

  Scenario: Owner invites a new team member
    Given I am an organization owner
    When I invite a user by email with a specified role
    Then an invitation email is sent to that address
    And when the invitation is accepted the user joins with the specified role

  Scenario: Owner removes a team member
    Given I am an organization owner
    And a member exists in my organization
    When I remove that member
    Then their membership is revoked
    And they lose access to the admin dashboard

  Scenario: Non-owner cannot manage memberships
    Given I am an organization editor
    When I attempt to manage team members
    Then I am denied access

