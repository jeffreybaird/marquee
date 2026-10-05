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
    And viewers see the updated theme without a server restart

  Scenario: Operator previews a preset without applying
    When I hover over or click preview on a preset
    Then the color preview updates in the UI
    But the live viewer site is not changed until I apply

  Scenario: Operator expands preview to full screen
    Given I am on the appearance settings page
    When I click the expand preview button
    Then a full-screen overlay appears
    And the overlay renders the canonical hero carousel component
    And the CTA buttons in the overlay match the viewer site exactly

  Scenario: Operator dismisses the expanded preview
    Given the full-screen preview overlay is open
    When I click the close button on the overlay
    Then the overlay is dismissed
    And I return to the appearance editor

  Scenario: Mini preview CTA buttons match viewer CTA styles
    Given I am on the appearance settings page
    Then the primary CTA in the mini preview uses the hero-cta-primary CSS class
    And the secondary CTA in the mini preview uses the hero-cta-secondary CSS class
    And both CTAs reflect my configured accent color and text-on-accent color

  Scenario: Mini preview reuses the real viewer hero carousel and content rows
    Given I am on the appearance settings page
    Then the mini preview renders the canonical hero carousel component
    And the mini preview renders the canonical content row component
    And default hero, landscape, and portrait images populate the preview when the catalog is empty

