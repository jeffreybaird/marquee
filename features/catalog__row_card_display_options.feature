Feature: Row Card Display Options

  Background:
    Given I am logged in as an operator with content management permissions
    And I am on the catalog management page

  Scenario: Operator hides details below cards in a row
    Given a catalog row exists with "Show details below card" enabled
    When I uncheck "Show details below card" for that row and save
    Then cards in that row on the viewer homepage display without the details bar

  Scenario: Operator re-enables details below cards
    Given a catalog row has details hidden
    When I check "Show details below card" for that row and save
    Then cards in that row display the details bar again

  Scenario: Operator enables title overlay on cards
    Given a catalog row has details hidden
    When I check "Overlay title on thumbnail" for that row and save
    Then cards in that row show the title text overlaid on the thumbnail

  Scenario: Title overlay option is only available when details are hidden
    Given a catalog row exists with "Show details below card" enabled
    When I view the row editor
    Then the "Overlay title on thumbnail" checkbox is not visible

  Scenario: Disabling details and enabling overlay does not affect other rows
    Given the catalog has two rows
    When I hide details and enable overlay on only one row
    Then the other row still displays the details bar and no overlay

