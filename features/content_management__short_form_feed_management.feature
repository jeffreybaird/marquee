Feature: Short-form feed management
  Operators with content permissions curate the vertical Shorts feed at
  /admin/shorts: they switch it on, choose who can watch, and add, reorder
  and remove eligible videos. Viewer support staff can only look.

  Scenario: Editor enables the Shorts feed and chooses who can watch
    Given I am logged in as an operator with the editor role
    When I open the Shorts management page
    And I switch the Shorts feed on
    And I set Shorts access to "free_with_account"
    Then the Shorts feed is enabled with access "free_with_account"

  Scenario: Editor adds an eligible video to the Shorts feed
    Given I am logged in as an operator with the editor role
    And a ready video titled "Morning Clip" is available for Shorts
    When I open the Shorts management page
    And I add "Morning Clip" from the Shorts video picker
    Then the Shorts feed lists "Morning Clip"

  Scenario: A video that is still processing is not offered
    Given I am logged in as an operator with the editor role
    And a processing video titled "Still Encoding" is available for Shorts
    When I open the Shorts management page
    And I open the Shorts video picker
    Then "Still Encoding" is not offered in the Shorts video picker

  Scenario: Editor reorders the Shorts feed
    Given I am logged in as an operator with the editor role
    And the Shorts feed already lists "First Clip" then "Second Clip"
    When I open the Shorts management page
    And I move "Second Clip" up in the Shorts feed
    Then the Shorts feed lists "Second Clip" before "First Clip"

  Scenario: Editor removes a video from the Shorts feed
    Given I am logged in as an operator with the editor role
    And the Shorts feed already lists "First Clip" then "Second Clip"
    When I open the Shorts management page
    And I remove "First Clip" from the Shorts feed
    Then the Shorts feed no longer lists "First Clip"

  Scenario: Viewer support cannot modify the Shorts feed
    Given I am logged in as an operator with the viewer support role
    And the Shorts feed already lists "First Clip" then "Second Clip"
    When I open the Shorts management page
    Then no Shorts management controls are available
    And a forced Shorts change is refused and nothing changes

  Scenario: Another organization's videos are never offered
    Given I am logged in as an operator with the editor role
    And another organization has a ready video titled "Rival Video"
    When I open the Shorts management page
    And I open the Shorts video picker
    Then "Rival Video" is not offered in the Shorts video picker

  Scenario: A Shorts video that later fails processing is badged Unavailable
    Given I am logged in as an operator with the editor role
    And the Shorts feed already lists "First Clip" then "Second Clip"
    And the Shorts video "First Clip" has since failed processing
    When I open the Shorts management page
    Then "First Clip" is badged Unavailable in the Shorts feed
    And "Second Clip" is badged Ready in the Shorts feed

  Scenario: An empty Shorts feed shows an empty state to the operator
    Given I am logged in as an operator with the editor role
    When I open the Shorts management page
    Then the Shorts management empty state is shown
