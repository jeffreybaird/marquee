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

