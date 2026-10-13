Feature: Portrait Shorts in demonstration catalogs
  Demo visitors can explore licensed vertical footage without changing other tenants.

  Scenario: Workshop provisions a playable portrait feed without converting episodes
    When a Workshop demo is provisioned with reviewed portrait Shorts
    Then the demo Shorts are curated separately from the longform episodes

  Scenario: Existing demo curation survives provisioning again
    When an operator disables and curates a provisioned demo Shorts feed
    Then provisioning again preserves the disabled setting and curated feed

  Scenario: Private operator manages and previews portrait Shorts
    When a private demo visitor curates Shorts and opens viewer preview
    Then the private viewer preview exposes the approved portrait playback
