Feature: Private Wanderlust operator demo
  Visitors can explore an editable travel catalog without affecting customer organizations.

  Scenario: Reset replaces only the requesting visitor's private workspace
    When two Wanderlust visitors edit and reset separate private workspaces
    Then the reset visitor has a fresh catalog and the other visitor keeps their edits

  Scenario: Private viewer preview controls remain accessible on a narrow screen
    When a Wanderlust visitor opens private viewer preview on a narrow screen
    Then the private demo controls and viewer navigation do not overlap

  Scenario: Expanded travel catalog is offered to new and reset visitors
    When the Wanderlust catalog expands for a new and a reset visitor
    Then both private catalogs contain forty-eight clips and the approved library can add another

  Scenario: Sample members and podcasts remain local to a private workspace
    When a Wanderlust visitor manages a sample member and a local podcast
    Then the local changes persist without viewer credentials or remote podcast feeds

  Scenario: An expired demo visitor can begin a fresh workspace
    When a Wanderlust visitor returns to entry after their private session expires
    Then beginning again creates one fresh workspace and repeated entry reuses it
