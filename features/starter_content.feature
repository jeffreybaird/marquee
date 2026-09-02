Feature: Starter content for new operators

  A brand-new organization is preloaded with sample guide videos, collections,
  and a varied homepage so the operator can immediately see what their platform
  looks like. The sample content is exempt from the trial's video-hours cap and
  can be removed in one click. It is scoped to the org it was seeded into, and
  only content managers may clear it.

  Background:
    Given the Marquee platform is running

  Scenario: A new organization is preloaded with sample content
    Given I am logged in as an organization owner
    When starter content is seeded for my organization
    Then my organization has sample videos, collections, and homepage rows

  Scenario: Sample content does not count against the trial's video hours
    Given I am logged in as an organization owner
    And my organization is on an active trial
    When starter content is seeded for my organization
    Then my organization can still upload another video

  Scenario: An operator clears the sample content from the dashboard
    Given I am logged in as an organization owner
    And starter content has been seeded for my organization
    When I visit the admin dashboard
    Then I see the sample content banner
    When I clear the sample content
    Then my organization has no sample content

  Scenario: Sample content is scoped to one organization
    Given I am logged in as an organization owner
    And another organization has been seeded with sample content
    Then my organization has no sample content

  Scenario: A read-only support member cannot clear sample content
    Given I am logged in as an operator with the viewer_support role
    And starter content has been seeded for my organization
    Then I am not permitted to clear sample content
