Feature: Theme and Color Customization

  Background:
    Given I am logged in as an organization owner
    And I am on the appearance settings page

  Scenario: Operator selects a theme preset
    When I select a preset theme such as midnight or daybreak
    Then a preview of the theme colors is displayed
    And when I apply it the viewer site reflects the new color scheme

  Scenario: Operator applies a theme preset
    Given I have previewed a theme preset
    When I confirm and apply the preset
    Then the theme is saved
    And the viewer site immediately reflects the new theme

  Scenario: Operator overrides accent colors with custom values
    When I enter custom oklch or hex color values for accent color slots
    And save the appearance settings
    Then the CSS variables are updated
    And the viewer site uses my custom colors

  Scenario: Operator selects a display font
    When I choose a display font from the approved font list
    And save the appearance settings
    Then the viewer site loads that font for headings

  Scenario: Operator selects a body font
    When I choose a body font from the approved font list
    And save the appearance settings
    Then the viewer site loads that font for body text

  Scenario: Theme change propagates across cluster
    Given I have saved a new theme
    When the save completes
    Then a cache invalidation event is broadcast via PubSub
    And all Fly cluster nodes reflect the new theme
    And viewers see the updated theme without a server restart

  Scenario: Operator previews a preset without applying
    When I hover over or click preview on a preset
    Then the color preview updates in the UI
    But the live viewer site is not changed until I apply

Feature: Organization Branding Configuration

  Background:
    Given I am logged in as an organization owner

  Scenario: Operator sets a custom domain
    Given I am on the organization settings page
    When I enter and save a custom domain
    Then the organization is accessible at that custom domain

  Scenario: Operator sets an admin accent color
    Given I am on the appearance settings page
    When I enter a custom color for the admin accent
    And save
    Then the admin dashboard reflects the custom accent color
