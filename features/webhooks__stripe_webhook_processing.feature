Feature: Stripe Webhook Processing

  Background:
    Given the Marquee platform is running
    And Stripe webhook signature verification is configured

  Scenario: Stripe sends subscription created event
    Given a viewer just completed checkout
    When Stripe POSTs a customer.subscription.created event with a valid signature
    Then the signature is verified
    And an async processing job is enqueued
    And the subscription record is created or updated for the viewer

  Scenario: Stripe sends subscription updated event
    Given a viewer has an active subscription
    When Stripe POSTs a customer.subscription.updated event
    Then the signature is verified
    And the subscription record is updated to reflect the new state

  Scenario: Stripe sends subscription deleted event
    Given a viewer has an active subscription
    When Stripe POSTs a customer.subscription.deleted event
    Then the subscription is marked as cancelled
    And the viewer loses access to gated content at period end

  Scenario: Stripe sends invoice payment succeeded event
    Given a viewer's subscription has a pending invoice
    When Stripe POSTs invoice.payment_succeeded
    Then the subscription status is confirmed as active

  Scenario: Stripe sends invoice payment failed event
    Given a viewer has an active subscription
    When Stripe POSTs invoice.payment_failed
    Then the viewer's subscription status is marked as payment_failed
    And the viewer sees a payment issue notice

  Scenario: Stripe webhook with invalid signature is rejected
    When Stripe POSTs a webhook with an invalid Stripe-Signature header
    Then the request is rejected with a 400 response
    And no processing occurs

  Scenario: Stripe Connect webhook is routed to the correct organization
    Given an event concerns a Stripe Connect account linked to an organization
    When Stripe POSTs the webhook
    Then the organization is resolved from the Connect account ID
    And processing is scoped to that organization
