Feature: Operator Authentication

  Background:
    Given the Bobine platform is running

  Scenario: Operator registers with a new organization
    Given I am an unauthenticated user
    When I submit the registration form with a valid email, password, and organization name
    Then an operator account is created
    And a new organization is created with an auto-generated slug
    And a confirmation email is sent to my address
    And I am redirected to the admin dashboard

  Scenario: Operator logs in with valid credentials
    Given I have a confirmed operator account
    When I submit valid credentials at the login page
    Then a session token is created
    And I am redirected to the admin dashboard

  Scenario: Operator fails login with wrong password
    Given I have a confirmed operator account
    When I submit an incorrect password
    Then I see an invalid credentials error
    And no session is created
