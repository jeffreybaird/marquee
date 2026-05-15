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

