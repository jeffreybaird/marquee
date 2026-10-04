Feature: Workshop subscriber portfolio demo
  Visitors can experience personal subscriber activity without signing up.

  Scenario: Visitors retain separate progress and watchlists
    Given The Workshop subscriber demo has a playable catalog
    When two visitors start the subscriber demo
    And the first demo visitor saves an episode and watches part of it
    Then the first demo visitor can resume that episode
    And the second demo visitor has independent activity

  Scenario: Expired demo activity is cleaned up
    Given The Workshop subscriber demo has a playable catalog
    When two visitors start the subscriber demo
    And the first demo visitor session expires
    Then that demo session no longer authenticates
    And expired demo activity can be removed without removing the second visitor
