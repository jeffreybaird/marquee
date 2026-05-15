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

