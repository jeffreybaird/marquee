Feature: Operator Organization Analytics

  Background:
    Given I am logged in as an operator
    And I am on the analytics dashboard at /admin/analytics

  Scenario: Operator views organization overview
    Then I see total subscriber count, MRR, and a content performance summary

  Scenario: Operator views subscriber growth by period
    When I select a time period of day, week, or month
    Then I see daily subscriber counts charted over that period

  Scenario: Operator views daily revenue chart
    When I select a time period
    Then I see daily revenue plotted over that period

  Scenario: Operator views content performance table
    When I view the content performance section
    Then I see a table of videos ranked by engagement metrics
    And watch count, completion rate, and average watch time

  Scenario: Operator sorts content performance table
    Given the content performance table is visible
    When I click a column header to sort
    Then the table re-orders by that metric

  Scenario: Operator paginates content performance table
    Given the content performance table has multiple pages
    When I navigate to the next page
    Then the next set of content is displayed

  Scenario: Operator views individual video analytics
    Given a video exists with watch data
    When I navigate to /admin/analytics/videos/:video_id
    Then I see watch stats, completion rate, average watch time,
    And a drop-off distribution showing where viewers stop watching

  Scenario: Operator views series analytics
    Given a series exists with watch data
    When I navigate to /admin/analytics/series/:series_id
    Then I see per-season stats, episode completion rates, and funnel data
    And next-season transition rates showing how many viewers continue

  Scenario: Operator views season analytics
    Given a season exists with watch data
    When I navigate to /admin/analytics/series/:series_id/seasons/:season_id
    Then I see per-episode completion rates and drop-off analysis

