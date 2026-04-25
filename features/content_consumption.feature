Feature: Content Discovery and Browsing

  Background:
    Given I am on a tenant viewer site

  Scenario: Viewer browses the homepage
    Given the organization has configured catalog rows and a hero banner
    When I navigate to the homepage
    Then I see the hero banner and content rows as configured by the operator

  Scenario: Unauthenticated viewer sees public content
    Given I am not logged in
    When I navigate to the homepage
    Then I see publicly visible content rows
    And I am prompted to log in or subscribe to access gated content

  Scenario: Viewer browses a collection
    Given a collection is visible on the platform
    When I navigate to the collection page
    Then I see the collection's title and its videos

  Scenario: Viewer filters content by tag
    Given videos with various tags exist on the homepage
    When I select a tag filter
    Then only videos with that tag are shown

  Scenario: Viewer browses all content in a row
    Given a catalog row exists with more items than fit in the default view
    When I click to view all items in that row
    Then I see the full list of content in that row

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

Feature: Queue Management

  Background:
    Given I am logged in as a viewer

  Scenario: Viewer adds a video to queue
    Given a video is available
    When I add it to my queue
    Then it appears at the end of my queue

  Scenario: Viewer adds a video to play next
    Given I have items in my queue and am currently watching
    When I add a video as "play next"
    Then that video is inserted at the front of the queue

  Scenario: Viewer removes an item from queue
    Given I have items in my queue
    When I remove one item
    Then it is deleted from the queue
    And the remaining items maintain their order

  Scenario: Viewer reorders queue items
    Given I have multiple items in my queue
    When I drag an item to a new position
    Then the queue updates to reflect the new order

  Scenario: Viewer clears the entire queue
    Given I have items in my queue
    When I clear the queue
    Then all queue items are removed

  Scenario: Viewer skips to the next item in queue
    Given I am watching a video and have items in my queue
    When I skip to the next video
    Then the next queued item begins playing

  Scenario: Viewer goes back to the previous queue item
    Given I have watched videos via the queue
    When I click "go back"
    Then the previously watched video resumes from the beginning

  Scenario: Viewer adds a collection to queue
    Given a collection exists with videos
    When I add the collection to my queue
    Then the collection's videos are appended to my queue in order

Feature: Watchlist and Favorites

  Background:
    Given I am logged in as a viewer

  Scenario: Viewer adds a video to watchlist
    Given a video is available
    When I add it to my watchlist
    Then it appears in my watchlist at /watchlist

  Scenario: Viewer adds a series to watchlist
    Given a series is available
    When I add it to my watchlist
    Then it appears in my watchlist

  Scenario: Viewer removes an item from watchlist
    Given an item is in my watchlist
    When I remove it
    Then it no longer appears in my watchlist

  Scenario: Viewer favorites a video
    Given a video is available
    When I mark it as a favorite
    Then it appears in my favorites at /favorites

  Scenario: Viewer unfavorites a video
    Given a video is in my favorites
    When I remove it from favorites
    Then it is removed from /favorites

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
