Feature: Viewer Account Management

  Background:
    Given I am logged in as a viewer

  Scenario: Viewer updates display name
    When I edit my display name and save
    Then my profile reflects the new display name

  Scenario: Viewer updates avatar
    When I upload a new avatar image and save
    Then my profile reflects the new avatar

  Scenario: Viewer updates marketing preferences
    When I toggle my marketing opt-in preference and save
    Then my marketing preference is updated

  Scenario: Viewer deletes their account
    When I confirm account deletion
    Then my viewer account and all associated data are permanently removed
    And I am logged out

