#!/usr/bin/env bash
# Render explicit Caddy addresses. Validate all input before touching the edge.
set -euo pipefail

fail() { printf 'tenant-hosts: %s\n' "$*" >&2; exit 1; }

valid_domain() {
  local host="$1" label
  [[ "$host" != *$'\n'* && "$host" != *$'\r'* ]] || return 1
  [[ ${#host} -le 253 && "$host" != *..* && "$host" != .* && "$host" != *. ]] || return 1
  local labels=()
  IFS='.' read -r -a labels <<< "$host"
  for label in "${labels[@]}"; do
    [[ ${#label} -le 63 && "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || return 1
  done
  [[ ${#labels[@]} -gt 0 ]]
}

domain="${DOMAIN:-}"
slugs="${TENANT_SLUGS:-}"
valid_domain "$domain" || fail 'DOMAIN must be a valid lowercase hostname'
addresses="$domain"
if [[ -n "$slugs" ]]; then
  [[ "$slugs" != ,* && "$slugs" != *, && "$slugs" != *,,* ]] || fail 'TENANT_SLUGS contains an empty slug'
  [[ "$slugs" != *$'\n'* && "$slugs" != *$'\r'* ]] || fail 'TENANT_SLUGS contains a newline'
  IFS=',' read -r -a tenants <<< "$slugs"
  for slug in "${tenants[@]}"; do
    [[ "$slug" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || fail 'invalid tenant slug'
    valid_domain "$slug-$domain" || fail 'tenant hostname exceeds DNS limits'
    addresses+=", $slug-$domain"
  done
fi
printf '%s\n' "$addresses"
