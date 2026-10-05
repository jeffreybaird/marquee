# Automatic tenant domain provisioning

This backend provisions `<slug>-marquee.jeffreybaird.com` through DNSimple and
Caddy. It does not add onboarding screens, change subscriptions, or require
existing organizations to complete a payment flow. An explicit reviewed
migration enrolls existing organizations through the same backend API available
to future authorized callers.

## Allocation and readiness

Each enrolled organization has one durable hostname allocation. The allocation
records eligibility, its immutable hostname and generation, DNS record identity,
provisioning state, sanitized errors, and readiness time. A changed slug or
namespace cannot silently reassign an allocation. A ready allocation remains
the canonical hostname; changing that hostname is a separate migration.

The worker reconciles DNS before checking HTTPS. DNS reconciliation creates an
A record only when the exact name has no conflicting address or alias records,
or adopts a single existing A record already pointing to the configured reserved
IP. Non-routing records such as TXT may coexist. Conflicting records,
including another target, AAAA/CNAME records, or duplicates, are not overwritten
or deleted. A timed-out creation is reconciled by listing again before another
create attempt.

The `dns_ready` state allows Caddy to request a certificate. It does not make
the hostname canonical. The worker must verify public DNS, a trusted HTTPS
connection for that hostname, and the application's allocation identity before
marking it `ready`. Provider failures remain retryable or become visible failed
allocations; they do not move clients to a broken URL.

With automatic provisioning enabled, pending, failed, and unenrolled
organizations retain their platform `?org=` links and sessions. Ready
organizations use their stored hostname. Host-based tenant identity remains
authoritative over query parameters and stale sessions. Session cookies remain
host-only, so moving to the hostname can require a fresh sign-in.

## Configuration

| Setting | Purpose |
| --- | --- |
| `TENANT_DOMAIN_PROVISIONING` | Opts the application into automatic provisioning and readiness-gated URLs. |
| `DNSIMPLE_ACCOUNT_ID` | DNSimple account owning the configured zone. |
| `DNSIMPLE_API_TOKEN` | Secret granting the required DNS record access. Never commit or print it. |
| `TENANT_DNS_ZONE` | Managed zone, such as `jeffreybaird.com`. |
| `TENANT_DNS_TARGET_IPV4` | The app's reserved public IPv4 address. |
| `TENANT_HOST_PATTERN` | Managed hostname pattern, such as `{slug}-marquee.jeffreybaird.com`. |
| `TENANT_TLS_ON_DEMAND` | Opts the shared edge into managed-namespace dynamic TLS/routing. |

The feature is opt-in. No DNS provider calls occur during dry-run, snapshot
application, or deployment. DNS and HTTPS operations run in the application's
background worker after an explicit enrollment has created durable intent.

## Shared edge requirements

Caddy's on-demand certificate permission check is global. The managed edge
configuration has one explicit owner and must reject a conflicting owner or
unknown global configuration before changing files. Candidate configuration is
validated with the existing app sites before a controlled reload. Other static
site files remain intact.

A private loopback HTTP listener routes permission requests to either active
blue/green application instance. Its upstream scheme header avoids Phoenix's
HTTPS redirect without making the permission check depend on a tenant
certificate. The permission endpoint only authorizes exact persisted, eligible,
active managed hostnames in DNS-ready or ready states. It never calls DNSimple
or provisions anything while handling a TLS handshake.

The edge image is pinned to Caddy 2.11.6-alpine, which includes the current
security fix. Its defaults include a 16 KiB request-header limit, one-minute
stalled I/O timeouts, removal of dotted headers, and stricter configuration
validation. Validate all shared sites and any unusual client header requirements
when upgrading from 2.11.4; the managed Marquee site uses none of the affected
custom configuration features.

All apps sharing this Caddy instance must preserve the managed global import.
An unrelated deployment template that overwrites the top-level Caddyfile with
an old import-only template is incompatible with automatic issuance. Review
and coordinate those templates before activation. The application requires no
Docker socket or Caddy admin API access.

## Existing-client migration

1. Deploy schema and code with automation disabled. Keep current URLs working.
2. Install and validate the compatible dynamic edge configuration. Confirm the
   private permission relay reaches the active application across a blue/green
   swap. Keep unrelated shared sites in the validation set.
