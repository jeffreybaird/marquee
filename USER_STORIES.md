# Bobine — User Stories

Derived from code inventory (lib/, routes, contexts, workers) cross-checked against Gherkin scenarios in `features/`. Each story lists role, goal, value. **Coverage** flags whether a Cucumber scenario exists.

Legend: ✅ covered · ⚠️ partial · ❌ missing

---

## 1. Authentication & Identity

### Operator
- **OP-AUTH-1** As operator, register account + create organization via magic link confirmation. ✅
- **OP-AUTH-2** As operator, log in with email + password. ✅
- **OP-AUTH-3** As operator, log in via magic link. ✅
- **OP-AUTH-4** As operator, fail login with bad password and see clear error. ✅
- **OP-AUTH-5** As operator, log out and invalidate session. ✅
- **OP-AUTH-6** As operator, update password from settings. ⚠️ (no scenario for password change)
- **OP-AUTH-7** As operator, update email with confirmation flow. ❌
- **OP-AUTH-8** As operator, edit profile in settings. ❌

### Viewer
- **VW-AUTH-1** As viewer, register with email + password. ✅
- **VW-AUTH-2** As viewer, register with email only and receive magic link. ✅
- **VW-AUTH-3** As viewer, log in via magic link. ✅
- **VW-AUTH-4** As viewer, log in with email + password. ✅
- **VW-AUTH-5** As viewer, see error when magic link expired. ✅
- **VW-AUTH-6** As viewer, log out. ✅

---

## 2. Content Management (Operator)

### Videos
- **CM-VID-1** Upload one or more videos direct-to-Mux. ✅
- **CM-VID-2** See video status update to "ready" via Mux webhook. ✅
- **CM-VID-3** See video status update to "error" via Mux webhook. ✅
- **CM-VID-4** Edit video metadata (title, description). ✅
- **CM-VID-5** Upload portrait thumbnail. ✅
- **CM-VID-6** Upload landscape thumbnail. ✅
- **CM-VID-7** See Mux fallback thumbnail when none uploaded. ✅
- **CM-VID-8** Soft-delete + restore videos. ✅
- **CM-VID-9** Add/remove tags on a video (incl. inline tag create). ✅
- **CM-VID-10** Search + paginate video library. ✅
- **CM-VID-11** Set video access level (public, subscribers-only, PPV, gated). ❌ (access control code exists, no Gherkin)

### Series & Seasons
- **CM-SER-1** Create series; add seasons; add episodes per season. ✅
- **CM-SER-2** Edit series + season metadata. ✅
- **CM-SER-3** Toggle visibility of series + season. ✅
- **CM-SER-4** Soft-delete series. ✅

### Collections
- **CM-COL-1** Create collection; add videos + series; reorder; remove items. ✅
- **CM-COL-2** Toggle visibility of collection. ✅
- **CM-COL-3** Soft-delete collection. ✅

### Tags
- **CM-TAG-1** CRUD tags with duplicate-name validation. ✅
- **CM-TAG-2** Search tags. ✅

---

## 3. Catalog & Homepage (Operator)

- **CAT-1** Create / edit / reorder / delete catalog rows. ✅
- **CAT-2** Toggle row visibility. ✅
- **CAT-3** Add/remove videos in row. ✅
- **CAT-4** Hide row "details" bar; enable title overlay on cards. ✅
- **CAT-5** Apply / cancel a layout preset. ✅
- **CAT-6** Configure rows by source type (curated, collection, tag, recent, popular, continue-watching). ⚠️ (only curated covered explicitly)
- **CAT-7** Hero carousel: create / reorder / delete slides; upload banner; set auto-advance interval; toggle visibility. ✅
- **CAT-8** Add title logo + channel logo to hero slide; text fallback. ✅

### Landing page builder
- **LP-1** Add hero / feature / video / testimonial / FAQ / CTA section. ✅
- **LP-2** Edit, reorder, toggle visibility, delete sections. ✅
- **LP-3** Add / remove FAQ items. ✅
- **LP-4** Link existing video or upload new video to section. ✅

---

## 4. Viewer Experience

### Discovery
- **VW-DISC-1** Browse homepage with hero + rows per org config. ✅
- **VW-DISC-2** As unauthenticated viewer, see public content + login/subscribe prompt. ✅
- **VW-DISC-3** Browse a collection page. ✅
- **VW-DISC-4** Filter content by tag. ✅
- **VW-DISC-5** "View all" full row listing. ✅

