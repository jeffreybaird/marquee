Feature: Layout Presets

  Background:
    Given I am logged in as an operator with content management permissions
    And I am on the catalog management page

  Scenario: Operator loads a catalog preset
    When I select a layout preset such as cinema, learning, or creator
    And I confirm the overwrite
    Then all existing rows are replaced with the preset configuration

  Scenario: Operator cancels a preset load
    When I select a layout preset
    But I cancel before confirming the overwrite
    Then my existing catalog rows remain unchanged
