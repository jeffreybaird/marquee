Feature: Live Event Listing (Viewer)

  Background:
    Given the Bobine platform is running

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

Feature: Live Event Calendar Export

  Background:
    Given the Bobine platform is running

  Scenario: Viewer downloads an ICS file for a scheduled event
    Given an organization has a scheduled event with a known slug and start time
    When a viewer requests the calendar.ics file for that event
    Then they receive a file with content-type text/calendar
    And the file has a content-disposition attachment header
    And the file contains a valid VCALENDAR with the event summary

  Scenario: Viewer downloads an ICS file for a live event
    Given an organization has a live event
    When a viewer requests the calendar.ics file for that event
    Then they receive a valid ICS file

  Scenario: ICS file uses CRLF line endings per RFC 5545
    Given an organization has a scheduled event
    When a viewer downloads the ICS file
    Then every line in the file ends with CRLF

  Scenario: ICS DTEND reflects estimated_duration_minutes
    Given a scheduled event with an estimated duration of 90 minutes starting at 10:00 UTC
    When a viewer downloads the ICS file
    Then the DTEND is 11:30 UTC on the same day

  Scenario: ICS uses 1-hour default duration when no estimate set
    Given a scheduled event with no estimated duration
    When a viewer downloads the ICS file
    Then the DTEND is 1 hour after the start time

  Scenario: Calendar ICS returns 404 for ended events
    Given an organization has an ended event
    When a viewer requests the calendar.ics file for that event
    Then they receive a 404 response

  Scenario: Calendar ICS returns 404 for canceled events
    Given an organization has a canceled event
    When a viewer requests the calendar.ics file for that event
    Then they receive a 404 response

  Scenario: Calendar ICS returns 404 for a non-existent slug
    Given an organization has no event with slug "no-such-event"
    When a viewer requests the calendar.ics file for that slug
    Then they receive a 404 response

Feature: Live Event Google Calendar Link

  Background:
    Given the Bobine platform is running

  Scenario: Google Calendar URL is built with correct event details
    Given a scheduled event with a title, slug, start time, and description
    When the Google Calendar URL is generated for that event and base URL
    Then the URL starts with the Google Calendar render endpoint
    And the URL includes the event title, start time, and event page URL as location

  Scenario: Google Calendar URL uses 1-hour default when no duration set
    Given a scheduled event with no estimated duration
    When the Google Calendar URL is generated
    Then the end time in the URL is 1 hour after the start time
