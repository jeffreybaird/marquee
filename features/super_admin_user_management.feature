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
