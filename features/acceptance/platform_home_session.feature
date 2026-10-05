Feature: Platform homepage after visiting a tenant
  A remembered tenant does not replace the platform homepage.

  Scenario: Return to the platform after viewing a tenant landing page
    Given a tenant is available for a platform homepage return visit
    When I visit that tenant and then the bare platform homepage
    Then I see the platform marketing homepage
