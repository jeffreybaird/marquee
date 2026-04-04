# Frontend Map

Quick-reference for navigating Bobine's frontend layer. Covers routes, LiveViews,
components, JS hooks, and layout hierarchy.

---

## Layout Hierarchy

```
root.html.heex                    ← HTML skeleton, meta tags, asset loading
├── ViewerLayout.viewer_layout    ← Org-branded shell: header, nav, mobile nav, theme CSS vars
│   └── Viewer LiveViews          ← HomeLive, WatchLive, BrowseLive, etc.
├── AdminLayout.admin_layout      ← DaisyUI sidebar + main content, responsive
│   └── Admin LiveViews           ← ContentLive, CatalogLive, MembersLive, etc.
├── SuperLayout.super_layout      ← Dark slate sidebar, platform-level nav
│   └── Super LiveViews           ← OrganizationsLive, UsersLive, PlansLive, etc.
└── Layouts.app                   ← Minimal layout for operator auth (login, register, settings)
    └── UserLive views            ← Login, Registration, Settings, Confirmation
```

---

## Route → LiveView Map

### Viewer-Facing (org resolved from subdomain/custom domain)

| Route                    | LiveView                   | Auth       | Notes |
|--------------------------|----------------------------|------------|-------|
| `/`                      | `Viewer.HomeLive`          | Optional   | Shows org catalog, org landing, or platform marketing based on context |
| `/browse`                | `Viewer.BrowseLive`       | Optional   | Search, filter by collection/tag, sort |
| `/collections/:slug`    | `Viewer.CollectionLive`    | Optional   | Single collection with its videos |
| `/register`              | `Viewer.RegisterLive`      | None       | Viewer email registration |
| `/login`                 | `Viewer.LoginLive`         | None       | Magic link auth |
| `/account`               | `Viewer.AccountLive`       | Required   | Profile editing, subscription management |
| `/account/payment-issue` | `Viewer.PaymentIssueLive`  | Required   | Past-due subscription, redirect to Stripe portal |
| `/subscribe`             | `Viewer.SubscribeLive`     | Required   | Plan selection, Stripe Checkout redirect |
| `/subscribe/success`     | `Viewer.SubscribeSuccessLive` | Required | Post-checkout confirmation |
| `/watch/:id`             | `Viewer.WatchLive`         | Subscribed | Video player, queue panel, related videos |
| `/watchlist`             | `Viewer.WatchlistLive`     | Subscribed | Tabbed: watchlist tab |
| `/favorites`             | `Viewer.WatchlistLive`     | Subscribed | Tabbed: favorites tab |
| `/queue`                 | `Viewer.WatchlistLive`     | Subscribed | Tabbed: queue tab (drag-and-drop reorder) |
| `/history`               | `Viewer.HistoryLive`       | Subscribed | Paginated watch history |

### Operator Dashboard (`/admin/*` — org resolved, viewer_support+ role)

| Route                          | LiveView                  | Notes |
|--------------------------------|---------------------------|-------|
| `/admin`                       | `Admin.DashboardLive`     | Overview/stats |
| `/admin/content`               | `Admin.ContentLive`       | Video list, upload, edit metadata, tag management |
| `/admin/collections`           | `Admin.CollectionsLive`   | CRUD collections, assign videos |
| `/admin/tags`                  | `Admin.TagsLive`          | CRUD tags |
| `/admin/catalog`               | `Admin.CatalogLive`       | Homepage row builder: add/edit/reorder rows, hero config |
| `/admin/analytics`             | `Admin.AnalyticsLive`     | Placeholder |
| `/admin/branding`              | `Admin.BrandingLive`      | Theme color editor with live preview |
| `/admin/members`               | `Admin.MembersLive`       | Viewer and operator member management |
| `/admin/webhooks`              | `Admin.WebhooksLive`      | Placeholder |
| `/admin/settings`              | `Admin.SettingsLive`      | Stripe Connect onboarding |
| `/admin/settings/billing`      | `Admin.BillingLive`       | Platform subscription, plan selection, usage |
| `/admin/settings/billing/success` | `Admin.PlanSuccessLive` | Post-checkout confirmation |
| `/admin/plans`                 | `Admin.PlansLive`         | Viewer subscription plans CRUD |
| `/admin/coupons`               | `Admin.CouponsLive`       | Stripe coupon CRUD |

### Super Admin (`/super/*` — no org, requires `is_super_admin`)

| Route                          | LiveView                       | Notes |
|--------------------------------|--------------------------------|-------|
| `/super`                       | `Super.DashboardLive`          | Platform overview |
| `/super/organizations`         | `Super.OrganizationsLive`      | Org list |
| `/super/organizations/new`     | `Super.OrganizationNewLive`    | Create org |
| `/super/organizations/:id`     | `Super.OrganizationShowLive`   | Org detail, impersonate button |
| `/super/organizations/:id/edit`| `Super.OrganizationEditLive`   | Edit org |
| `/super/users`                 | `Super.UsersLive`              | All users across tenants |
| `/super/plans`                 | `Super.PlansLive`              | Platform plan management |

### Operator Auth (no org resolution)

| Route                                       | LiveView                | Notes |
|---------------------------------------------|-------------------------|-------|
| `/users/register`                           | `UserLive.Registration` | Operator signup |
| `/users/log-in`                             | `UserLive.Login`        | Operator login |
| `/users/log-in/:token`                      | `UserLive.Confirmation` | Email confirmation |
| `/users/settings`                           | `UserLive.Settings`     | Operator profile |

### API / Controller-Only Routes

