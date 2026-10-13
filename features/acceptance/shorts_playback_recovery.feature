Feature: Recovering Shorts playback
  Viewers should see a Retry message only while a Short cannot play.

  Scenario: Playback recovery removes the Retry overlay
    When a Short resumes playback after a source failure
    Then the playing Short has no visible Retry overlay
