# Private Wanderlust TV admin demo

## Scope

This demo uses private, disposable workspaces styled as a travel channel. It
never edits the real Wanderlust TV organization or the Workshop subscriber demo.
Each visitor receives a separate organization, an admin-role synthetic user,
and a separate disabled synthetic owner preserving the ownership invariant.
Normal operator authentication is retained independently.

Visitors can edit video metadata and publication state, soft-remove sample
videos, manage collections/series/seasons, arrange homepage rows, and change
supported branding colors, fonts, and layouts. Private viewer preview reflects
those edits. An approved sample-clip library replaces provider uploads. Sample
analytics are visibly labeled. The normal dashboard and optional tour are reused.
Billing, payments, invitations, webhooks, domains, uploads, and live broadcasting
are explanation-only in this environment.

Each new workspace includes six sample members with varied local access and
private viewing activity, plus two podcast shows. Operators can manage member
status/access and edit local podcast-show metadata. No playable podcast episodes
are invented, and feed synchronization, uploads, feed tokens, and external
publication remain unavailable. Existing workspaces receive these samples on
Reset demo; their current edits are not replaced automatically.

View as opens the selected sample member's read-only viewer experience,
including their saved content and account summary. A named banner provides a
return to Members. The selected identity is separate from normal viewer and
operator authentication, restricted to the current sandbox, and invalidated by
reset, expiry, exit, or feature disablement. Sample members cannot obtain normal
viewer authentication tokens or enter registration and magic-link workflows.

Unavailable integrations retain recognizable read-only pages with labeled sample
cards and disabled external actions. The audit page displays the workspace's
own events without export. Provider callbacks and unsupported mutation routes
remain blocked; hiding controls is not the authorization boundary.

## Sessions and limits

The dedicated host is configured with `ADMIN_DEMO_HOST`, expected to be
`admin-demo-marquee.jeffreybaird.com`. `ADMIN_DEMO_ENABLED` defaults to false.
A CSRF-protected POST creates or resumes a workspace. A separate
`admin_demo_token` session key never overwrites the real operator token. Only
the configured demo host accepts this identity. Every connected event and
context mutation revalidates persisted session expiry and resource ownership.
Disabling the feature denies both new entry and continued request/event access;
cleanup continues independently.

Sessions last two hours. A stable server-issued entry nonce makes duplicate
entry requests return the same workspace; reset creates one replacement even
under concurrent requests. Failed reset leaves the old workspace valid. Start
and reset are limited to three requests per IP per minute, with at most 100
active workspaces globally, enforced transactionally. Exit revokes the demo
session and returns to the platform. Responses are private and uncached.

The persistent demo bar identifies the private workspace, its expiry, and
Preview site, Reset demo, and Exit actions. Synthetic users cannot enter normal
registration, invitation, password, confirmation, or magic-link workflows.

## Media and template

The root-owned catalog is `priv/admin_demo/wanderlust_catalog.json`; see
[media provenance](wanderlust-admin-demo-media.md). It contains a version and
60 licensed travel shorts: 48 initial clips and 12 extras. Each of the four
collections starts with 12 clips and has three additional approved clips.
Initial clips are
organized into collections, series/seasons, curated homepage rows, and travel
heroes. Source and creator attribution remains visible, with a prominent Pexels
credit link. These are short travel clips, not full-length documentaries.

New workspaces and Reset demo use the current catalog version. Existing active
workspaces retain their content and edits until reset; they are not backfilled.
Private demo Browse shows the complete bounded catalog, including added clips.

Sandbox videos copy approved playback references and never own the shared Mux
assets. Their `mux_asset_id` is nil. A permanent protected-asset registry also
blocks deletion independently of sandbox lifetime. Sample insertion accepts
only a server-known catalog slug; pasted provider IDs and remote URLs are not
accepted. Provider side effects are denied in contexts and background workers,
not merely hidden in navigation.

## Retention

This is an explicit disposable-demo policy, separate from ordinary customer
data and audit retention:

- Access is revoked at expiry, reset, or exit.
- Disposable workspace content and activity are purged after 24 hours.
- Minimal demo audit and session records are retained for 30 days.
- Minimal non-customer organization tombstones and protected media records
  remain to reject late jobs and replayed entry keys.

Cleanup is bounded and retryable. Late workers reject demo organizations and
protected assets when they execute, including after disposable data is purged. Sandbox and
service organizations are excluded from actual customer reports and automation.

## Rollout

The permanent marked service organization provisions the dedicated hostname
once through the existing tenant-domain backend. Host bootstrap and certificate
readiness work while admin-demo access is disabled. Enable the feature and
platform entry link only after the host and reviewed media are ready. Existing
DNS/TLS challenge endpoints are independent of demo authentication.

For rollback, disable `ADMIN_DEMO_ENABLED` on the current application version.
Do not return blindly to an older image whose reporting and automation do not
recognize non-customer demo organizations.

The test-gated deployment performs the following sequence:

1. Keep `ADMIN_DEMO_ENABLED=false` and configure `ADMIN_DEMO_HOST`.
2. Discover Caddy's current address on the shared `edge` network and write
   `ADMIN_DEMO_TRUSTED_PROXY_IP` into the application's environment.
3. Migrate and swap to the new application image, stopping the old workers.
4. Run `Marquee.Release.configure_admin_demo_host/0` from the new image.
   This idempotently registers the approved media and enqueues the exact
   service hostname through the existing provisioning backend. It works while
   demo access is disabled and does not start another worker pool.
5. Verify hostname readiness, DNS and trusted HTTPS, then enable the feature
   and deploy again. The platform entry link appears only when enabled and ready.

An empty host skips automatic bootstrap. A bootstrap error fails the deployment
job without restarting old workers; the disabled new application remains in
place for diagnosis. The release API can also be invoked with `bin/marquee eval`
for an authorized operational retry; treat an error tuple as failure.

The demo limiter trusts a forwarded client address only from the exact Caddy
peer discovered on the host. Other peers, multiple forwarded values, or invalid
addresses fall back to the connection address. Deployment and rollback refresh
the trusted peer automatically. After recreating Caddy independently, redeploy
the application to refresh that address; do not use a broad trusted subnet.

Normal rollback does not bootstrap demo hosts into an older image. Prefer the
flag-off procedure above because pre-demo images do not enforce demo isolation.
See [verification evidence](admin-demo-verification.md) for checks and limits.
