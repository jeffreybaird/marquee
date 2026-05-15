Feature: Tags Management

  Background:
    Given I am logged in as an operator with content management permissions

  Scenario: Operator creates a tag
    When I create a tag with a valid name
    Then the tag is created and available to assign to videos

  Scenario: Operator creates a duplicate tag name
    Given a tag with a given name already exists
    When I try to create another tag with the same name
    Then I see a validation error
    And no duplicate tag is created

  Scenario: Operator edits a tag name
    Given a tag exists
    When I edit its name and save
    Then the tag name is updated
    And all videos with that tag reflect the updated name

  Scenario: Operator deletes a tag
    Given a tag exists
    When I delete it
    Then the tag is removed from the system
    And disassociated from all videos

  Scenario: Operator searches tags
    Given multiple tags exist
    When I type a search query in the tag search box
    Then the tag list filters to matching results
