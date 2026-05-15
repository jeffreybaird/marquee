Feature: Video Upload and Management

  Background:
    Given I am logged in as an operator with content management permissions

  Scenario: Operator uploads a video
    When I select one or more video files and submit the upload form
    Then the files are uploaded directly to Mux
    And I see real-time upload progress for each file
    And video records are created with status "processing"

  Scenario: Video finishes processing in Mux
    Given a video was uploaded and is processing in Mux
    When Mux signals the asset is ready via webhook
    Then the video status updates to "ready"
    And the updated status is reflected in the content list without a page refresh

  Scenario: Video encounters an error during processing
    Given a video was uploaded and is processing in Mux
    When Mux signals an asset error via webhook
    Then the video status updates to "error"
    And the operator can see the error state in the content list

  Scenario: Operator edits video metadata
    Given a video exists in the content library
    When I edit the title or description and save
    Then the video record is updated with the new metadata

  Scenario: Operator uploads a video thumbnail
    Given a video exists in the content library
    When I upload a thumbnail image for that video
    Then the thumbnail is stored and associated with the video

  Scenario: Operator uploads a portrait thumbnail for a video
    Given a video exists in the content library
    When I upload a portrait thumbnail image for that video
    Then the portrait thumbnail is stored and used for poster-style card displays

  Scenario: Operator uploads a landscape thumbnail for a video
    Given a video exists in the content library
    When I upload a landscape thumbnail image for that video
    Then the landscape thumbnail is stored and used for episode and hero card displays

  Scenario: Video without uploaded thumbnails falls back to Mux smart-cropped URL
    Given a video exists with no portrait or landscape thumbnail uploaded
    When the video is displayed on the viewer site
    Then the player uses the Mux-generated thumbnail at the appropriate aspect dimensions

  Scenario: Uploading a landscape thumbnail does not overwrite the portrait thumbnail
    Given a video exists with both a portrait and a landscape thumbnail
    When I upload a new landscape thumbnail
    Then the portrait thumbnail remains unchanged

  Scenario: Operator soft-deletes a video
    Given a video exists in the content library
    When I delete the video
    Then the video is marked with a deleted_at timestamp
    And it no longer appears in content listings
    But it can be restored

  Scenario: Operator restores a soft-deleted video
    Given a video has been soft-deleted
    When I restore the video
    Then it reappears in the content library

  Scenario: Operator adds a tag to a video
    Given a video exists and tags are available
    When I add a tag to the video via the tag picker
    Then the tag is associated with that video

  Scenario: Operator creates and applies a new tag to a video
    Given a video exists
    When I create a new tag and apply it to the video
    Then the tag is created in the system
    And immediately associated with that video

  Scenario: Operator removes a tag from a video
    Given a video has an associated tag
    When I remove the tag from the video
    Then the tag is disassociated from that video

  Scenario: Operator searches videos
    Given videos exist in the content library
    When I type a search query in the search box
    Then the video list filters in real time to matching results

  Scenario: Operator paginates the video list
    Given more than one page of videos exists
    When I navigate to the next page
    Then the next set of videos is displayed

