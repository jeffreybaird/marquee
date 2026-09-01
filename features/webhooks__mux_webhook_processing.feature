Feature: Mux Webhook Processing

  Background:
    Given the Marquee platform is running
    And Mux webhook signature verification is configured

  Scenario: Mux sends asset ready event
    Given a video is processing in Mux
    When Mux POSTs an asset.ready event to /webhooks/mux with a valid signature
    Then the signature is verified
    And an async processing job is enqueued
    And the video status is updated to "ready"
    And the operator sees the status change in real time without refreshing

  Scenario: Mux sends asset errored event
    Given a video is processing in Mux
    When Mux POSTs an asset.errored event with a valid signature
    Then the signature is verified
    And the video status is updated to "error"

  Scenario: Mux webhook with invalid signature is rejected
    When Mux POSTs a webhook with an invalid Mux-Signature header
    Then the request is rejected with a 400 response
    And no processing occurs

  Scenario: Mux webhook organization is resolved from passthrough metadata
    Given a Mux asset was created with organization metadata in the passthrough field
    When Mux sends a webhook for that asset
    Then the organization is resolved from the passthrough metadata
    And the processing job is scoped to the correct organization

