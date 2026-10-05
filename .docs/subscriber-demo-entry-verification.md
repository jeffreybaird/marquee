# Direct subscriber demo entry verification (historical)

This automatic-GET contract is superseded by the explicit-entry landing work in
[Workshop landing verification](workshop-landing-verification.md). The results
below record the earlier implementation, not the current entry behavior.

## Historical contract

An anonymous browser's homepage GET for an organization with `subscriber_demo`
set to exactly `true` receives a private demo session and the catalog/demo bar
in its first rendered response. Existing real viewers, operators, member
previews, and impersonation retain their current behavior. Valid demo sessions
are reused, expired sessions receive a fresh identity, and another tenant's
identity cannot cross the hostname boundary.

Creation stays at the HTTP boundary, outside LiveView mounts, through the
existing subscriber-demo context. It uses existing tenant/authentication rate
limits. HEAD and prefetch requests do not create records; original HTTP method
must be preserved before `Plug.Head` normalizes it. Responses are private and
uncached. Missing demo media returns 503. Existing POST routes retain CSRF
protection. This intentionally permits allocation of anonymous, expiring demo
state on the public demo homepage GET; it does not sign users into a real
account or change content authorization.

## Security review

The independent reviewer refreshed 121 Hex and 17 Caddy advisories and reran
`npm audit`: zero known affected installed dependencies. Advisory data and
lockfiles match the previous reviewed versions; Caddy remains pinned to 2.11.6,
including the fix for GHSA-6365-7ppr-5r92. No dependency change was required.

## Workflow evidence

Test authoring, authoritative execution, implementation, and review are assigned
to separate native workflow roles. The runner established the intended failures
before implementation: 16 integration/existing demo tests had seven behavior
failures, the cold-browser test failed on the missing demo bar, and the new
Gherkin scenario failed on the same missing initial experience. A Gherkin import
dependency was corrected by the test writer before recording that behavioral
failure; the reviewer verified its assertions were unchanged.

The reviewer accepted all five contracts in
[the test hash manifest](subscriber-demo-entry-tests-sha256.json). The existing
manual-entry expectation changed only to the newly requested direct demo bar;
its POST/session/security assertions remain intact. The three source files are
recorded in [the source hash manifest](subscriber-demo-entry-source-sha256.json),
reviewed independently with no unresolved findings. Final comparison found no
drift in the three source or five test contracts. The branch audit contains
three new entries with zero ownership violations; `git diff --check` passed.

Targeted green evidence: all 16 integration/existing-demo tests passed; the cold
browser test passed in 1.2 seconds; all four subscriber-demo Gherkin scenarios
passed in 2.803 seconds. Formatting, warnings-as-errors compilation, strict
Credo, asset checks, 307 doctests and 2,681 Elixir tests, and Dialyzer passed.
Asset coverage passed across 157 tests (96.68% statements, 85.41% branches,
99.59% lines). All 20 browser tests passed in 306.2 seconds. Application
coverage passed at 78.4%, with 307 doctests and 2,681 tests and zero failures.
All required verification is complete; production deployment and fresh-browser
visual confirmation follow the reviewed local commit.
The existing user edit to
`.docs/project-guidance.md` is excluded from this work.
