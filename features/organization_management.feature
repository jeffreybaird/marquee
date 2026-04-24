Feature: Super Admin Organization Management

  Background:
    Given I am logged in as a super admin

  Scenario: Super admin lists all organizations
    When I navigate to /super/organizations
    Then I see all organizations with their health metrics
    Including video count, subscriber count, and member count

  Scenario: Super admin creates a new organization
    When I submit the new organization form with a name and owner email
    Then the organization is created with an auto-generated slug
    And an owner account is provisioned for the specified email

  Scenario: Super admin edits an organization
    Given an organization exists
    When I edit the organization's name, slug, or custom domain and save
    Then the organization record is updated

  Scenario: Super admin soft-deletes an organization
    Given an organization exists
    When I delete the organization
    Then the organization is marked with a deleted_at timestamp
    And it no longer appears in normal organization listings

  Scenario: Super admin restores a deleted organization
    Given a soft-deleted organization exists
    When I restore the organization
    Then it reappears in organization listings
    And its data is intact

  Scenario: Super admin impersonates an operator
    Given an organization has at least one operator member
    When I choose to impersonate an operator in that organization
    Then I get an operator session scoped to that organization
    And my original super admin session is preserved for return

  Scenario: Super admin ends impersonation
    Given I am impersonating an operator
    When I end the impersonation
    Then I am returned to my super admin session

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

Feature: Super Admin User Management

  Scenario: Super admin views all platform users
    Given I am logged in as a super admin
    When I navigate to /super/users
    Then I see all platform users

  Scenario: Super admin grants super admin access
    Given I am a super admin viewing a user
    When I promote that user to super admin
    Then that user gains platform-level access
    And the promotion is recorded in the audit log

  Scenario: Super admin revokes super admin access
    Given a user has super admin access
    When I revoke their super admin flag
    Then that user loses platform-level access
    And the revocation is recorded in the audit log
