Feature: Operator Authentication

  Background:
    Given the Marquee platform is running

  Scenario: Operator registers and confirms a new organization via magic link
    Given I am an unauthenticated user
    When I submit the registration form with a valid email and organization name
    Then I see instructions to confirm my account
    And an unconfirmed operator account exists for my email
    And my organization has an auto-generated slug derived from its name
    When I open the magic link I received
    And I choose to stay logged in
    Then I am on the admin dashboard for my new organization

  Scenario: Operator logs in with email and password
    Given I have a confirmed operator account with a password
    When I submit my email and password on the login page
    Then I am on the admin dashboard

  Scenario: Operator fails login with wrong password
    Given I have a confirmed operator account with a password
    When I submit my email and an incorrect password on the login page
    Then I see "Invalid email or password"
    And I remain on the login page

  Scenario: Operator requests a magic link to log in
    Given I have a confirmed operator account
    When I submit only my email on the login page
    Then I see instructions that a log-in link has been sent

  Scenario: Operator logs out
    Given I am logged in as an operator
    When I log out
    Then I see "Logged out successfully"
    And I am on the log-in page

  # --- Scenarios below require UI or infrastructure not yet explored ---
  # TODO: rewrite once the flow is verified in the running app.
  #
  # Scenario: Operator resets forgotten password
  # Scenario: Sensitive operation requires re-authentication (sudo)
  # Scenario: Operator changes email address
  # Scenario: Operator changes password
