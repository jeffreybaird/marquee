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

