# Platform homepage session isolation

## Contract and cause

The bare configured platform homepage must render platform marketing for an
anonymous or viewer-only browser, even if it previously visited a tenant on
that host. An explicit `?org=` or supported organization header still selects
the tenant. Tenant hostnames remain authoritative. Operator redirects, authorized
preview/impersonation, and non-root legacy tenant navigation retain their current
behavior.

The bug had two layers: HTTP resolution reused the remembered organization slug
or viewer token on the platform homepage, and LiveView could restore that
organization from the session while ignoring the no-organization marker in
configured hostname mode. The fix clears only the passive organization bridge
on a bare platform homepage request and respects that marker on the platform
LiveView. Viewer credentials are retained; tenant hostnames ignore a stale
platform marker.

## Workflow

Separate native roles own tests, authoritative execution, source changes, and
independent review. Before implementation, the runner recorded seven integration
tests with four expected failures, one browser test failing on absent platform
marketing after a tenant visit, and one Gherkin scenario failing on the same
behavior. Three integration guard cases already passed. The four new contracts were accepted before implementation. A full-suite run
then exposed two older tests that explicitly expected the removed behavior:
bare platform home restoring or redirecting to the viewer's tenant. The test
writer revised those expectations to assert platform marketing, cleared tenant
context, and a retained valid viewer token on the returned connection. Explicit
tenant access coverage remained unchanged. The reviewer renewed acceptance;
all six contracts are recorded in [the test manifest](platform-home-session-tests-sha256.json).

The reviewer refreshed 121 Hex and 17 Caddy advisories and ran `npm audit`.
No known installed dependency was affected. Current advisory records and locks
match the prior reviewed versions; Caddy 2.11.6 retains the required security fix.

The two-file implementation passed independent review. Its frozen bytes are
recorded in [the source manifest](platform-home-session-source-sha256.json).
All accepted test hashes match. The audit contains four new entries and no
ownership violations; `git diff --check` passed.

Targeted green: seven integration tests and the browser regression passed
(the browser run took 1.3 seconds), as did the new Gherkin scenario. After the
two legacy contract revisions, all 88 focused tests passed. The full unit and
coverage run passed 307 doctests and 2,688 tests with zero failures and 78.4%
coverage. Formatting, warnings-as-errors compilation, strict Credo, Dialyzer,
and asset checks/coverage passed (157 asset tests).

All 21 browser tests passed in 307.7 seconds. All required verification is
complete, including the full unit/coverage run and remaining checks after the
authorized legacy-test revisions. Final hashes remained unchanged and diff
checks passed. Production deployment and confirmation with a previously used
browser session follow this reviewed local commit.