| Route                              | Controller                     | Notes |
|------------------------------------|--------------------------------|-------|
| `/webhooks/mux`                    | `WebhookController`            | Mux webhook receiver |
| `/webhooks/stripe`                 | `WebhookController`            | Stripe webhook receiver |
| `/health`                          | `HealthController`             | Fly.io health check |
| `/super/organizations/:id/impersonate` | `ImpersonationController` | Start impersonation (POST) |
| `/super/impersonate`               | `ImpersonationController`      | Stop impersonation (DELETE) |
| `/admin/settings/stripe/return`    | `StripeConnectController`      | Stripe Connect OAuth return |
| `/admin/settings/stripe/refresh`   | `StripeConnectController`      | Stripe Connect refresh |
| `/magic-link/:token`               | `Viewer.SessionController`     | Viewer magic link login |

---

## Component Modules

| Module                          | File                                     | Purpose |
|---------------------------------|------------------------------------------|---------|
| `BobineWeb.CoreComponents`      | `components/core_components.ex`          | Phoenix-generated: tables, forms, inputs, modals, icons. Tailwind + daisyUI. |
| `BobineWeb.Components.ViewerComponents` | `components/viewer_components.ex` | Viewer UI: `content_card`, `content_row`, `video_player`, `empty_state`, `badge`, `gate_overlay`, `skeleton_row`, `sv_button`. All use `--sv-*` CSS vars. |
| `BobineWeb.Components.ViewerLayout` | `components/viewer_layout.ex`        | Viewer shell: `viewer_layout` (header, nav, mobile nav, theme injection, impersonation banner). |
| `BobineWeb.Components.AdminLayout` | `components/admin_layout.ex`          | Admin shell: `admin_layout` (sidebar nav, responsive, impersonation banner). |
| `BobineWeb.Components.SuperLayout` | `components/super_layout.ex`          | Super admin shell: `super_layout` (dark sidebar). |
| `BobineWeb.Layouts`             | `components/layouts.ex`                  | Root layout, app layout, flash group. Embeds `layouts/root.html.heex`. |

---

## JS Hooks → LiveView Usage

| Hook              | File                          | Used By                        | Server Events |
|-------------------|-------------------------------|--------------------------------|---------------|
| `MuxPlayer`       | `hooks/mux_player.ts`         | `WatchLive`                    | `playback_started`, `playback_progress`, `playback_paused` |
| `PlaybackTracker` | `hooks/playback_tracker.ts`   | `WatchLive`                    | `progress_update` |
| `HeroCarousel`    | `hooks/hero_carousel.ts`      | `HomeLive`                     | None (client-side only) |
| `CardFocus`       | `hooks/card_focus.ts`         | `ViewerComponents.content_card`| None (client-side hover/focus popup + preview player) |
| `RowScroller`     | `hooks/row_scroller.ts`       | `ViewerComponents.content_row` | None (client-side scroll arrows) |
| `ViewerNav`       | `hooks/viewer_nav.ts`         | `ViewerLayout.viewer_header`   | None (transparent→solid nav on scroll) |
| `MuxUploader`     | `hooks/mux_uploader.ts`       | `Admin.ContentLive`            | Receives `upload_url`, sends `upload_complete`, `upload_error` |
| `Sortable`        | `hooks/sortable.ts`           | `Admin.CatalogLive`            | `reordered` |
| `QueueSortable`   | `hooks/queue_sortable.ts`     | `Viewer.WatchlistLive` (queue tab), `WatchLive` (queue panel) | `reorder_queue` |
| `PushNotifications`| `hooks/push_notifications.ts`| Not yet wired                  | `push_subscription_created`, `push_subscription_failed` |

---

## Shared Behavior: CardActions

`BobineWeb.Viewer.CardActions` (`live/viewer/card_actions.ex`) is a `__using__` macro
included by most viewer LiveViews that render `content_card` components. It provides:

- `on_mount` callback that loads engagement state (`favorited_ids`, `watchlisted_ids`, `queued_ids`)
- `handle_event` clauses for `card_toggle_favorite`, `card_add_to_watchlist`, `card_add_to_queue`
- Optimistic UI updates

**LiveViews that `use CardActions`:** HomeLive, BrowseLive, WatchLive, WatchlistLive, HistoryLive, CollectionLive.

---

## CSS Architecture

- **Tailwind CSS + daisyUI** — admin and super admin use daisyUI component classes directly.
- **Viewer `--sv-*` custom properties** — all viewer styling uses CSS custom properties
  injected by `Theme.build_css_vars/1` on the `.sv-root` element. The org's `Branding.Theme`
  controls colors, fonts, etc. See `assets/css/app.css` for the viewer stylesheet.
- **No hardcoded colors in viewer templates** — everything flows through theme variables.

---

## Pipelines (Authentication/Authorization)

| Pipeline              | Purpose                                                  |
|-----------------------|----------------------------------------------------------|
| `:browser`            | Standard browser stack + `SetRequestContext` (trace IDs) |
| `:set_organization`   | Resolves org from subdomain/custom domain (required)     |
| `:optional_organization` | Same but doesn't 404 if no org found                 |
| `:require_admin`      | Requires `viewer_support` role or higher                 |
| `:require_super_admin`| Requires `is_super_admin` on user                        |

LiveView `on_mount` hooks add further auth checks:

| Hook                                | Purpose |
|-------------------------------------|---------|
| `AssignScope :require_authenticated`| Operator must be logged in |
| `AssignScope :assign_org`           | Puts org in assigns |
| `AssignViewerScope :optional_auth`  | Loads viewer if session exists |
| `AssignViewerScope :require_authenticated` | Viewer must be logged in |
| `RequireSuperAdmin :require_super_admin` | Super admin check for LiveView |
| `RequireSubscription :require_subscription` | Active subscription required |
