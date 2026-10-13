# Cucumber audit handoff (issue #28)

Branch: `claude/cucumber-audit` (off `main` at 029d556). Last commit:
`8529636 initial audit of cucumber`. Development is paused; this file is the
handoff for whoever resumes. Issue:
https://github.com/jeffreybaird/marquee/issues/28

## Process rules in force

- Agent workflow v2.0.0 (`.docs/agent-workflow.md`). Main session orchestrates
  only. Spec writer owns `features/**` and `test/**`; implementer owns `lib/**`,
  `mix.exs`, config, `.github/workflows/*.yml`; runner records red/green
  evidence; reviewer accepts tests before implementation and reviews the final
  diff. Hooks deny direct source/test edits from the main session.
- Test deletions need explicit user approval. Approval was given for
  `features/acceptance/authentication.feature` (staged deletion, uncommitted).
- User decisions: define every undefined step (no scenario removals); delete
  only the stale acceptance auth feature.
- Commit trailer: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
  PR body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- GitHub MCP is broken; use `gh` CLI.
- Step files under `features/` are excluded from `mix format`.

## Issue #28 status

| Task | Status |
|------|--------|
| 1. Root-cause and fix failing scenarios | Partial. 31 original failures diagnosed. 30 were test-side (step fixes committed in 8529636). 1 was an app gap (A3, audit-log expanded row never rendered `changes`); fixed in working tree, green. Several step fixes still fail on rerun (see below). |
| 2. Report undefined steps, propose definitions | Report done: `.docs/cucumber-undefined-steps.md` (37 files, 180 scenarios, 606 undefined step occurrences). Its "proposal" section is superseded by the user's decision to define everything. Definitions: in progress, nothing finished. |
| 3. Port 4002 collision | Done, committed. `mix marquee.cucumber` honours `MARQUEE_CUCUMBER_PORT` (default 4003). Docs updated in `.docs/testing.md` and `.docs/project-guidance.md`. Smoke evidence: 4 scenarios passed on 4003. |
| 4. `mix hex.audit` in verify + CI | Done, committed. `lib/mix/tasks/marquee/verify.ex` and `.github/workflows/ci.yml`. |

## Uncommitted working tree

- `lib/marquee_web/live/admin/audit_log_live.ex`,
  `lib/marquee_web/live/super/audit_log_live.ex`: A3 implementation. Expanded
  `metadata-row-<id>` renders `<section data-test="changes-<id>">` and
  `<section data-test="metadata-<id>">` with pretty JSON; expand button
  aria-label "Expand details"/"Collapse details". Tests in
  `test/marquee_web/live/{admin,super}/audit_log_live_test.exs` (already
  committed) pass: 26 tests, 0 failures. Ready to commit as
  `fix: render audit log changes in expanded row`.
- `D features/acceptance/authentication.feature`: staged, user-approved. Commit
  as `test: remove stale acceptance authentication feature`.
- `features/step_definitions/onboarding_steps.ex`: contains a `DEBUG-TEMP`
  block (Process.sleep + IO.puts) left by a killed spec writer. Revert or
  finish; do not commit it.
- `features/step_definitions/content_consumption_steps.ex` (untracked, 1252
  lines): partial from a killed spec writer. Uses literal string patterns
  (good). Not yet compiled or run. Verify with `MIX_ENV=test mix compile` and
  a dry run before relying on it.
- `.agent-audit/bash.jsonl`: audit log, commit with the work.

## Known failures still open (from rerun logs)

Evidence dir: `/private/tmp/claude-501/-Users-jeffreybaird-src-marquee/5ed2f40b-55f1-4345-a8e7-971b4b80c93f/scratchpad/evidence/`

- `features/authentication.feature` (5 scenarios, 4 pass): "I log out" then
  `I see "Logged out successfully"` fails. Logout is a `method="delete"` link
  causing a full page load; body text check finds no flash. Check what flash
  the app actually sets on logout and whether the redirect lands on a page that
  renders flash.
