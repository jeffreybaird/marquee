#!/usr/bin/env bash
# Initialize only missing reviewed demo content before switching traffic.
set -euo pipefail
stack_dir="${1:?Missing stack directory}"
app_name="${2:?Missing release application name}"
module="${3:?Missing release module}"
[[ "$app_name" =~ ^[a-z][a-z0-9_]*$ && "$module" =~ ^[A-Z][A-Za-z0-9_.]*$ ]] || {
  echo "Invalid release identity" >&2
  exit 1
}
cd "$stack_dir"
docker compose run --rm -e POOL_SIZE=2 migrate "bin/$app_name" eval \
  "case $module.Release.seed_missing_demo_content() do {:ok, _} -> :ok; _ -> IO.puts(:stderr, \"Demo content bootstrap failed\"); System.halt(1) end"
