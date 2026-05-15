Feature: Collections Management

  Background:
    Given I am logged in as an operator with content management permissions

  Scenario: Operator creates a collection
    When I create a collection with a name
    Then the collection is saved and appears in the collections list

  Scenario: Operator adds videos to a collection
    Given a collection exists
    When I add videos to it
    Then those videos appear as collection items in the correct order

  Scenario: Operator adds a series to a collection
    Given a collection and a series exist
    When I add the series to the collection
    Then the series appears as a collection item

  Scenario: Operator reorders collection items
    Given a collection has multiple items
    When I move an item up or down
    Then the display order is updated

  Scenario: Operator removes an item from a collection
    Given a collection has items
    When I remove an item
    Then it is no longer part of that collection

  Scenario: Operator toggles collection visibility
    Given a collection exists
    When I toggle its visibility off
    Then viewers cannot see the collection on the platform

  Scenario: Operator makes a hidden collection visible
    Given a collection is hidden
    When I toggle its visibility on
    Then viewers can see the collection on the platform

  Scenario: Operator soft-deletes a collection
    Given a collection exists
    When I delete the collection
    Then it is marked with a deleted_at timestamp
    And no longer appears to viewers

