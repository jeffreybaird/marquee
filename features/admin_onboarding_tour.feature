Feature: New-admin guided tour

  After finishing setup, a new operator landing on the admin dashboard is
  offered a guided walkthrough that points out each section of the dashboard —
  Content, Collections, Analytics, Settings and the rest. It launches once per
  operator, can be dismissed at any time, is replayable from a "Take a tour"
  link, and never auto-launches again once seen.

  Background:
    Given the Marquee platform is running

  Scenario: A new owner is greeted by the guided tour on first landing
    Given I am logged in as an organization owner
    And I have not yet seen the guided tour
    When I visit the admin dashboard
    Then I am greeted by the guided tour

  Scenario: Dismissing the tour records it and it won't auto-launch again
    Given I am logged in as an organization owner
    And I have not yet seen the guided tour
    When I visit the admin dashboard
    And I dismiss the guided tour
    Then the guided tour is marked complete for me
    When I visit the admin dashboard
    Then the guided tour does not launch

  Scenario: An operator who already toured is not shown it again
    Given I am logged in as an organization owner
    And I have already completed the guided tour
    When I visit the admin dashboard
    Then the guided tour does not launch

  Scenario: The tour can be replayed from the dashboard
    Given I am logged in as an organization owner
    And I have already completed the guided tour
    When I visit the admin dashboard
    And I click the take a tour link
    Then I am greeted by the guided tour
