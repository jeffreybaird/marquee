Feature: Tenant hostnames
  Viewers reach the correct studio using its hostname without an organization query parameter.

  Background:
    Given tenant hostname routing is configured

  Scenario: Open a studio by hostname
    When I request the studio hostname with another studio query parameter
    Then hostname routing selects the requested studio

  Scenario: Follow an existing shared-host bookmark
    When I request the old studio bookmark
    Then hostname routing redirects to the studio hostname and preserves the page

  Scenario: Reject an untrusted hostname despite a remembered studio
    When I request an unrelated hostname with a remembered studio
    Then hostname routing returns organization not found

  Scenario: Generate a portable studio login link
    When I generate a studio login URL
    Then the login URL uses the studio hostname without an organization query parameter
