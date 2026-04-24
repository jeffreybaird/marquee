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

Feature: Collections Management

  Background:
    Given I am logged in as an operator with content management permissions

  Scenario: Operator creates a collection
    When I create a collection with a name
    Then the collection is saved and appears in the collections list

  Scenario: Operator adds videos to a collection
    Given a collection exists
    When I add videos to it
    Then those videos appear as collection items in the correct order

  Scenario: Operator adds a series to a collection
    Given a collection and a series exist
    When I add the series to the collection
    Then the series appears as a collection item

  Scenario: Operator reorders collection items
    Given a collection has multiple items
    When I move an item up or down
    Then the display order is updated

  Scenario: Operator removes an item from a collection
    Given a collection has items
    When I remove an item
    Then it is no longer part of that collection

  Scenario: Operator toggles collection visibility
    Given a collection exists
    When I toggle its visibility off
    Then viewers cannot see the collection on the platform

  Scenario: Operator makes a hidden collection visible
    Given a collection is hidden
    When I toggle its visibility on
    Then viewers can see the collection on the platform

  Scenario: Operator soft-deletes a collection
    Given a collection exists
    When I delete the collection
    Then it is marked with a deleted_at timestamp
    And no longer appears to viewers

Feature: Series and Season Management

  Background:
    Given I am logged in as an operator with content management permissions

  Scenario: Operator creates a series
    When I create a series with a name and metadata
    Then the series is saved and appears in the content library

  Scenario: Operator creates a season within a series
    Given a series exists
    When I add a season with a name and season number
    Then the season is created and linked to that series

  Scenario: Operator edits a series
    Given a series exists
    When I edit the series name or metadata and save
    Then the series record is updated

  Scenario: Operator edits a season
    Given a season exists within a series
    When I edit the season details and save
    Then the season record is updated

  Scenario: Operator toggles series visibility
    Given a series exists
    When I toggle its visibility off
    Then viewers cannot see the series

  Scenario: Operator toggles season visibility
    Given a season exists
    When I toggle its visibility off
    Then viewers cannot see that season

  Scenario: Operator soft-deletes a series
    Given a series exists
    When I delete the series
    Then it is marked with a deleted_at timestamp
    And no longer appears to viewers

Feature: Tags Management

  Background:
    Given I am logged in as an operator with content management permissions

  Scenario: Operator creates a tag
    When I create a tag with a valid name
    Then the tag is created and available to assign to videos

  Scenario: Operator creates a duplicate tag name
    Given a tag with a given name already exists
    When I try to create another tag with the same name
    Then I see a validation error
    And no duplicate tag is created

  Scenario: Operator edits a tag name
    Given a tag exists
    When I edit its name and save
    Then the tag name is updated
    And all videos with that tag reflect the updated name

  Scenario: Operator deletes a tag
    Given a tag exists
    When I delete it
    Then the tag is removed from the system
    And disassociated from all videos

  Scenario: Operator searches tags
    Given multiple tags exist
    When I type a search query in the tag search box
    Then the tag list filters to matching results
