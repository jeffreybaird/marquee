Feature: Viewer Subscription Flow

  Background:
    Given I am a registered viewer on a tenant site

  Scenario: Viewer subscribes to a plan
    Given at least one active plan is available
    When I select a plan on the subscribe page
    Then I am redirected to Stripe Checkout
    And upon successful payment my subscription becomes active
    And I gain access to gated content

  Scenario: Viewer cancels checkout before completing payment
    Given I am on the Stripe Checkout page
    When I cancel and return to the platform
    Then no subscription is created
    And I am returned to the subscribe page

  Scenario: Viewer with an active subscription manages it
    Given I have an active subscription
    When I click "Manage Subscription" from my account page
    Then I am redirected to the Stripe Customer Portal
    And I can update my payment method or cancel my subscription

  Scenario: Viewer subscription is cancelled via portal
    Given I have an active subscription
    When I cancel through the Stripe Customer Portal
    Then Stripe sends a cancellation webhook
    And my subscription status is updated to cancelled
    And I lose access to gated content at the end of the billing period

  Scenario: Viewer subscription payment fails
    Given I have an active subscription
    When Stripe reports a failed payment via webhook
    Then my account shows a payment issue notice
    And I am directed to resolve the issue

  Scenario: Viewer resolves a payment failure
    Given my subscription has a payment failure
    When I update my payment method via the Stripe portal
    And payment succeeds
    Then my subscription status returns to active
    And my access is restored

  Scenario: Unauthenticated viewer attempts to access gated content
    Given a video requires a subscription
    When an unauthenticated viewer attempts to access it
    Then they are redirected to the login or subscribe page