### Playback
- **VW-PLAY-1** Play a video (Mux player). ✅
- **VW-PLAY-2** Resume from saved position. ✅
- **VW-PLAY-3** Progress auto-saves on pause/stop. ✅
- **VW-PLAY-4** Mark video complete; appears in history. ✅
- **VW-PLAY-5** Play a series episode; switch seasons. ✅
- **VW-PLAY-6** Dismiss a card from continue-watching (preserve progress). ✅
- **VW-PLAY-7** Dismissed series card hides whole series. ✅
- **VW-PLAY-8** See related videos grid on watch page. ⚠️ (code exists, no scenario)

### Queue
- **VW-Q-1** Add to queue / play next / remove / reorder / clear. ✅
- **VW-Q-2** Skip to next; go back to previous. ✅
- **VW-Q-3** Add a whole collection to queue. ✅

### Watchlist & Favorites
- **VW-WL-1** Add / remove video on watchlist. ✅
- **VW-WL-2** Add a series to watchlist. ✅
- **VW-FAV-1** Favorite / unfavorite a video. ✅

### History
- **VW-HIST-1** View paginated watch history; load more; resume. ✅

### Account
- **VW-ACCT-1** Update display name. ✅
- **VW-ACCT-2** Update avatar. ✅
- **VW-ACCT-3** Update marketing preferences. ✅
- **VW-ACCT-4** Delete account permanently. ✅

---

## 5. Billing & Subscriptions

### Operator: Plans & Coupons
- **BIL-PLAN-1** Create plan (Stripe product/price). ✅
- **BIL-PLAN-2** Create plan with trial period. ✅
- **BIL-PLAN-3** Edit plan. ✅
- **BIL-PLAN-4** Deactivate plan (preserve existing access). ✅
- **BIL-PLAN-5** Delete plan with no subscribers. ✅
- **BIL-COUP-1** Create fixed-amount coupon. ✅
- **BIL-COUP-2** Create percentage coupon. ✅
- **BIL-COUP-3** Deactivate coupon. ✅

### Operator: Stripe Connect
- **BIL-SC-1** Initiate Stripe Connect onboarding. ✅
- **BIL-SC-2** Complete Stripe Connect onboarding. ✅
- **BIL-SC-3** Resume onboarding after interruption. ✅
- **BIL-SC-4** View Stripe Connect status from dashboard. ✅

### Viewer
- **BIL-V-1** Subscribe to a plan via Stripe Checkout. ✅
- **BIL-V-2** Apply valid coupon at checkout. ✅
- **BIL-V-3** See error for invalid/expired coupon. ✅
- **BIL-V-4** Cancel checkout (no subscription created). ✅
- **BIL-V-5** Manage subscription via Stripe Customer Portal. ✅
- **BIL-V-6** Cancellation via portal revokes access. ✅
- **BIL-V-7** See payment-failure notice. ✅
- **BIL-V-8** Resolve failed payment + restore subscription. ✅
- **BIL-V-9** Unauthenticated viewer redirected from gated content. ✅

### Platform billing (Super Admin)
- **PLAT-BIL-1** Super admin manages platform plans for organizations. ❌ (code exists `/super/plans`, no scenario)

---

## 6. Live Events & Streaming

### Operator
- **LE-OP-1** Create / edit / delete live event (title, schedule, access level, recording config). ⚠️ (admin scenarios missing in features; code in `lib/bobine_web/live/admin/live_event_live/`)
- **LE-OP-2** Moderate chat (ban viewers). ❌

### Viewer
- **LE-V-1** Browse upcoming, live, past events. ✅
- **LE-V-2** Live-now card shows muted preview; falls back to cover. ✅
- **LE-V-3** Draft events hidden. ✅
- **LE-V-4** Empty-state when no events. ✅
- **LE-V-5** Unauthenticated viewer can browse events. ✅
- **LE-V-6** Download .ics calendar file (CRLF, RFC 5545). ✅
- **LE-V-7** ICS DTEND respects estimated_duration_minutes; 1h default. ✅
- **LE-V-8** ICS 404 for ended / canceled / nonexistent events. ✅
- **LE-V-9** Google Calendar URL with correct fields + 1h default. ✅
- **LE-V-10** Watch live event with chat + viewer count. ❌
- **LE-V-11** Purchase PPV ticket. ❌
- **LE-V-12** Receive cancellation notification + automatic refund. ❌

---

## 7. Podcasts (covered in `features/acceptance/podcasts.feature`)

