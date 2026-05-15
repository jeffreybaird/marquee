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

