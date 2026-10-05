Feature: Platform homepage after visiting a tenant
  A remembered tenant does not replace the platform homepage.

  Scenario: Return to the platform after viewing a tenant landing page
    Given a tenant is available for a platform homepage return visit
    When I visit that tenant and then the bare platform homepage
    Then I see the platform marketing homepage

  Scenario: The platform clearly identifies itself as a portfolio project
    When I open the platform homepage on desktop and mobile
    Then the portfolio disclosure is visible above the hero on both screens