- **POD-OP-1** Operator creates direct-upload podcast show with slug + access mode. ✅
- **POD-OP-2** Operator restricts show to specific subscription tier(s). ✅
- **POD-OP-3** Operator revokes a subscriber's feed token. ✅
- **POD-OP-4** Multi-tenant isolation: org A cannot see org B's shows. ✅
- **POD-OP-5** Sync episodes from remote RSS feed. ❌ (worker exists, no scenario)
- **POD-V-1** Subscriber's tokenized feed serves iTunes-namespaced RSS with enclosure URL. ✅
- **POD-V-2** Subscriber regenerates feed URL → new token, old revoked. ✅
- **POD-V-3** Mux audio webhook publishes draft episode (sets `mux_playback_id`, status → published). ✅
- **POD-V-4** Browse podcast directory in viewer site. ❌
- **POD-V-5** View podcast show page + episode list. ❌
- **POD-V-6** Listen to episode in browser (viewer-side player). ❌

---

## 8. Branding & Theming (Operator)

- **BR-1** Pick theme preset; preview before apply. ✅
- **BR-2** Apply theme; viewer site updates. ✅
- **BR-3** Override accent colors with custom values. ✅
- **BR-4** Pick display + body fonts. ✅
- **BR-5** Theme propagates across cluster (PubSub cache invalidation). ✅
- **BR-6** Expand mini-preview to fullscreen overlay. ✅
- **BR-7** Mini-preview reuses real viewer components + CTA classes. ✅
- **BR-8** Set custom domain. ✅
- **BR-9** Set admin accent color. ✅
- **BR-10** Configure layout settings via Appearance page. ⚠️ (route exists `/admin/appearance`, no scenario)

---

## 9. Analytics

### Operator
- **AN-OP-1** Org overview KPIs (subs, MRR, content perf summary). ✅
- **AN-OP-2** Subscriber growth time series (day/week/month). ✅
- **AN-OP-3** Daily revenue chart. ✅
- **AN-OP-4** Content performance table with sort + paginate. ✅
- **AN-OP-5** Per-video analytics (views, completion, drop-off). ✅
- **AN-OP-6** Per-series + per-season analytics. ✅

### Super Admin
- **AN-SA-1** Platform-wide KPIs. ✅
- **AN-SA-2** Revenue per org. ✅
- **AN-SA-3** Top organizations ranked. ✅

---

## 10. Audit Logging

- **AUD-OP-1** View org audit log. ✅
- **AUD-OP-2** Filter by actor / action / resource type. ✅
- **AUD-OP-3** Expand entry to see field-level diff. ✅
- **AUD-OP-4** Load more (paginate). ✅
- **AUD-OP-5** Export filtered log as CSV. ✅
- **AUD-OP-6** Impersonation context recorded. ✅
- **AUD-SA-1** Super admin views platform-wide log. ✅
- **AUD-SA-2** Filter by org. ✅
- **AUD-SA-3** Super admin grants visible in log. ✅

---

## 11. Organization & Team Management

### Super Admin
- **SA-ORG-1** List all orgs with health metrics. ✅
- **SA-ORG-2** Create org + provision owner. ✅
- **SA-ORG-3** Edit org (name, slug, custom domain). ✅
- **SA-ORG-4** Soft-delete org. ✅
- **SA-ORG-5** Restore soft-deleted org. ✅
- **SA-ORG-6** Impersonate operator; end impersonation. ✅
- **SA-USR-1** List all platform users. ✅
- **SA-USR-2** Grant + revoke super admin. ✅

### Operator
- **TEAM-1** Owner/admin views team members + roles. ✅
- **TEAM-2** Owner invites a member with specific role. ✅
- **TEAM-3** Owner removes member. ✅
- **TEAM-4** Non-owner blocked from membership management. ✅

---

## 12. Viewer Management (Operator)

- **VM-1** Paginated viewer list. ✅
- **VM-2** Search viewers. ✅
- **VM-3** Suspend a viewer. ✅
- **VM-4** Ban a viewer (permanent). ✅
- **VM-5** Reactivate suspended viewer. ✅
- **VM-6** Grant early access (with optional expiry). ✅
- **VM-7** Revoke early access. ✅
- **VM-8** Impersonate viewer; end impersonation. ✅

---

## 13. Webhooks & Integrations

