Feature: Watch History

  Background:
    Given I am logged in as a viewer

  Scenario: Viewer views watch history
    Given I have watched videos in the past
    When I navigate to /history
    Then I see a chronological list of videos I have watched

  Scenario: Viewer loads more history
    Given I have a long watch history spanning more than one page
    When I reach the bottom of the history list
    Then more history items are loaded

  Scenario: Viewer resumes from watch history
    Given a video appears in my watch history with a saved position
    When I click on it from history
    Then playback resumes from my last saved position