- `features/onboarding.feature` (5 scenarios, 3 pass): "I finish the setup
  wizard" and "I skip the setup wizard" both still find
  `[data-test=onboarding-progress]` after finish/skip. Spec writer was mid
  debug (see DEBUG-TEMP block). Likely LiveView navigation not awaited; use
  `MarqueeFeatures.Support.Browser.await_live_connect/1` or assert on the
  dashboard `h1` first.
- `features/super_admin_user_management.feature` (3 scenarios, 1 pass):
  "the promotion is recorded in the audit log" / "the revocation is recorded in
  the audit log" fail: `expected audit entry for super admin grant of user <id>`.
  Check whether `Admin.grant_super_admin`/`revoke_super_admin` emit an audit
  event; if not, that is an app gap (new failing test, implementer fix).
- `features/super_admin_org_management.feature` (7 scenarios, 6 pass): 1
  scenario has an undefined step; define it.
- Not rerun after fixes: branding, tags, viewer management, audit logging
  (expand scenario should now pass with A3), landing page, analytics,
  `features/acceptance/*`.

## Wallaby/Cucumberex pitfalls learned

- Wait for `[data-phx-main].phx-connected` before any phx-* interaction
  (`MarqueeFeatures.Support.Browser.visit_live/2`).
- After a full page load (`phx-trigger-action` POST, `method="delete"` link) use
  `assert_has(css("body", text: ...))`, not `assert_text` (stale element).
- `<select>` filters: `click(css("select option[value=...]"))`, not `set_value`.
- Step patterns must be literal strings, never `~s(...)` sigils.
- Appearance presets are `Marquee.Catalog.Presets` (`catalog_cinema`,
  `learning_platform`, `creator_channel`), stored on `layouts.preset_name`.
- Orphaned `chromedriver` processes accumulate (hundreds seen). Before a run:
  `pkill -f 'chromedriver --log-level=OFF'`.
- Parallel runs: `MIX_TEST_PARTITION=N` selects DB `marquee_testN`
  (`MIX_TEST_PARTITION=N mix ecto.create && mix ecto.migrate` first) and
  `MARQUEE_CUCUMBER_PORT=40NN` selects the endpoint port.

## Plan for the undefined steps (not started beyond the partial file)

Six parallel spec writers, each with its own partition/port and disjoint
feature + step files. Groups (partition/port): billing 11/4011,
content consumption 12/4012, catalog+branding+dashboard 13/4013,
content mgmt + live events 14/4014, viewer/team/analytics/audit 15/4015,
original failure fixer 10/4010. Rules: never edit `shared_steps.ex` or
`features/support/*`; grep all step files before adding a pattern to avoid
ambiguous matches; one real step per pathway; app gaps become honest failing
steps reported to the orchestrator, not stubs. Shared handoff text is in the
scratchpad `HANDOFF-steps.md`. Each group writes
`evidence/accepted-steps-<group>.sha256` plus a pretty-format log.

## Commands

```bash
MIX_ENV=test mix compile --warnings-as-errors
mix marquee.cucumber features/<file>.feature --format pretty --strict
mix marquee.cucumber --dry-run --strict    # undefined step inventory
mix test test/marquee_web/live/admin/audit_log_live_test.exs test/marquee_web/live/super/audit_log_live_test.exs
mix precommit --no-e2e                     # before commit; full run before push
```

## Remaining steps to finish the PR

1. Clean `onboarding_steps.ex` debug block; confirm
   `content_consumption_steps.ex` compiles.
2. Commit A3 source and the acceptance feature deletion as separate commits.
3. Resume undefined-step definition per the group plan; fix the open failures.
4. Update `.docs/cucumber-undefined-steps.md` to reflect the decision and
   final state.
5. Full-suite green evidence (`--format pretty --strict`), reviewer final diff,
   dead-code review, `mix deps.audit` + `mix hex.audit` advisory report.
6. `mix precommit`, push, `gh pr create` (non-draft, base `main`) with Gherkin
   scenario evidence per `.docs/agent-workflow.md`; report `<pr-created>URL</pr-created>`.
