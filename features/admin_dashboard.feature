Feature: Admin Dashboard

  Background:
    Given I am logged in as an operator

  Scenario: Operator views the dashboard
    When I navigate to /admin/
    Then I see quick stats including subscriber count, video count, and MRR
    And I see links to all admin sections

  Scenario: Dashboard stats reflect current organization data
    Given my organization has subscribers, videos, and revenue
    When I view the dashboard
    Then the displayed stats match the current organization data

Feature: Landing Page Builder

  Background:
    Given I am logged in as an operator with content management permissions
    And I am on the landing page builder at /admin/landing

  Scenario: Operator adds a hero section
    When I add a section of type hero
    Then a hero section appears in the landing page

  Scenario: Operator adds a feature section
    When I add a section of type feature
    Then a feature section appears in the landing page

  Scenario: Operator adds a video section
    When I add a section of type video
    Then a video section appears and I can link a video to it

  Scenario: Operator adds a testimonial section
    When I add a section of type testimonial
    Then a testimonial section appears in the landing page

  Scenario: Operator adds a FAQ section
    When I add a section of type FAQ
    Then a FAQ section appears in the landing page

  Scenario: Operator adds a CTA section
    When I add a section of type CTA
    Then a CTA section appears in the landing page

  Scenario: Operator edits a landing page section
    Given a landing page section exists
    When I edit its content and save
    Then the updated content is published to the landing page

  Scenario: Operator adds a FAQ item
    Given a FAQ section exists
    When I add a question and answer pair
    Then the FAQ item appears within the FAQ section

  Scenario: Operator removes a FAQ item
    Given a FAQ section has items
    When I remove a FAQ item
    Then it is removed from the FAQ section

  Scenario: Operator reorders landing page sections
    Given the landing page has multiple sections
    When I move a section up or down
    Then the display order updates accordingly

  Scenario: Operator toggles a section visibility off
    Given a landing page section exists
    When I toggle its visibility off
    Then that section is hidden from public visitors

  Scenario: Operator toggles a section visibility on
    Given a landing page section is hidden
    When I toggle its visibility on
    Then that section appears for public visitors

  Scenario: Operator deletes a landing page section
    Given a landing page section exists
    When I delete it
    Then the section is removed from the landing page

  Scenario: Operator links an existing video to a landing page section
    Given a video section exists and videos are available
    When I open the video picker and select an existing video
    Then the video is linked to that landing page section

  Scenario: Operator uploads a new video for a landing page section
    Given a video section exists
    When I upload a new video file via the video picker
    Then the video is uploaded to Mux
    And linked to that landing page section

Feature: Organization Settings

  Background:
    Given I am logged in as an organization owner
    And I am on the organization settings page

  Scenario: Owner views Stripe Connect status
    When I view the settings page
    Then I see whether Stripe Connect is connected or pending

  Scenario: Owner initiates Stripe Connect onboarding
    Given Stripe Connect is not yet connected
    When I click to connect my Stripe account
    Then I am redirected to the Stripe OAuth flow

Feature: Super Admin Dashboard

  Background:
    Given I am logged in as a super admin

  Scenario: Super admin views the platform dashboard
    When I navigate to /super/
    Then I see platform-level stats
    And I see links to organizations, users, analytics, and the audit log
