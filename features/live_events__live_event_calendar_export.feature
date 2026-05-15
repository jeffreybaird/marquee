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

