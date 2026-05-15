Feature: Operator Viewer Impersonation

  Background:
    Given I am logged in as an operator with admin or editor role

  Scenario: Operator impersonates a viewer
    Given a viewer exists in my organization
    When I choose to impersonate that viewer
    Then I browse the viewer site as that viewer
    And the impersonation session is tracked with the operator and viewer IDs

  Scenario: Operator ends viewer impersonation
    Given I am impersonating a viewer
    When I end the impersonation session
    Then I am returned to the operator dashboard
    And the viewer's session is not affected
