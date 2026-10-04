Feature: Public source and license access
  Visitors can find Marquee's source code and license without an account.

  Scenario: Find the source offer from the sign-in page
    Given I visit the public sign-in page for the source offer
    Then the public Marquee source and license links are visible
