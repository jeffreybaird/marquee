Feature: Live Event Listing (Viewer)

  Background:
    Given the Marquee platform is running

  Scenario: Viewer sees live, upcoming, and past events grouped by status
    Given an organization has a live event, a scheduled event, and an ended event
    When a viewer visits the events page for that organization
    Then they see the live event in the live-now section
    And they see the scheduled event in the upcoming section
    And they see the ended event in the past section

  Scenario: Live-now section shows a muted video preview when a playback ID exists
    Given an organization has a live event with a Mux playback ID
    When a viewer visits the events page
    Then the live event card embeds a muted autoplay video preview

  Scenario: Live-now card falls back to cover image when no playback ID
    Given an organization has a live event with a cover image but no playback ID
    When a viewer visits the events page
    Then the live event card displays the cover image instead of a video preview

  Scenario: Draft events are hidden from viewers
    Given an organization has a draft event
    When a viewer visits the events page
    Then the draft event is not visible

  Scenario: Empty state renders when no events exist
    Given an organization has no events
    When a viewer visits the events page
    Then they see the empty state indicator

  Scenario: Unauthenticated viewer can browse events
    Given an organization has a scheduled event
    When an unauthenticated visitor views the events page
    Then the page renders successfully without requiring login

  Scenario: Authenticated operator can view their org events page
    Given an operator is logged in to their organization
    When they visit the events page
    Then the page renders successfully

