Feature: New-admin setup wizard

  A new operator who has just created their service is guided through a short
  full-screen setup wizard — welcome, pick a theme, add a first video, finish.
  It appears once for owners and admins of a not-yet-onboarded organization,
  is skippable, and never reappears afterward.

  Background:
    Given the Marquee platform is running

  Scenario: A new owner is guided into setup on first landing
    Given I am logged in as an organization owner
    And my organization has not completed onboarding
    When I visit the admin dashboard
    Then I am taken to the setup wizard

  Scenario: Finishing the wizard reaches the dashboard and won't reappear
    Given I am logged in as an organization owner
    And my organization has not completed onboarding
    When I visit the admin dashboard
    And I finish the setup wizard
    Then onboarding is marked complete for my organization
    And I am not shown the setup wizard

  Scenario: An owner can skip setup
    Given I am logged in as an organization owner
    And my organization has not completed onboarding
    When I visit the admin dashboard
    And I skip the setup wizard
    Then onboarding is marked complete for my organization

  Scenario: A non-admin member is never shown the wizard
    Given I am logged in as an operator with the editor role
    And my organization has not completed onboarding
    When I visit the admin dashboard
    Then I am not shown the setup wizard

  Scenario: Onboarding state is scoped to one organization
    Given I am logged in as an organization owner
    And another organization has not completed onboarding
    When I visit the admin dashboard
    Then I am not shown the setup wizard
