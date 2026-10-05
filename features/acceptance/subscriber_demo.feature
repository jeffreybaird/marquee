Feature: Workshop subscriber portfolio demo
  Visitors can experience personal subscriber activity without signing up.

  Scenario: A fresh visitor previews the landing page and explicitly begins the subscriber demo
    Given The Workshop subscriber demo has a playable catalog
    When a fresh browser opens the Workshop homepage
    And the visitor chooses Begin demo from the themed landing page
    Then the Workshop catalog opens with a private demo session

  Scenario: Visitors discover featured Workshop footage without explanatory catalog text
    Given The Workshop subscriber demo has a playable catalog
    Then the Workshop hero offers three distinct featured videos
    And the Workshop catalog has no managed subscriber explanation row

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
