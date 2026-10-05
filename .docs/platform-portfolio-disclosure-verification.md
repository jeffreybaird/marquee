# Platform portfolio disclosure verification

The platform homepage displays exactly: “Marquee is a portfolio project, not a
real business.” A full-width, in-flow note appears after navigation and before
the hero. Tenant landing/catalog pages do not display it. Existing surface/text
color tokens and responsive spacing preserve the platform's visual system.

## Accepted contract and red evidence

The HTTP/connected test failed on the missing sentence. The focused Gherkin
feature had one passing scenario and one expected missing-disclosure failure.
Logs: `/tmp/marquee-platform-banner-red.log` and
`/tmp/marquee-platform-banner-cucumber-red.log`.
The geometry contract checks desktop 1280px and mobile 390px: visible in the first
viewport, full width, above the hero, without horizontal overflow.

Three-file test manifest: `/tmp/marquee-platform-banner-reviewed-tests.json`,
SHA-256 `f089a6d5e64b298be8e57fedfaf337874e53bfe310c0d065a6cd8f51a859e4f4`.
One-file source manifest: `/tmp/marquee-platform-banner-reviewed-source.json`,
SHA-256 `b30504f9f3a7eebc785e170c0c5dbab3616a6b7097070edeeacfc2d88c95f501`.
The independent source review found no scope or accessibility blocker. Exact
source hash: `854316a03b2eb4681f9bb85f1efa71d3d9a9a9b6cb01da7ad8ac34ad06a339ea`.
Accepted test hashes match. Current audit delta: two ambiguous records, no
reported violations. Root independently confirmed the exact strip below navigation and above the hero
at desktop 1280px and actual mobile 390px (innerWidth verified). The sentence is
fully visible. Root screenshots: `portfolio-banner-desktop.jpg` and
`portfolio-banner-mobile.jpg`. Final execution passed as recorded below.

## Security review

Public GitHub advisory GETs at 2026-10-05 15:22:26 UTC returned zero modified Hex
or npm advisories since the beginning of the day, with no pagination. Evidence:
`/tmp/marquee-portfolio-banner-advisories.json`. Dependency locks and runtime
pins are unchanged. This supplements the earlier baseline; it is not a new
npm-registry bulk audit. The prior bulk retry was rejected by automatic approval
review because it sends dependency metadata. No such metadata was uploaded.

Previously reviewed Caddy GHSA-6365-7ppr-5r92 affected 2.11.4, was patched in
2.11.5, and required its forward-auth/reverse-proxy exposure conditions. The
current pin remains 2.11.6. No new affected dependency was identified. This
static markup change adds no external requests or authentication behavior.

## Final execution and approval

The runner completed the full verification command successfully: 311 doctests,
2,787 tests, 25 browser tests (350.9 seconds), 157 asset tests, formatting,
compilation, strict Credo, and Dialyzer all passed. Elixir coverage is 80.1%.
The focused 65 HomeLive tests and both Gherkin scenarios passed. Diff checks are
clean. Source and accepted test fingerprints remain unchanged.

Evidence: `/tmp/marquee-platform-banner-verify.log`,
`/tmp/marquee-platform-banner-coverage.log`,
`/tmp/marquee-platform-banner-focused-green.log`, and
`/tmp/marquee-platform-banner-cucumber-green.log`.

Independent review approves this atomic platform disclosure change. All required
execution, visual, scope, and advisory-review gates are complete.
