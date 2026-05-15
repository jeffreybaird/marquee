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

  Scenario: Operator adds a title logo image to a hero slide
    Given a hero slide exists
    When I enter a title logo URL for that slide
    Then the viewer hero renders the title logo image instead of plain text

  Scenario: Operator adds a channel logo to a hero slide
    Given a hero slide exists
    When I enter a channel logo URL for that slide
    Then the viewer hero renders the channel logo above the title area

  Scenario: Hero slide without logo URLs falls back to text headline
    Given a hero slide exists with no title logo or channel logo URL
    When a viewer sees the hero banner
    Then the slide renders the text title and no logo images

  Scenario: Both logo URLs are optional independently
    Given a hero slide exists
    When I set only a channel logo URL and leave the title logo URL blank
    Then the channel logo appears and the text headline is used for the title

