Feature: Premium Podcast Shows

  Premium podcasts let an operator publish audio that is gated behind a
  viewer subscription. Subscribers receive a tokenized RSS URL they paste
  into their podcast app; if their access changes, the URL stops working.

  Background:
    Given the Bobine platform is running

  Scenario: Operator creates a direct-upload podcast show
    Given I am logged in as an operator with content management permissions
    When I create a podcast show with a slug and the any-active access mode
    Then the show appears in the operator's podcasts list
    And the show is org-scoped to my organization

  Scenario: Operator restricts a show to specific subscription tiers
    Given I am logged in as an operator with content management permissions
    And a paid plan exists in the organization
    When I create a podcast show that allows only that plan's subscribers
    Then a subscriber on that plan can access the show
    But a subscriber on a different plan cannot access the show

  Scenario: Subscriber's tokenized feed serves RSS
    Given a published podcast show exists with a ready episode
    And a subscriber has an active feed token for the show
    When the subscriber's app fetches the feed URL
    Then the feed responds with iTunes-namespaced RSS XML
    And the response includes the episode's enclosure URL

  Scenario: Revoked feed token stops serving
    Given a published podcast show exists with a ready episode
    And a subscriber has an active feed token for the show
    When the operator revokes the token
    Then the feed URL no longer serves audio for that subscriber

  Scenario: Subscriber regenerates their feed URL
    Given a published podcast show exists with a ready episode
    And a subscriber has an active feed token for the show
    When the subscriber regenerates their feed URL
    Then a fresh token is issued
    And the previous URL is revoked

  Scenario: One organization cannot see another organization's shows
    Given two organizations each own a podcast show
    Then operator A only sees their own show in the podcasts list
    And operator B only sees their own show in the podcasts list

  Scenario: Mux audio webhook publishes a draft episode
    Given a draft episode exists waiting on Mux processing
    When Mux signals that the audio asset is ready
    Then the episode status becomes published
    And its mux_playback_id is set
