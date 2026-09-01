Feature: Live Event Google Calendar Link

  Background:
    Given the Marquee platform is running

  Scenario: Google Calendar URL is built with correct event details
    Given a scheduled event with a title, slug, start time, and description
    When the Google Calendar URL is generated for that event and base URL
    Then the URL starts with the Google Calendar render endpoint
    And the URL includes the event title, start time, and event page URL as location

  Scenario: Google Calendar URL uses 1-hour default when no duration set
    Given a scheduled event with no estimated duration
    When the Google Calendar URL is generated
    Then the end time in the URL is 1 hour after the start time
