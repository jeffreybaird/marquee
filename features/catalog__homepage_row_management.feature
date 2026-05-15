Feature: Homepage Row Management

  Background:
    Given I am logged in as an operator with content management permissions
    And I am on the catalog management page

  Scenario: Operator creates a content row
    When I create a new row with a title and variant type
    Then the row appears in the catalog list

  Scenario: Operator adds videos to a row
    Given a catalog row exists
    When I add videos to that row
    Then those videos appear in the row on the viewer homepage

  Scenario: Operator removes a video from a row
    Given a catalog row has videos
    When I remove a video from the row
    Then that video no longer appears in the row

  Scenario: Operator reorders catalog rows
    Given the catalog has multiple rows
    When I move a row up or down
    Then the display order on the viewer homepage updates accordingly

  Scenario: Operator toggles row visibility off
    Given a catalog row exists
    When I toggle the row visibility off
    Then viewers no longer see that row on the homepage

  Scenario: Operator toggles row visibility on
    Given a catalog row is hidden
    When I toggle its visibility on
    Then viewers see the row on the homepage

  Scenario: Operator edits a row title
    Given a catalog row exists
    When I edit the row title and save
    Then the updated title appears on the viewer homepage

  Scenario: Operator deletes a catalog row
    Given a catalog row exists
    When I delete the row
    Then it is removed from the catalog
    And viewers no longer see it

