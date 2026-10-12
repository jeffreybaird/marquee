Feature: Short-form vertical feed
  Viewers browse an operator-curated vertical feed of short clips at /shorts.
  The organization's Shorts access level decides who can play every clip in
  the feed; a locked clip never exposes its playback id.

  Scenario: Viewer discovers Shorts from the navigation
    Given an organization whose Shorts feed is enabled with access "public"
    And the Shorts feed contains 2 ready clips
    When a signed-out visitor opens the browse page of the Shorts organization
    Then the Shorts navigation link is visible
    When the visitor opens the Shorts feed
    Then every Shorts clip is playable

  Scenario: A disabled Shorts feed is hidden
    Given an organization whose Shorts feed is disabled
    When a signed-out visitor opens the browse page of the Shorts organization
    Then the Shorts navigation link is not visible
    And opening the Shorts feed sends the visitor to the home page

  Scenario: An enabled feed without clips shows an empty state
    Given an organization whose Shorts feed is enabled with access "public"
    When the visitor opens the Shorts feed
    Then the Shorts empty state is shown

  Scenario: Viewer loads more clips and reaches the end of the feed
    Given an organization whose Shorts feed is enabled with access "public"
    And the Shorts feed contains 10 ready clips
    When the visitor opens the Shorts feed
    Then 8 Shorts clips are listed
    When the visitor nears the end of the loaded Shorts clips
    Then 10 Shorts clips are listed
    And the end of the Shorts feed is shown

  Scenario: Signed-out visitor sees locked clips in a subscribers-only feed
    Given an organization whose Shorts feed is enabled with access "subscribers_only"
    And the Shorts feed contains 2 ready clips
    When the visitor opens the Shorts feed
    Then every Shorts clip is locked with a call to action to "/login"
    And no Shorts playback id or Mux image is exposed

  Scenario: Signed-out visitor plays clips in a public feed
    Given an organization whose Shorts feed is enabled with access "public"
    And the Shorts feed contains 2 ready clips with video visibility "subscribers_only"
    When the visitor opens the Shorts feed
    Then every Shorts clip is playable

  Scenario: Subscriber plays clips in a subscribers-only feed
    Given an organization whose Shorts feed is enabled with access "subscribers_only"
    And the Shorts feed contains 2 ready clips
    And a Shorts viewer with subscription status "active" is signed in
    When the visitor opens the Shorts feed
    Then every Shorts clip is playable

  Scenario: Viewer with complimentary access plays clips in a subscribers-only feed
    Given an organization whose Shorts feed is enabled with access "subscribers_only"
    And the Shorts feed contains 2 ready clips
    And a Shorts viewer granted complimentary access is signed in
    When the visitor opens the Shorts feed
    Then every Shorts clip is playable

  Scenario: Past-due viewer is asked to fix their payment in a subscribers-only feed
    Given an organization whose Shorts feed is enabled with access "subscribers_only"
    And the Shorts feed contains 2 ready clips
    And a Shorts viewer with subscription status "past_due" is signed in
    When the visitor opens the Shorts feed
    Then every Shorts clip is locked with a call to action to "/account/payment-issue"
    And no Shorts playback id or Mux image is exposed

  Scenario: Past-due viewer plays clips in a free-with-account feed
    Given an organization whose Shorts feed is enabled with access "free_with_account"
    And the Shorts feed contains 2 ready clips
    And a Shorts viewer with subscription status "past_due" is signed in
    When the visitor opens the Shorts feed
    Then every Shorts clip is playable

  Scenario: Subscriber demo viewer sees only demo clips
    Given an organization whose Shorts feed is enabled with access "subscribers_only"
    And the Shorts feed contains 2 ready clips
    And only the first Shorts clip belongs to the subscriber demo catalog
    And a subscriber demo viewer of the Shorts organization is signed in
    When the visitor opens the Shorts feed
    Then only the first Shorts clip is listed

  Scenario: Viewer favorites a clip
    Given an organization whose Shorts feed is enabled with access "public"
    And the Shorts feed contains 2 ready clips
    And a Shorts viewer with subscription status "active" is signed in
    When the visitor opens the Shorts feed
    And the viewer favorites the first Shorts clip
    Then the first Shorts clip is saved as a favorite

  Scenario: Another organization's clips never appear
    Given an organization whose Shorts feed is enabled with access "public"
    And the Shorts feed contains 2 ready clips
    And another organization has a Shorts clip titled "Rival Short"
    When the visitor opens the Shorts feed
    Then the Shorts feed does not include "Rival Short"
