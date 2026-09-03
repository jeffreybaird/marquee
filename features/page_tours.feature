Feature: Per-page guided tours

  The first time an operator visits an admin page, they are offered a short
  walkthrough of that page, anchored to its own controls. Each page's tour is
  independent — seeing one page's tour has no effect on any other — launches
  once per operator per organization, can be dismissed at any time, is
  replayable from a "Page tour" link, and never auto-launches again once seen.

  The Content page is the first page with its own tour.

  Background:
    Given the Marquee platform is running

  Scenario: An operator is greeted by the content tour on their first visit
    Given I am logged in as an operator with the admin role
    When I am on the content page
    Then I am greeted by the content page tour

  Scenario: Dismissing the content tour records it and it won't auto-launch again
    Given I am logged in as an operator with the admin role
    When I am on the content page
    And I dismiss the page tour
    Then the content page tour is marked seen for me
    When I am on the content page
    Then the content page tour does not launch

  Scenario: An operator who already saw the content tour is not shown it again
    Given I am logged in as an operator with the admin role
    And I have already seen the content page tour
    When I am on the content page
    Then the content page tour does not launch

  Scenario: The content tour can be replayed from the page
    Given I am logged in as an operator with the admin role
    And I have already seen the content page tour
    When I am on the content page
    And I click the page tour link
    Then I am greeted by the content page tour

  Scenario: A viewer-support operator is not shown the content tour
    Given I am logged in as an operator with the viewer support role
    When I am on the content page
    Then the content page tour does not launch
    And I do not see the page tour link
