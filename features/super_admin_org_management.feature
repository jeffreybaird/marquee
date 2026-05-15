Feature: Super Admin Organization Management

  Background:
    Given I am logged in as a super admin

  Scenario: Super admin lists all organizations
    When I navigate to /super/organizations
    Then I see all organizations with their health metrics
    And video count, subscriber count, and member count

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

