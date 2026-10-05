Feature: Private Wanderlust operator demo
  Visitors can explore an editable travel catalog without affecting customer organizations.

  Scenario: Reset replaces only the requesting visitor's private workspace
    When two Wanderlust visitors edit and reset separate private workspaces
    Then the reset visitor has a fresh catalog and the other visitor keeps their edits
