# Workshop landing and explicit entry verification

## Contract and workflow

Anonymous subscriber-demo homepage GET, HEAD, prefetch, and LiveView mounts render
landing content without creating viewers, tokens, or landing-section records.
Begin demo is an explicit CSRF-protected POST. Existing POST authentication limits
remain intact; valid returning sessions continue to the catalog, while expired
sessions return to the landing page until explicit restart. Ordinary viewer,
operator, member-preview, and private admin-demo behavior remains separate.

The landing uses existing section and theme infrastructure, approved same-tenant
catalog imagery, and configured ordering/visibility. An explicit image wins over
a fallback, and resolved fallback data never overwrites stored configuration.
The landing-only seed is scoped and idempotent, preserving any existing sections,
including a configuration containing only hidden sections. It does not run the
broader production demo seeder.

The runner recorded ten entry tests with five intended failures, four landing
tests with four intended failures after correcting a fixture API call, one
browser failure on missing landing, and four Gherkin scenarios with one expected
failure on the same entry change. Logs:
`/tmp/marquee-workshop-{entry-red,landing-final-red,browser-red,cucumber-red}.log`.
The existing direct-entry expectation and browser/Gherkin journey were explicitly
revised for the requested behavior while retaining session, navigation, and
engagement assertions.

Accepted seven-file test manifest:
`/tmp/marquee-workshop-landing-reviewed-tests.json`, SHA-256
`469228a1051e2f52eceb571525ab03321943edb7b84df86dbb7999242c8cc0c6`.
The later UI contract preserves a configured secondary CTA beside Begin demo and
hides anonymous landing favorite/watchlist/queue controls while retaining those
actions for an authenticated catalog viewer. Each exposed an independent genuine
failure before its fix. Logs: `/tmp/marquee-workshop-cta-red-retry.log` and
`/tmp/marquee-workshop-cta-final-red.log`.

The initial contrast regression passed, but independent review found that its Theme
accent was overridden by the Organization accent token. That run does not prove
production warm-gold contrast. The corrected fixture asserts the actual organization gold and failed at a
measured 2.9224:1 against the required 4.5:1. Evidence:
`/tmp/marquee-workshop-actual-gold-red.log`. The scoped contrast fix passed the faithful normal/hover regression. The browser also exposed loss of organization selection after
explicit entry on the platform host. The controller preserves the query selector
on that host; its narrow test required correcting the fixture host to the configured
platform host. The original browser failure is the behavioral red evidence.
Root independently accepted the real-media landing at desktop 1280px and mobile
390px: warm composition, dark text on the gold CTA, anonymous action controls
absent, and manual Begin demo/sign-out working. Root captured
`workshop-landing-desktop.jpg` and `workshop-landing-mobile.jpg` in the task's
visualizations directory. The blank capture is a browser-capture artifact and is
not acceptance evidence. Final execution evidence follows.

## Independent source review

Nine source files, including the new untracked landing composer, are fingerprinted
in `/tmp/marquee-workshop-landing-reviewed-source.json`, SHA-256
`df28bb1ad6e7f997217705a9618ea4e4ee3bafb2706ada22e5bc67626a33b013`.
The seven accepted test hashes still match. The reviewed implementation removes
GET allocation, keeps POST CSRF/rate enforcement, preserves explicit platform
organization selection after entry, and uses scoped approved media for fallback
without persisting fallback data. Seeding locks the organization and preserves
all existing sections, including hidden-only configurations. Configured secondary
CTA text/link remains available. Anonymous landing card actions are hidden via an
opt-in presentation flag; ordinary authenticated controls retain their default.

The contrast correction is limited to this landing's Begin demo foreground and
hover opacity. Its tested guarantee concerns the Workshop warm-gold/dark palette;
it is not a general automatic contrast guarantee for arbitrary tenant palettes.

The current audit delta contains 40 records, all marked ambiguous because of
concurrent activity. Flagged commands were inspected as read/check commands or
owner-scoped format operations; no exclusive role-ownership violation was found.

## Security review

Public GitHub advisory GETs at October 5, 2026, 14:46:29 UTC returned no changed
Hex or npm advisories since `2026-10-05`, with no pagination; Caddy returned 17
records. Evidence: `/tmp/marquee-workshop-landing-{hex,npm,caddy}-advisories.json`.
Dependency lockfiles and the Caddy 2.11.6 pin are unchanged. The prior
GHSA-6365-7ppr-5r92 affected Caddy 2.11.4 and was patched in 2.11.5; exposure
required the advisory's forward-auth/reverse-proxy conditions. No new affected
dependency was identified.

The previous npm bulk-audit network retry was rejected by automatic approval
review because it sends dependency metadata to the public registry. The recent
clean baseline plus current public advisory delta are available evidence; this
is not a fresh npm-registry audit. No project dependency metadata was uploaded.

## Final execution and approval

The runner completed 311 doctests and 2,786 tests with no failures, 80.1% Elixir
coverage, formatting, compilation, strict Credo, Dialyzer, and 157 asset tests.
Four focused Gherkin scenarios passed in 3.674 seconds. Final diff checks passed.

The full browser run had 24 passing tests and one obsolete cold-entry setup
expectation in 358.8 seconds. The writer added exactly two setup lines to
PlatformHomeSessionTest: assert Begin demo and click it. Every platform isolation
and identity-reuse assertion remained. Reviewer accepted SHA-256
`fcd701be7e56d7daa37d239b834307b3f6b190fa747882478b0752928f8382f4`;
the affected browser test then passed in 2.3 seconds. The full browser run was
not repeated after this test-only correction, as explicitly approved. This is
combined evidence, not a claim that the original full run was all green.
The actual-gold contrast journey passed both its focused run and the full run.

Evidence: `/tmp/marquee-workshop-verify.log`,
`/tmp/marquee-workshop-coverage.log`,
`/tmp/marquee-workshop-platform-browser-green.log`, and
`/tmp/marquee-workshop-cucumber-final-after-contrast.log`.
Final source and seven accepted test manifests were independently rechecked with
no mismatches. Independent review approves this atomic Workshop landing change;
there are no remaining gates for this scope.
