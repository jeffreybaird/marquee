Feature: Safe tenant hostname rollout
  Existing studios keep working while their dedicated hostname is being prepared.
  The new address becomes canonical only after DNS and HTTPS readiness succeed.

  Scenario: A studio keeps its existing login link while provisioning is pending
    Given a studio is enrolled for hostname provisioning
    When I open its existing platform login link
    Then the platform still shows that studio login

  Scenario: A ready studio uses its dedicated hostname
    Given a studio is enrolled for hostname provisioning
    And its hostname has completed DNS and HTTPS readiness
    When I open its existing platform login link
    Then the platform redirects to its ready hostname login
