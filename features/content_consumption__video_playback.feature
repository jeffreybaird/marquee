Feature: Video Playback

  Background:
    Given I am logged in as a viewer with an active subscription

  Scenario: Viewer plays a video
    Given a ready video exists
    When I navigate to the video watch page
    Then the Mux player loads
    And playback begins

  Scenario: Viewer playback progress is tracked
    Given I am watching a video
    When I pause or stop at a certain position
    Then my playback position is saved

  Scenario: Viewer resumes a video from last position
    Given I previously watched part of a video and my position was saved
    When I open the video again
    Then playback starts from my last saved position

  Scenario: Viewer dismisses a card from continue watching
    Given I have partially watched a video that appears in my continue watching row
    When I click the dismiss button on that video's card
    Then the card is removed from my continue watching row
    And my playback progress for that video is not lost

  Scenario: Dismissed card reappears after viewer watches again
    Given I have dismissed a video from my continue watching row
    When I watch that video again
    Then the video reappears in my continue watching row

  Scenario: Dismissing a series card hides the whole series
    Given I am watching an episode in a series
    And the series appears in my continue watching row
    When I click the dismiss button on the series card
    Then the series no longer appears in my continue watching row
    And my progress in the series is not lost

  Scenario: Viewer completes a video
    Given I am watching a video
    When the video plays to completion
    Then the video is marked as completed in my watch history

  Scenario: Viewer plays a series episode
    Given a series exists with at least one season and episode
    When I navigate to the series page
    Then I see the episode list
    And I can play individual episodes

  Scenario: Viewer switches seasons within a series
    Given a series has multiple seasons
    When I select a different season
    Then the episode list updates to show episodes for that season

