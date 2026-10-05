# Tenant hostnames

For automatic provisioning and migration of existing clients, follow
[automatic tenant domain provisioning](tenant-domain-provisioning.md). That
opt-in path gates each canonical URL on verified DNS and HTTPS readiness and
does not require per-client Terraform resources or deployments. The explicit
DNS/Caddy list below remains the manual provisioning path when automation is
disabled. Do not combine ownership of a DNS record without the documented
Terraform handoff.

Production tenant URLs use `https://<slug>-<platform-host>`. With
`PHX_HOST=marquee.jeffreybaird.com`, an organization whose stored slug is
`the-workshop` uses `https://the-workshop-marquee.jeffreybaird.com`.
`the-work-shop` is a different slug; this feature does not rename organizations.

## Configuration

| Setting | Purpose |
| --- | --- |
| `ORG_RESOLUTION` | `query_param` (default) or `hostname`; enable hostname mode only after DNS and certificates are ready. |
| `PHX_HOST` | Platform hostname; supplied by Compose from `DOMAIN`. |
| `TENANT_HOST_PATTERN` | Optional runtime pattern containing `{slug}`; defaults to `{slug}-<PHX_HOST>` in hostname mode. |
| `TENANT_SLUGS` | Comma-separated deployment list of tenant slugs whose explicit hostnames Caddy serves. |
| Terraform `tenant_slugs` | Set of the same tenant slugs; provisions explicit DNSimple A records pointing to the existing reserved IP. |

The deployment scripts and Terraform use `<slug>-<DOMAIN>`. A custom runtime
pattern requires corresponding separately provisioned DNS and edge configuration.
Do not change only the application pattern.

The DNS label including `-marquee` must fit the 63-character DNS label limit.
`*-marquee.jeffreybaird.com` is not a DNS wildcard. Explicit records avoid
claiming unrelated sibling hostnames under `jeffreybaird.com`.

## Request behavior

In configured hostname mode, the tenant host identifies the organization for
both HTTP requests and connected LiveViews. A query parameter, header, stale
session, or membership cannot change the organization on a tenant hostname.
Existing custom-domain resolution remains available in the application, but
this deployment does not automatically provision customer-owned domains.

Old platform-host GET/HEAD links with a known `org` parameter redirect to the
tenant hostname, preserving the path and other query parameters. Mutating
requests are not redirected. Development and staging retain query-parameter
resolution.

Platform operator administration and explicit super-admin impersonation remain
available on the platform hostname. Cookies remain host-only. A session on the
platform host is not transferred to a tenant host; users may need to sign in
again when moving between hosts. LiveView checks the request's own origin.

## Rollout

1. Verify each organization's stored slug. Keep the existing slug unless an
   organization rename is separately intended. Record the full tenant list for
   both Terraform and deployment configuration.
2. With the existing persistent-root backend and credentials configured, set
   `TF_VAR_database_backend=postgres` and
   `TF_VAR_tenant_slugs='["the-workshop"]'` (replace with the full actual list).
   Run `terraform -chdir=infra/persistent plan` and inspect that it adds only
   the intended DNS records. Apply the reviewed plan. Do not create a real
   `terraform.tfvars`; it overrides the bootstrap's environment inputs.
3. Confirm each hostname resolves to the reserved IP. Set the GitHub repository
   variable `TENANT_SLUGS` to the matching comma-separated list. Keep
   `ORG_RESOLUTION=query_param` for the first deployment. Deploy through the
   normal test-gated workflow so Caddy installs the explicit site addresses and
   obtains certificates. Other apps' site files remain independent.
4. Verify HTTPS certificate validity for every tenant hostname. Then set the
   repository variable `ORG_RESOLUTION=hostname` and redeploy through the normal
   workflow. No database migration or organization rename is required.
5. Check the tenant landing page, viewer login, operator login, connected
   LiveView navigation, passwordless email links, checkout return links, and
   platform super-admin impersonation. Verify an old `?org=` bookmark redirects
   to the intended host and a conflicting `?org=` on a tenant host cannot select
   another tenant.

Adding or renaming a tenant requires updating the explicit DNS and Caddy lists
before its canonical URL can be used. Removing a slug from the list removes its
DNS/edge provisioning on the next corresponding apply/deploy; review such a
change before applying it.

## Rollback

Set `ORG_RESOLUTION=query_param` and redeploy using the normal workflow to
restore query-based tenant links. Keep the tenant DNS/Caddy list while checking
the rollback so already shared hostnames retain valid certificates. Image
rollback also uses the configured tenant list; changing only the image does not
change repository variables. Verify platform login and query-based links after
rollback. Do not remove DNS or shared edge configuration as an emergency first
step.
