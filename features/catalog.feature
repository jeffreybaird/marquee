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

Feature: Hero Banner Management

  Background:
    Given I am logged in as an operator with content management permissions
    And I am on the catalog management page

  Scenario: Operator creates a hero slide
    When I add a hero slide with a linked video and display metadata
    Then the slide appears in the hero banner rotation on the viewer homepage

  Scenario: Operator uploads a custom hero banner image
    Given a hero slide exists
    When I upload a banner image for that slide
    Then the image displays as the slide background

  Scenario: Operator reorders hero slides
    Given the hero has multiple slides
    When I reorder the slides
    Then they rotate in the new order for viewers

  Scenario: Operator sets the hero auto-advance interval
    Given the hero banner is configured
    When I set an auto-advance interval in milliseconds
    Then slides advance at that pace on the viewer homepage

  Scenario: Operator toggles hero visibility
    Given the hero banner is visible
    When I toggle hero visibility off
    Then the hero banner is hidden from viewers

  Scenario: Operator deletes a hero slide
    Given a hero slide exists
    When I delete the slide
    Then it is removed from the hero rotation

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
