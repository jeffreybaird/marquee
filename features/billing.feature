Feature: Subscription Plan Management

  Background:
    Given I am logged in as an organization owner

  Scenario: Operator creates a subscription plan
    When I create a plan with a name, price, and description
    Then a Stripe product and price are created in Stripe
    And the plan is available for viewers to subscribe to

  Scenario: Operator creates a plan with a trial period
    When I create a plan and specify a trial duration
    Then new subscribers receive a trial period before being charged

  Scenario: Operator edits a subscription plan
    Given a plan exists
    When I edit the plan name or description and save
    Then the plan record is updated

  Scenario: Operator deactivates a plan
    Given an active plan exists with existing subscribers
    When I deactivate the plan
    Then no new viewers can subscribe to it
    And existing subscribers retain their access

  Scenario: Operator deletes a plan with no subscribers
    Given a plan exists with no active subscribers
    When I delete the plan
    Then it is removed from the system

Feature: Coupon Management

  Background:
    Given I am logged in as an organization owner

  Scenario: Operator creates a fixed-amount coupon
    When I create a coupon with a code and a fixed discount amount
    Then the coupon is available for viewers to apply at checkout

  Scenario: Operator creates a percentage coupon
    When I create a coupon with a code and a percentage discount
    Then the coupon reduces the plan price by that percentage at checkout

  Scenario: Viewer applies a valid coupon at checkout
    Given a coupon code exists and is active
    When a viewer enters the code during checkout
    Then the discount is applied to the subscription price

  Scenario: Viewer applies an invalid or expired coupon
    Given an invalid or deactivated coupon code
    When a viewer enters the code during checkout
    Then an error is displayed and no discount is applied

  Scenario: Operator deactivates a coupon
    Given an active coupon exists
    When I deactivate it
    Then the coupon code can no longer be applied at checkout

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
