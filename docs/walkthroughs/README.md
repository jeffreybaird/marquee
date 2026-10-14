# Operator walkthrough video scripts

Recordable scripts for the short guide videos shown to new Marquee operators
(owners and admins). Each script covers one task, runs under five minutes, and
pairs narration (**VO**) with stage directions (**STAGE**) that say exactly what
is on screen and what to click. Every quoted label is copied verbatim from the
admin templates, so if a label in a script does not match the app, the app
changed and the script needs updating.

| # | Script | Target | Audience |
|---|--------|--------|----------|
| 01 | [Welcome to your dashboard](01-welcome-to-your-dashboard.md) | 2:30 | Owner, admin |
| 02 | [Uploading videos](02-uploading-videos.md) | 3:00 | Owner, admin, editor |
| 03 | [Collections](03-collections.md) | 2:30 | Owner, admin, editor |
| 04 | [Series and seasons](04-series-and-seasons.md) | 3:00 | Owner, admin, editor |
| 05 | [Homepage rows](05-homepage-rows.md) | 3:30 | Owner, admin, editor |
| 06 | [The hero banner](06-hero-banner.md) | 3:00 | Owner, admin, editor |
| 07 | [Appearance and branding](07-appearance-and-branding.md) | 3:30 | Owner, admin |
| 08 | [Stripe and subscription plans](08-stripe-and-subscription-plans.md) | 4:00 | Owner |
| 09 | [Coupons](09-coupons.md) | 2:00 | Owner, admin |
| 10 | [The landing page](10-landing-page.md) | 3:00 | Owner, admin, editor |
| 11 | [Managing viewers](11-managing-viewers.md) | 2:30 | Owner, admin |
| 12 | [Analytics](12-analytics.md) | 3:00 | Owner, admin |
| 13 | [The audit log](13-audit-log.md) | 1:45 | Owner, admin |
| 14 | [Live events](14-live-events.md) | 4:00 | Owner, admin |
| 15 | [Podcasts](15-podcasts.md) | 3:00 | Owner, admin |
| 16 | [Your trial and Marquee billing](16-your-trial-and-marquee-billing.md) | 2:00 | Owner |

## Script conventions

- **STAGE** lines give the URL, what must be visible, what to click or type,
  and what to wait for before speaking the next line (a flash message, a badge
  changing, a sheet opening). Labels in quotes are exact.
- **VO** is second person, plain, about 140 words per minute. Scene timings
  are cumulative targets, not hard cuts.
- Each script ends with **Rough edges**: things the recorder will run into
  that should not be narrated.
- Scripts never show the browser URL bar in close-up. In development the
  tenant is resolved with `?org=<slug>` on the URL, which is not what a
  production operator sees.

## Recording setup

1. **Org state.** Record scripts 01–10 and 16 on a fresh trial organization
   that still has its sample content. That is the state a new operator lands
   in: the "Your platform is preloaded with **sample content** so you can see
   how it looks." banner, the "Free trial — **N** days left." banner, and the
   setup nudge cards on the dashboard. Do not click "Clear sample content"
   until script 01 says so, and re-seed afterward if you need the sample
   content again.
2. **Populated org.** Scripts 11, 12 and 13 need real viewers, views and
   audit entries or the tables are empty. Record those on a demo org
   (`mix marquee.seed_demo_orgs`, needs `PEXELS_API_KEY` plus Mux credentials)
   or on a trial org after scripts 02–10 have been recorded on it.
3. **External accounts.** Script 02 needs Mux configured and a short video
   file (under two minutes) on disk. Script 08 and 09 need a Stripe account in
   test mode. Script 14 needs OBS or another RTMP encoder.
4. **Guided tour.** The Shepherd tour auto-launches the first time an operator
   opens `/admin`. Script 01 uses it. Finish or dismiss it before recording
   anything else, or it will pop over the dashboard.
5. **Viewer preview.** "View site" in the sidebar footer opens the member-facing
   site in a new tab with a member preview flag, so an operator sees what a
   logged-in viewer sees. Have a second browser profile logged in as a plain
   viewer for scripts 08, 11 and 14.
6. **Window.** Record at 1440×900 or wider so the admin sidebar stays pinned.
   Below the `lg` breakpoint it collapses behind an "Open menu" button.

## Sidebar order

Every script refers to the sidebar by label. The order is: Dashboard, Content,
Collections, Series, Tags, Catalog, Podcasts, Landing Page, Analytics,
Appearance, Members, Webhooks, Settings, Billing, Audit Log, then "View site"
and "Log out" in the footer.

## Known gaps the scripts route around

These are product gaps as of the commit that added these scripts. The scripts
avoid or acknowledge them; they do not narrate them as features.

- **Plans, Coupons and Live Events are not in the sidebar.** `/admin/plans`
  is reachable from the "Create a subscription plan" nudge on the dashboard.
  `/admin/coupons` and `/admin/live-events` are reachable only by URL. Scripts
  08, 09 and 14 show the URL being typed.
- **Team management and Webhooks are placeholders.** The Members page "Team"
  tab and the Webhooks page both read "coming soon". There is no team-invite
  or webhooks script.
- **No custom domain settings in the operator admin.** Custom domains are set
  by a super admin. Script 16 says trial orgs cannot use one and stops there.
- **Early access has no expiry in the UI.** The Members page has Grant and
  Revoke buttons but no date field, although the Gherkin scenarios describe
  one. Script 11 shows Grant/Revoke and does not mention expiry.
- **No publish button on videos.** A video appears on the viewer site as soon
  as Mux reports it "Ready" and it sits in a visible row or collection. The
  `published` flag is never set from the admin, so the dashboard "Published
  Videos" KPI reads 0 for operator uploads. Scripts 02 and 05 describe the
  real behavior and never mention the KPI.
