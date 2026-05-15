Feature: Organization Settings

  Background:
    Given I am logged in as an organization owner
    And I am on the organization settings page

  Scenario: Owner views Stripe Connect status
    When I view the settings page
    Then I see whether Stripe Connect is connected or pending

  Scenario: Owner initiates Stripe Connect onboarding
    Given Stripe Connect is not yet connected
    When I click to connect my Stripe account
    Then I am redirected to the Stripe OAuth flow