3. Configure the application credentials, zone, target, and pattern, then enable
   automatic provisioning. Existing clients continue on legacy URLs until
   their own allocation becomes ready; a global `ORG_RESOLUTION` cutover is
   unnecessary.
4. Generate a read-only migration snapshot with an explicit slug allowlist when
   choosing clients from a deployment that also contains demo/test tenants.
   Review organization IDs, slugs, generated hostnames, cutoff, and next cursor.
   The snapshot contains no user email addresses or credentials.
5. Apply the reviewed snapshot. Only its listed organizations are explicitly
   grandfathered and enqueued. Repeating the same application is idempotent.
   Continue with further pages using the same cutoff and returned cursor.
6. Inspect per-organization status. Retry failed allocations after fixing their
   reported cause. Do not resolve a DNS conflict by blindly replacing a record.
7. Verify each ready hostname's landing page, sign-in email, connected LiveView,
   and redirect from an old bookmark. Existing payment configuration is retained.

Release operations use `bin/marquee eval`; distributed Erlang `rpc` access is
not required. Dry-run and status start only the required database components.
Snapshot application starts only the services needed to persist jobs and audit
events, with Oban queues/plugins disabled in that release process. Network work
runs in the already deployed application, not the one-off release command.

For example, run these inside the configured release container (replace the
slug allowlist with the reviewed client selection):

```sh
bin/marquee eval 'Marquee.Release.tenant_domain_snapshot(slugs: ["the-workshop"], page_size: 100)'
bin/marquee eval 'Marquee.Release.tenant_domain_apply("/app/tenant-domain-plan.json")'
bin/marquee eval 'Marquee.Release.tenant_domain_status(page: 1, per_page: 100)'
bin/marquee eval 'Marquee.Release.tenant_domain_retry("ORGANIZATION_UUID")'
```

Save the snapshot's JSON object as the reviewed plan file and mount or copy it
into the release container before applying. Keep diagnostic log lines out of
the JSON file. Applying a plan validates its contents again and does not replace
its selection with a fresh query for every active organization. A retry names
one existing allocation; it is not an enrollment of all organizations.

The migration API is paginated. Its second-precision cutoff excludes the current
in-flight second so an organization created after the snapshot cannot sneak into
the same page. Later organizations require a new explicit review/enrollment.

## Terraform ownership handoff

Automatic provisioning does not require a Terraform resource or deployment for
each client. If an existing tenant A record is already Terraform-managed, hand
off ownership deliberately before retiring its old configuration:

1. Confirm the DNS name and target match the intended allocation and back up
   Terraform state privately. State may contain secrets; do not paste it into
   logs or commit it.
2. Record the exact tenant record resource address with `terraform state list`.
3. Remove only that address from Terraform state with `terraform state rm`.
   This forgets ownership and does not delete the provider record.
4. Remove the corresponding legacy tenant declaration and inspect a plan.
   It must neither destroy the adopted DNS record nor recreate a duplicate.
5. Let the provisioner adopt the unchanged exact A record through its normal
   reconciliation path. Verify the stored provider record ID and readiness.

Never apply a plan that destroys client records as part of this handoff. Do not
remove the reserved IP or platform DNS resources. A deployment with no existing
tenant records needs no state handoff.

## Rollback

Disable application automation to stop new enrollment/provisioning and restore
legacy platform query URLs. Preserve allocations and provider records; no
automatic DNS deletion is performed. The deployment and rollback workflows tie
the dynamic edge flag to application provisioning. Running either workflow with
provisioning disabled restores the static application site, so previously shared
tenant URLs may stop serving even though their DNS records remain. To preserve
those URLs during rollback, explicitly retain their static `TENANT_SLUGS` and
certificate configuration, set `ORG_RESOLUTION=hostname`, and retain the matching
`TENANT_HOST_PATTERN` before switching away from the dynamic route. Static edge
routing alone cannot restore tenant resolution when the application is in query
mode with provisioning disabled.

Keep certificate storage and unrelated shared-site files intact. The managed
global permission fragments are preserved; disabling the application flag does
not remove them. An image rollback alone does not reset repository variables or
remove database state. Review both application and edge configuration before
claiming a rollback preserves already migrated client URLs.
