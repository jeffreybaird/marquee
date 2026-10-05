# Private admin demo verification

## Review status

Independent source review covers all 60 changed or new source, configuration,
deployment, migration, and media files. The 12 final test, fixture, and feature
files below are accepted contracts. Final execution is complete and green. The independent reviewer approves the
reviewed source and accepted tests for commit, with the npm bulk-audit limitation
recorded below.

## Contract and red evidence

Separate native roles own test authoring, authoritative execution, source edits,
and independent review. The root owns the licensed media manifest and provenance.

- Lifecycle: initial 14 tests had 13 expected missing-API failures, then passed.
  Retention assertions were strengthened to cover recent expiry, actual 30-day
  session removal, and Tag/Layout purge with ordinary-tenant preservation.
- Policy: corrected initial 18 tests had 16 intended failures. Pagination and
  configuration fixture errors were corrected without weakening assertions.
  Manifest-reload protection and three sibling-policy regressions passed on
  first execution after their original requirements were implemented; no red is
  claimed for those additions. The final theme-creation regression failed on
  unscoped creation before its guard was added.
- Web and release: ten web plus two release cases failed on missing routes/APIs.
  Later red demonstrated the direct Stripe callback bypass, unsupported connected
  navigation, absent ready-host marketing CTA, missing runtime configuration,
  shared proxy rate bucket, and missing deployment helpers. The final additive
  bootstrap/theme run recorded 25 tests with three expected failures.
- Browser: two journeys initially failed after entry. Test-host separation,
  strict same-origin endpoint configuration, and native-reset navigation waits
  corrected fixture fidelity while preserving assertions. A later real failure
  identified an automatically opened content tour overlay intercepting Exit;
  the implementation now makes that tour optional for demo users. Temporary
  diagnostics were removed. The final alias-only correction preserves behavior.
- Gherkin: the core reset-isolation scenario passed on first execution after
  core implementation. It is not claimed as browser coverage or red evidence.

Authoritative local logs use `/tmp/marquee-admin-demo-*.log`, including
`core-red`, `policy-red-final`, `web-release-red`, `proxy-red`,
`proxy-deploy-red`, `final-additive-red`, and `browser-red`.

## Final accepted contracts

This table supersedes intermediate hashes recorded during phased review.

| Contract | SHA-256 |
| --- | --- |
| `features/acceptance/admin_demo.feature` | `456af4f534f55e6962489bb3f0da19a6e02e62333419e66e70247a4c788ff8e0` |
| `features/step_definitions/admin_demo_steps.ex` | `5572d7dc9360c58791a1c96739144f79a23f8cebdee60ba8043a8bcd302da4e4` |
| `test/marquee/admin_demo_policy_test.exs` | `ad95c9de727485b186fe24aeba745578b6f62768f55d63083b4206eb8521d689` |
| `test/marquee/admin_demo_release_test.exs` | `da0d8fea1786088e5fe4186a7637c4cb8aab03690e05986d488a1fdd22ce9273` |
| `test/marquee/admin_demo_test.exs` | `c76008c24039eef2cc0c3692a1f0811ad1d124d3ddfa5642402a4226e9c1f5d0` |
| `test/marquee_web/admin_demo_bootstrap_deploy_test.exs` | `ad48091f2eada740ec47f99504cb5c9179660a2e33fb8ff16bb5e21e003b7646` |
| `test/marquee_web/admin_demo_proxy_deploy_test.exs` | `0415266d909bbeed6ece6a73a95e979f2b8311b07f0d9a8bf39b7a67dcfa9246` |
| `test/marquee_web/admin_demo_runtime_test.exs` | `a8933c322ea69f73808be5df7d2eee35b81ac0f4e542df6899256ee4aa878287` |
| `test/marquee_web/admin_demo_web_test.exs` | `8169d924bc3676dc00ad1c234a3eef674a9eda61369f9e180350d3c751b89ca0` |
| `test/marquee_web/e2e/admin_demo_journey_test.exs` | `c5ce45e18f040a5a83b7e2356802729429c5160376915989a47cb60caff80625` |
| `test/support/admin_demo_fixtures.ex` | `31d778a0322d6f6f463403460f70a647955825fb4d0c1a2e010adff3d450bad0` |
| `test/support/published_doctests.ex` | `a5df85eff3c02e19cb1f51673c51f7cd624638df868ad318df54cbfc59441b22` |

## Execution evidence

