Feature: Self-service trial

  A new operator can start a 30-day free trial with no payment info. The trial
  permits up to 5 hours of video, 10 end-user viewers, a custom theme, and a
  single admin seat — everything except a custom URL. After 30 days the org is
  soft-locked (existing content keeps playing; new publishing needs payment).

  Background:
    Given the Marquee platform is running

  Scenario: Signing up starts a trial with no payment info
    Given I am an unauthenticated user
    When I submit the registration form with a valid email and organization name
    Then my organization is on a trialing subscription
    And no payment information was collected

  Scenario: An operator on an active trial sees the trial banner
    Given I am logged in as an organization owner
    And my organization is on an active trial
    When I visit the admin dashboard
    Then I see the active trial banner

  Scenario: Viewer registration is blocked once the viewer cap is reached
    Given I am logged in as an organization owner
    And my organization is on an active trial
    And my organization already has 10 viewers
    When a new viewer tries to register on the viewer site
    Then the viewer registration is refused

  Scenario: Uploading beyond the trial's hours is blocked
    Given I am logged in as an organization owner
    And my organization is on an active trial
    And my organization already has 5 hours of ready video
    When I try to upload another video
    Then the upload is refused with a plan-limit message

  Scenario: The trial does not permit a custom URL
    Given I am logged in as an organization owner
    And my organization is on an active trial
    Then my organization is not permitted a custom domain

  Scenario: An expired trial soft-locks the operator but not viewers
    Given I am logged in as an organization owner
    And my organization's trial has expired
    When I visit the admin dashboard
    Then I see the expired trial banner
    And existing viewers can still watch published videos

  Scenario: One trial organization cannot see another's trial state
    Given I am logged in as an organization owner
    And my organization is on an active trial
    And another organization has an expired trial
    Then I do not see the expired trial banner
