Feature: Organization Branding Configuration

  Background:
    Given I am logged in as an organization owner

  Scenario: Operator sets a custom domain
    Given I am on the organization settings page
    When I enter and save a custom domain
    Then the organization is accessible at that custom domain

  Scenario: Operator sets an admin accent color
    Given I am on the appearance settings page
    When I enter a custom color for the admin accent
    And save
    Then the admin dashboard reflects the custom accent color
