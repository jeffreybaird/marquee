Feature: Series and Season Management

  Background:
    Given I am logged in as an operator with content management permissions

  Scenario: Operator creates a series
    When I create a series with a name and metadata
    Then the series is saved and appears in the content library

  Scenario: Operator creates a season within a series
    Given a series exists
    When I add a season with a name and season number
    Then the season is created and linked to that series

  Scenario: Operator edits a series
    Given a series exists
    When I edit the series name or metadata and save
    Then the series record is updated

  Scenario: Operator edits a season
    Given a season exists within a series
    When I edit the season details and save
    Then the season record is updated

  Scenario: Operator toggles series visibility
    Given a series exists
    When I toggle its visibility off
    Then viewers cannot see the series

  Scenario: Operator toggles season visibility
    Given a season exists
    When I toggle its visibility off
    Then viewers cannot see that season

  Scenario: Operator soft-deletes a series
    Given a series exists
    When I delete the series
    Then it is marked with a deleted_at timestamp
    And no longer appears to viewers

