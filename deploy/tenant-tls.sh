#!/usr/bin/env bash
# Render/apply one explicitly owned on-demand TLS permission policy. All other
# apps keep their static site files and certificates. No Docker socket is exposed.
set -euo pipefail
fail() { printf 'tenant-tls: %s\n' "$*" >&2; exit 1; }
script_dir="$(cd "$(dirname "$0")" && pwd)"
action="${1:-}"
destination="${2:-}"
[[ -n "$destination" ]] || fail 'destination is required'
[[ "${TENANT_TLS_ON_DEMAND:-false}" == true ]] || fail 'TENANT_TLS_ON_DEMAND must be true'
[[ "${APP_SLUG:-}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || fail 'invalid APP_SLUG'
DOMAIN="${DOMAIN:-}" TENANT_SLUGS='' bash "$script_dir/tenant-hosts.sh" >/dev/null
default_pattern="{slug}-${DOMAIN}"
pattern="${TENANT_HOST_PATTERN:-$default_pattern}"
# The shared edge supports exactly the app's managed sibling namespace.
[[ "$pattern" == "{slug}-${DOMAIN}" ]] || fail 'managed namespace must be {slug}-DOMAIN'
escaped_domain="${DOMAIN//./\\.}"

render() {
  local out="$1"
  mkdir -p "$out"
  cat > "$out/global.options" <<EOF
{
  on_demand_tls {
    ask http://127.0.0.1:9080/internal/tenant-domains/ask
  }
}
EOF
  cat > "$out/${APP_SLUG}.caddy" <<EOF
${DOMAIN} {
  reverse_proxy ${APP_SLUG}-blue:4000 ${APP_SLUG}-green:4000 {
    lb_try_duration 30s
    lb_try_interval 250ms
    fail_duration 10s
  }
}
https:// {
  tls {
    on_demand
  }
  @managed expression \`{http.request.host}.matches(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?-${escaped_domain}$')\`
  handle @managed {
    reverse_proxy ${APP_SLUG}-blue:4000 ${APP_SLUG}-green:4000 {
      lb_try_duration 30s
      lb_try_interval 250ms
      fail_duration 10s
    }
  }
  handle {
    respond 404
  }
}
EOF
  cat > "$out/${APP_SLUG}-ask.caddy" <<EOF
http://127.0.0.1:9080 {
  bind 127.0.0.1
  @permission path /internal/tenant-domains/ask
  handle @permission {
    reverse_proxy ${APP_SLUG}-blue:4000 ${APP_SLUG}-green:4000 {
      header_up X-Forwarded-Proto https
      lb_try_duration 10s
      lb_try_interval 250ms
      fail_duration 10s
    }
  }
  handle {
    respond 403
  }
}
EOF
}

check_owner() {
  local root="$1" owner body expected
  [[ -f "$root/Caddyfile" ]] || fail 'shared Caddyfile is missing'
  owner="$(sed -n 's/^# marquee-tenant-tls owner=//p' "$root/Caddyfile")"
  [[ -z "$owner" || "$owner" == "$APP_SLUG" ]] || fail 'another app owns the global TLS policy'
  body="$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$root/Caddyfile")"
  if [[ -z "$owner" ]]; then
    [[ "$body" == 'import /etc/caddy/sites/*.caddy' ]] || fail 'unrecognized global Caddy configuration'
  else
    expected="$(printf 'import /etc/caddy/sites/%s-tenant.options\nimport /etc/caddy/sites/*.caddy' "$APP_SLUG")"
    [[ "$body" == "$expected" ]] || fail 'owned global Caddy configuration has changed'
  fi
  # A foreign options fragment or another catch-all must not be adopted silently.
  for file in "$root"/sites/*-tenant.options "$root"/sites/*-ask.caddy; do
    [[ -e "$file" ]] || continue
    case "$(basename "$file")" in
      "${APP_SLUG}-tenant.options"|"${APP_SLUG}-ask.caddy") ;;
      *) fail 'another app has a managed TLS fragment' ;;
    esac
  done
}

apply_config() {
  local root="$1" stage stage_name file target
  check_owner "$root"
  exec 9> "$root/.tenant-tls.lock"
  flock -x 9
  check_owner "$root"
  mkdir -p "$root/sites"
  stage="$(mktemp -d "$root/sites/.tenant-stage.XXXXXX")"
  stage_name="$(basename "$stage")"
  trap 'rm -rf "$stage"' EXIT
  mkdir "$stage/backup"
  cp "$root/Caddyfile" "$stage/backup/Caddyfile"
  for file in "$root"/sites/*.caddy; do
    [[ -f "$file" ]] && cp "$file" "$stage/"
  done
  for target in "${APP_SLUG}.caddy" "${APP_SLUG}-ask.caddy" "${APP_SLUG}-tenant.options"; do
    [[ ! -f "$root/sites/$target" ]] || cp "$root/sites/$target" "$stage/backup/$target"
  done
  render "$stage"
  printf 'import /etc/caddy/sites/%s/global.options\nimport /etc/caddy/sites/%s/*.caddy\n' "$stage_name" "$stage_name" > "$stage/Caddyfile"
  (
    cd "$root"
    docker compose exec -T caddy caddy validate --config "/etc/caddy/sites/$stage_name/Caddyfile" --adapter caddyfile
  ) || fail 'candidate validation failed; previous configuration preserved'
  printf '# marquee-tenant-tls owner=%s\nimport /etc/caddy/sites/%s-tenant.options\nimport /etc/caddy/sites/*.caddy\n' "$APP_SLUG" "$APP_SLUG" > "$stage/live.Caddyfile"
  mv "$stage/global.options" "$root/sites/${APP_SLUG}-tenant.options"
  mv "$stage/${APP_SLUG}.caddy" "$root/sites/${APP_SLUG}.caddy"
  mv "$stage/${APP_SLUG}-ask.caddy" "$root/sites/${APP_SLUG}-ask.caddy"
  # Caddyfile is a direct bind mount. Preserve its inode so the running container
  # sees the new bytes; only directory-mounted site files may use atomic rename.
  cat "$stage/live.Caddyfile" > "$root/Caddyfile"
  if (cd "$root" && docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile); then
    rm -rf "$stage"
    trap - EXIT
    return
  fi
  cat "$stage/backup/Caddyfile" > "$root/Caddyfile"
  for target in "${APP_SLUG}.caddy" "${APP_SLUG}-ask.caddy" "${APP_SLUG}-tenant.options"; do
    if [[ -f "$stage/backup/$target" ]]; then
      mv "$stage/backup/$target" "$root/sites/$target"
    else
      rm -f "$root/sites/$target"
    fi
  done
  (cd "$root" && docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile) || true
  fail 'reload failed; previous configuration restored'
}

case "$action" in
  render) render "$destination" ;;
  apply) apply_config "$destination" ;;
  check) check_owner "$destination" ;;
  *) fail 'expected render or apply' ;;
esac
