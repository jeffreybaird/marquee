Feature: Hero carousel on the viewer homepage
  Viewers on a phone move through featured content by swiping, without
  relying on the arrow buttons that only make sense with a pointer.

  Scenario: Viewer swipes through the hero banner on a mobile screen
    Given an organization has multiple hero slides
    When I open the homepage as a viewer on a mobile screen
    And I swipe left on the hero banner
    Then the next hero slide is shown
    And the hero arrow buttons are hidden
