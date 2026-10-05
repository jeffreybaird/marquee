#!/usr/bin/env bash
# Enroll the configured demo service host using the new release after a swap.
# This only configures/enqueues; the release helper never starts job queues.
set -euo pipefail
stack_dir="${1:?Missing stack directory}"
app_name="${2:?Missing release application name}"
module="${3:?Missing release module}"
demo_host="${4-}"
[[ -n "$demo_host" ]] || exit 0
[[ "$app_name" =~ ^[a-z][a-z0-9_]*$ && "$module" =~ ^[A-Z][A-Za-z0-9_.]*$ ]] || {
  echo "Invalid release identity" >&2
  exit 1
}
cd "$stack_dir"
docker compose run --rm -e POOL_SIZE=2 migrate "bin/$app_name" eval \
  "case $module.Release.configure_admin_demo_host() do {:ok, _} -> :ok; _ -> IO.puts(:stderr, \"Admin demo bootstrap failed\"); System.halt(1) end"
