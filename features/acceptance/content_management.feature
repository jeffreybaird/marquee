Feature: Video and Tag Management

  Background:
    Given I am logged in as an operator with content management permissions

  Scenario: Operator edits video metadata
    Given a video exists in the content library
    When I edit the title or description and save
    Then the video record is updated with the new metadata

  Scenario: Operator soft-deletes a video
    Given a video exists in the content library
    When I delete the video
    Then the video is marked with a deleted_at timestamp
    And it no longer appears in content listings
    But it can be restored

  Scenario: Operator creates a tag
    When I create a tag with a valid name
    Then the tag is created and available to assign to videos
