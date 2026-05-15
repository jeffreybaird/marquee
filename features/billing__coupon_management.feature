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

