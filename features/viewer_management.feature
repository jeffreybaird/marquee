Feature: Viewer Registration and Login

  Background:
    Given the tenant site is accessible

  Scenario: Viewer registers with email and password
    Given I am an unauthenticated user on the tenant site
    When I submit the registration form with a valid email and password
    Then a viewer account is created for my email
    And I am logged in

  Scenario: Viewer registers with email only (magic link)
    Given I am an unauthenticated user on the tenant site
    When I submit only my email address on the registration form
    Then a viewer account is created
    And a magic link is sent to my email

  Scenario: Viewer logs in via magic link
    Given I have a viewer account
    When I enter my email on the login page
    Then a magic link email is sent to me
    And clicking that link creates a session without requiring a password

  Scenario: Viewer logs in with email and password
    Given I have a viewer account with a password set
    When I submit valid credentials on the login page
    Then I am logged in

  Scenario: Viewer uses an expired magic link
    Given a magic link token that has expired
    When I click the expired magic link
    Then I see an error indicating the link is invalid or expired
    And no session is created

  Scenario: Viewer logs out
    Given I am logged in as a viewer
    When I log out
    Then my session is invalidated
    And I am redirected to the login page

Feature: Viewer Account Management

  Background:
    Given I am logged in as a viewer

  Scenario: Viewer updates display name
    When I edit my display name and save
    Then my profile reflects the new display name

  Scenario: Viewer updates avatar
    When I upload a new avatar image and save
    Then my profile reflects the new avatar

  Scenario: Viewer updates marketing preferences
    When I toggle my marketing opt-in preference and save
    Then my marketing preference is updated

  Scenario: Viewer deletes their account
    When I confirm account deletion
    Then my viewer account and all associated data are permanently removed
    And I am logged out

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

Feature: Operator Viewer Impersonation

  Background:
    Given I am logged in as an operator with admin or editor role

  Scenario: Operator impersonates a viewer
    Given a viewer exists in my organization
    When I choose to impersonate that viewer
    Then I browse the viewer site as that viewer
    And the impersonation session is tracked with the operator and viewer IDs

  Scenario: Operator ends viewer impersonation
    Given I am impersonating a viewer
    When I end the impersonation session
    Then I am returned to the operator dashboard
    And the viewer's session is not affected
