# Cucumber audit handoff (issue #28)

Branch: `claude/cucumber-audit`, PR #30. Issue:
https://github.com/jeffreybaird/marquee/issues/28

## Issue #28 status

| Task | Status |
|------|--------|
| 1. Root-cause and fix failing scenarios | Done. Test-side failures fixed in step definitions. App defects fixed in `lib/` with ExUnit regression tests: audit log expanded row, billing fixes, hidden content visible to viewers, tag admin editing and duplicate names, collection picker buttons, viewer delete redirect, logout flash, org counts, theme fonts, admin flashes. |
| 2. Undefined steps | Done. Every step is defined. Scenarios for features the app lacks are tagged `@app-gap`, one issue each (#31–#46). See `.docs/cucumber-undefined-steps.md`. |
| 3. Port 4002 collision | Done. `mix marquee.cucumber` honours `MARQUEE_CUCUMBER_PORT` (default 4003). |
| 4. `mix hex.audit` in verify + CI | Done. |

## App-gap issues

| Issue | Scenario(s) |
|-------|-------------|
| #31 | Operator deletes a plan with no subscribers |
| #32 | Viewer applies a valid / invalid or expired coupon at checkout |
| #33 | Operator deactivates a coupon |
| #34 | Viewer adds a series to watchlist |
| #35 | Viewer adds a video to play next |
| #36 | Viewer adds a collection to queue |
| #37 | Operator uploads a custom hero banner image |
| #38 | Operator adds a feature / testimonial / CTA section |
| #39 | Operator sets a custom domain |
| #40 | Operator sets an admin accent color |
| #41 | Operator searches tags |
| #42 | Operator views series analytics |
| #43 | Operator audit log captures impersonation context; operator impersonates a viewer |
| #44 | Viewer updates avatar |
| #45 | Viewer registers / logs in with email and password |
| #46 | `team_membership_management.feature` (whole file) |

Follow-ups found during review, not fixed here: #47 (hidden seasons in catalog
rows and `/watch/:id`), #48 (unique tag-name index, `update_tag`), #49
(org-less duplicate Stripe audit row), #50 (redundant `subscribe_global` in
`Branding.CacheSubscriber`), #51 (secondary hero CTA contrast).

## Running the suite

```bash
pkill -f 'chromedriver --log-level=OFF'   # orphaned drivers accumulate
MARQUEE_CUCUMBER_PORT=4020 mix marquee.cucumber features/<file>.feature \
  --format pretty --strict --tags "not @app-gap"
```

- Run feature files one at a time. Running the whole tree in one process can
  exhaust Postgres connections (`too_many_connections`).
- Pass `--tags` and its expression as two arguments. `--tags="not @app-gap"` is
  ignored and the app-gap scenarios run.
- `--dry-run` marks every step skipped without matching, so it cannot find
  undefined steps. Use `--strict` on a real run.
- ChromeDriver must match Chrome's major version. It is installed as the npm
  global `chromedriver` (`npm install -g chromedriver@<major>`), not a Homebrew cask.

## Wallaby/Cucumberex pitfalls

- Wait for `[data-phx-main].phx-connected` before any phx-* interaction
  (`MarqueeFeatures.Support.Browser.visit_live/2`).
- After a full page load (`phx-trigger-action` POST, `method="delete"` link) use
  `assert_has(css("body", text: ...))`, not `assert_text` (stale element).
- `refute_has` does not wait. Assert the new state first, then refute the old.
- `<select>` filters: `click(css("select option[value=...]"))`, not `set_value`.
- Step patterns must be literal strings, never `~s(...)` sigils.
- Parallel runs: `MIX_TEST_PARTITION=N` selects DB `marquee_testN` and
  `MARQUEE_CUCUMBER_PORT=40NN` selects the endpoint port.