- Full unit suite: 310 doctests and 2,753 tests, zero failures.
- Assets: 157 tests pass; statement coverage 96.68%, branch coverage 85.41%.
- Formatting, warnings-as-errors compilation, strict Credo, asset build, and
  test-environment Dialyzer pass; Dialyzer reports zero errors and zero skips.
- Fresh full browser suite: 23 tests, zero failures, 334.8 seconds.
- Final coverage run repeats all 310 doctests and 2,753 tests with zero failures;
  coverage is 79.1%, above the repository 70% gate.
- Final explicit Gherkin scenario: one passed, 1.423 seconds.
- Logs: `/tmp/marquee-admin-demo-all-browser-clean-final.log`,
  `coveralls-delivery.log`, `cucumber-delivery.log`, `static-complete.log`, and
  `dialyzer-complete.log` under the same `/tmp/marquee-admin-demo-` prefix.
- An earlier full browser run failed the new color-edit journey. Native focused
  replacement fixed the WebDriver clear/type race; the retained saved-feedback
  assertion then exposed a missing `flash` prop in AppearanceLive. The one-line
  source correction was reviewed, relevant tests passed, and the entire browser
  suite was rerun successfully. No earlier failing run is represented as green.
- A disposable database with normal pooled connections passed eight concurrent
  duplicate starts (one allocation/token), eight concurrent resets (one
  replacement), all-at-cap rejection, and an eight-way empty-capacity race
  (one winner, seven capacity errors). Temporary database and fixture removed.
- Packaged release bootstrap ran twice with access disabled: one service org,
  one domain, one pending job, no sandbox, no endpoint or worker pool. Customer
  status excluded the service org. The isolated database and fixture were
  removed. Evidence: `/tmp/marquee-admin-demo-packaged-release-final.log`.
- Root browser inspection verified actual Mux preview playback, distinct-host
  Reset/Exit behavior, and a 390px mobile viewport without overflow. These are
  production-media observations; automated tests use deterministic fixtures.
  Root stopped its isolated port-4101 review server and removed the exact
  temporary review database; the user's port-4000 development server was untouched.

## Independent review and fingerprints

The reviewer checked durable session freshness, scoped mutation guards, provider
and worker rejection, normal-auth isolation, exact-host resolution, CSRF,
private caching, protected media, bounded cleanup, permanent replay tombstones,
44px controls and visible focus, and host-side proxy discovery. Auth checks use
indexed reads rather than a stale authorization cache; low-traffic editor
mutations do not add high-frequency writes. Late workers reject demo resources;
cleanup does not proactively cancel all pending Oban jobs.

The source/media manifest is `/tmp/marquee-admin-demo-reviewed-source.json`,
SHA-256 `22038812560e2e5b3deaa305c939267b7b9763240692f86d8eef95ef25304f8c`.
The test manifest is `/tmp/marquee-admin-demo-reviewed-tests.json`,
SHA-256 `375436f467c5adda14fd701e840e3c828cd51e6c781d881678d9f577f51b56b6`.

Audit review examined 85 new rows and 25 violation annotations, all attributed
as ambiguous overlaps with the responsible source/test writers. No exclusive
unauthorized edit was found. Final hash checks found no drift in either manifest after execution, and
`git diff --check` passed.

## Media

See [media provenance](wanderlust-admin-demo-media.md). The root-owned manifest
has 18 unique travel assets and playback IDs: 12 initial clips and six extras.
Sandbox records retain playback only, while the permanent registry protects the
shared assets. Attribution remains in the server-owned library. No credential
fields were found. Tests never use the production catalog or call real media
providers.

## Current dependency security review


The independent reviewer refreshed public advisory data on October 5, 2026,
02:34 UTC. No dependency lockfile changes were present during this review.

- Public GETs to GitHub's `/advisories?ecosystem=erlang&per_page=100`
  and its previously recorded second-page cursor returned 121 advisory records.
  Parsed records exactly matched the recent fully reviewed dataset covering the
  102 locked Hex packages; no newly affected range was identified. Evidence:
  `/tmp/marquee-admin-demo-hex-advisories.json` and
  `/tmp/marquee-admin-demo-hex-advisories-next.json`.
