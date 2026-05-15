Feature: Stripe Connect Onboarding

  Background:
    Given I am logged in as an organization owner
    And my organization is not yet connected to Stripe

  Scenario: Operator initiates Stripe Connect onboarding
    When I click to connect my Stripe account
    Then I am redirected to the Stripe OAuth flow

  Scenario: Operator completes Stripe Connect onboarding
    Given I have completed the Stripe OAuth flow
    When Stripe redirects me back to the platform
    Then my organization is linked to a Stripe Connect account
    And the Stripe Connect status shows as complete
    And I can receive viewer subscription payments

  Scenario: Operator returns to Stripe Connect onboarding after interruption
    Given I started but did not complete Stripe Connect onboarding
    When I return via the Stripe refresh callback
    Then I am redirected to continue onboarding