### Inbound (System)
- **WH-MUX-1** Mux asset.ready event → status updated, operator sees real-time. ✅
- **WH-MUX-2** Mux asset.errored event → status updated. ✅
- **WH-MUX-3** Invalid Mux signature rejected (400). ✅
- **WH-MUX-4** Org resolved from passthrough metadata. ✅
- **WH-STR-1** Stripe subscription.created. ✅
- **WH-STR-2** Stripe subscription.updated. ✅
- **WH-STR-3** Stripe subscription.deleted. ✅
- **WH-STR-4** Stripe invoice.payment_succeeded. ✅
- **WH-STR-5** Stripe invoice.payment_failed. ✅
- **WH-STR-6** Invalid Stripe signature rejected. ✅
- **WH-STR-7** Connect webhook routed to correct org. ✅

### Outbound (Operator) ❌
- **WH-OUT-1** Operator configures custom webhook endpoint. ❌
- **WH-OUT-2** Org events deliver to configured endpoints. ❌
- **WH-OUT-3** View webhook delivery history / retries. ❌

---

## 14. Notifications ⚠️ (subsystem present, partial coverage)

- **NOT-1** Live-event reminder before scheduled start. ❌
- **NOT-2** Live-event "going live now" notification. ❌
- **NOT-3** Live-event cancellation notification. ❌
- **NOT-4** Push notification preferences. ❌

---

## 15. Cross-Cutting

- **MT-1** Tenant resolved from subdomain or custom domain. ⚠️ (design doc only)
- **MT-2** One org cannot read/mutate another org's data. ⚠️ (RBAC scenarios present partially in viewer/team mgmt)
- **OPS-1** Health check endpoint for Fly.io. n/a (infra)

---

# Step Definition Reality Check

`✅` above means a `Scenario:` exists in a `.feature` file. **It does not mean the scenario executes.** Cross-checking `features/step_definitions/`:

| Feature file | Step file present? | Status |
|---|---|---|
| admin_dashboard | yes | runs |
| analytics | yes | runs |
| audit_logging | yes | runs |
| authentication | yes | runs |
| **billing** | **no** | **scenarios written, no steps — won't run** |
| branding | yes | runs |
| catalog | yes | runs |
| **content_consumption** | **no** | **no steps — won't run** |
| content_management | yes | runs |
| **live_events** | **no** | **no steps — won't run** |
| **organization_management** | **no** | **no steps — won't run** |
| viewer_management | yes | runs |
| webhooks | yes | runs |
| acceptance/podcasts | podcasts_steps.ex | runs |
| acceptance/{auth,catalog,content_mgmt} | shared w/ top-level | runs |

Comments in `authentication.feature` explicitly mark 4 planned-but-pending scenarios: forgotten password reset, sudo re-auth, email change, password change.

# Coverage Gap Summary

| Domain | Code features | Cucumber covered | Gap |
|---|---|---|---|
| Auth (operator) | 8 | 5 | password change, email change, profile edit |
| Content mgmt | 11 | 10 | access control levels (public/subs/PPV/gated) |
| Catalog | 8 | ~7 | row source types beyond curated |
| Viewer experience | 25 | 24 | related-videos grid |
| Billing | 21 | 20 | super-admin platform plans |
| Live events | 12 | 9 | admin CRUD, watch+chat, PPV purchase, refund/cancel notif |
| Podcasts | 11 | 7 | RSS sync worker, viewer-side directory/show/player |
| Branding | 10 | 9 | appearance/layout settings page |
| Analytics | 9 | 9 | full |
| Audit | 9 | 9 | full |
| Org/team mgmt | 12 | 12 | full |
| Viewer mgmt | 8 | 8 | full |
| Webhooks (in) | 11 | 11 | full |
| **Webhooks (out)** | **3** | **0** | **operator endpoint mgmt + delivery** |
| **Notifications** | **4** | **0** | **entire domain** |

## Top priorities

0. **Write step definitions for existing orphan feature files**: `billing.feature`, `content_consumption.feature`, `live_events.feature`, `organization_management.feature`. Scenarios already written — just no executor. Highest ROI.
1. **Podcasts viewer side** — `/podcasts` directory, show detail page, in-browser player. Operator side covered.
2. **Live events admin** — operator create/edit/delete + chat moderation + PPV purchase flow + cancellation refund/notify.
3. **Outbound webhook endpoints** — operator config + delivery + retry visibility.
4. **Notifications** — live-event reminder/live-now/cancel, viewer push prefs.
5. **Content access control** — public vs subs-only vs PPV vs gated enforcement on watch + browse.
6. **Super admin platform plans** — `/super/plans` CRUD.
7. **Operator self-service** — password change, email change, profile edit.
8. **Multi-tenant isolation tests** — explicit org-A-cannot-see-org-B scenarios per CLAUDE.md rule.
