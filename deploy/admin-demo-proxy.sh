#!/usr/bin/env bash
# Refresh the exact shared Caddy peer trusted by this app's demo entry limiter.
# Run after preparing the edge and before starting either app color.
set -euo pipefail

stack_dir="${1:?Usage: admin-demo-proxy.sh STACK_DIR}"
env_file="$stack_dir/.env"
test -f "$env_file"

container_id="$(docker compose -f /root/caddy/compose.yaml ps -q caddy)"
[[ -n "$container_id" && "$container_id" != *$'\n'* ]] || {
  echo "Expected one running Caddy container" >&2
  exit 1
}
edge_ip="$(docker inspect --format '{{(index .NetworkSettings.Networks "edge").IPAddress}}' "$container_id")"

# Docker's shared edge bridge is IPv4. Refuse missing or malformed discovery
# before touching the existing environment, including embedded shell/newline data.
[[ "$edge_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || {
  echo "Caddy has no valid edge IPv4 address" >&2
  exit 1
}
IFS=. read -r -a octets <<< "$edge_ip"
for octet in "${octets[@]}"; do
  (( 10#$octet <= 255 )) || { echo "Invalid Caddy edge address" >&2; exit 1; }
done

umask 077
candidate="$(mktemp "$stack_dir/.env.proxy.XXXXXX")"
trap 'rm -f "$candidate"' EXIT
awk '!/^ADMIN_DEMO_TRUSTED_PROXY_IP=/' "$env_file" > "$candidate"
printf 'ADMIN_DEMO_TRUSTED_PROXY_IP=%s\n' "$edge_ip" >> "$candidate"
mv "$candidate" "$env_file"
