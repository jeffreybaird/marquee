Feature: Homepage Row Management

  Background:
    Given I am logged in as an operator with content management permissions
    And I am on the catalog management page

  Scenario: Operator creates a content row
    When I create a new row with a title and variant type
    Then the row appears in the catalog list

  Scenario: Operator reorders catalog rows
    Given the catalog has multiple rows
    When I move a row up or down
    Then the display order on the viewer homepage updates accordingly