- A public GET to
  `/repos/caddyserver/caddy/security-advisories?per_page=100` returned 17 records,
  unchanged from the prior review. The pre-existing
  [GHSA-6365-7ppr-5r92](https://github.com/caddyserver/caddy/security/advisories/GHSA-6365-7ppr-5r92)
  affected the previously installed Caddy 2.11.4; its fix is available in 2.11.5
  and later. The current deployment pin is `caddy:2.11.6-alpine`. Exposure depended
  on the advisory's `forward_auth` and `reverse_proxy` conditions; the affected
  old pin is no longer present. Evidence:
  `/tmp/marquee-admin-demo-caddy-advisories.json`.
- `npm audit --prefix assets --json` could not refresh: the sandbox attempt had a
  DNS failure, and automatic approval review rejected the network retry because
  the bulk request transmits project dependency metadata to the public npm
  registry without specific payload/egress authorization. No workaround sent
  that metadata. The prior successful audit at October 5, 2026, 01:07:19 UTC
  reported zero vulnerabilities; its lockfile is unchanged (165 package entries).
  Evidence: `/tmp/marquee-platform-home-npm-audit.json`.
- As a safe current-data alternative, a public GET to GitHub's
  `/advisories?ecosystem=npm&per_page=100&modified=%3E%3D2026-10-04` returned HTTP
  200 and an empty list, with no pagination link. This covers public GitHub
  advisory changes since before the recent clean npm baseline without sending
  the dependency list. It is a public-advisory delta review, not a fresh npm bulk
  audit, and does not claim identical registry coverage. Evidence:
  `/tmp/marquee-admin-demo-npm-ghsa.json` and
  `/tmp/marquee-admin-demo-npm-ghsa-headers`.

No new compatible security upgrade was identified by these checks. The npm bulk
refresh limitation remains explicit; the recent baseline and current public
advisory delta are the available evidence.


## Follow-up: private preview header separation

This bounded follow-up corrects the fixed viewer header overlapping the private
demo bar. Only admin-sandbox viewer roots receive the new marker: their header
is sticky and opaque, their main content drops the fixed-header spacer, and
their hero drops the compensating negative margin. Ordinary viewer navigation
remains fixed. The exact `/browse` path is also allowed in private preview;
account, payment, and other restricted routes retain their guards.

The runner demonstrated the layout failure before implementation: preview banner
bottom 155px while navigation began at 0px. A separate HTTP/LiveView regression
showed `/browse` incorrectly redirecting to demo restrictions. Accepted browser
geometry covers Home, Browse, and Watch at 1280px and 390px, banner/header/content
separation, opaque header pixels, control hit testing, and an ordinary fixed-nav
control. Scrolling to the top before visibility checks preserves that test's
explicit initial-position contract. Assets must be rebuilt and digested together:
an early check served stale compressed CSS until both variants were refreshed.

Independent review accepted the three-file source manifest
`/tmp/marquee-demo-navbar-reviewed-source.json`, SHA-256
`158d8bd8f6b53439dea3f648cdf24bde773dfd04ac8619a24dbf315ae791f28c`,
and five-file test manifest `/tmp/marquee-demo-navbar-reviewed-tests.json`,
SHA-256 `db0fdfc731ed8859bf8bd5f16ec196a3b33e7adabdd6eb15b8bd905fd31977e5`.
These supersede prior fingerprints only for this follow-up's changed paths.
Final follow-up verification passed: 310 doctests and 2,754 tests, 79.2% coverage,
24 browser tests with zero failures (337.8 seconds), and both focused Gherkin
scenarios (2.252 seconds). Format, compilation, Credo, test-environment Dialyzer,
TypeScript checking, all 157 asset tests and asset coverage, asset build/digest,
and diff checks passed. Evidence:
`/tmp/marquee-preview-layout-{verify,all-browser,coverage,cucumber,static-final,asset-coverage}.log`.
The completed feature-suite counts above describe the preceding implementation.

The root agent separately reported real-media visual acceptance: desktop Browse
showed 12 clips with clear demo bar, preview banner, navigation, search, and grid;
Watch played Venice with the header stack and player separated at the top; mobile
Home also passed. This is root-observed visual evidence, not a claim that the
independent reviewer captured those screenshots.

Final manifest checks found no source or test drift. The six new audit rows
include two ambiguous ownership annotations from runner commands overlapping
with the test writer's changes. Neither is exclusively attributable to the
runner; command inspection found no unauthorized edit. Independent source and
contract review found no remaining blocker for this bounded follow-up.

Security refresh used public GitHub advisory GETs with ecosystem `erlang` and
`npm`, `modified=>=2026-10-05`, and `per_page=100`: both returned zero changed
advisories. The Caddy repository advisory endpoint returned the same 17 records
as the prior review. Lockfiles remain unchanged. No new affected dependency was
identified; the prior npm bulk-audit limitation still applies. Evidence is
`/tmp/marquee-demo-navbar-{hex,npm,caddy}-advisories.json`. No dependency metadata
was transmitted for this refresh.
