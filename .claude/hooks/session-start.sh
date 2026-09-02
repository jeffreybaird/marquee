#!/bin/bash
#
# SessionStart hook for Claude Code on the web.
#
# Installs the pinned BEAM toolchain, a local Postgres, and the project's deps
# so `mix test`, `mix marquee.verify`, `mix credo` and `mix format` work in a
# fresh remote container. Ubuntu's packaged Erlang is far too old (OTP 25 on
# noble) and this project needs OTP 28 / Elixir 1.19, so the toolchain comes
# from the same precompiled builds erlef/setup-beam uses in CI rather than
# from apt.
#
# Versions are parsed from the Dockerfile ARGs — the single source of truth
# CI already reads (see .github/workflows/ci.yml) — so bumping the pin there
# updates local, CI and remote sessions together.
#
# Idempotent: everything below is skipped when it is already in place, which
# is the common case once the container image has been cached.

set -euo pipefail

# Local sessions bring their own toolchain; only fix up the remote container.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"

BEAM_ROOT="/opt/beam"

as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

# Run a command as the `postgres` OS user. `sudo -u` switches user, but as root
# there is no sudo in play, so use runuser to drop to postgres either way.
as_postgres() {
  if [ "$(id -u)" -eq 0 ]; then runuser -u postgres -- "$@"; else sudo -u postgres "$@"; fi
}

## Pinned versions ------------------------------------------------------------

ELIXIR_VERSION="$(grep -E '^ARG ELIXIR_VERSION=' Dockerfile | head -1 | cut -d= -f2)"
OTP_VERSION="$(grep -E '^ARG OTP_VERSION=' Dockerfile | head -1 | cut -d= -f2)"

if [ -z "$ELIXIR_VERSION" ] || [ -z "$OTP_VERSION" ]; then
  echo "session-start: could not parse ELIXIR_VERSION/OTP_VERSION from Dockerfile" >&2
  exit 1
fi

OTP_MAJOR="${OTP_VERSION%%.*}"
OTP_DIR="$BEAM_ROOT/otp-$OTP_VERSION"
ELIXIR_DIR="$BEAM_ROOT/elixir-$ELIXIR_VERSION-otp-$OTP_MAJOR"

## System packages ------------------------------------------------------------

# build-essential: bcrypt_elixir compiles a C NIF.
# libncurses6/libssl3t64: the precompiled OTP links against them.
# postgresql: `mix test` runs against a real Postgres (Ecto), unlike CI's
# service container this session has to start its own.
PACKAGES="build-essential git curl unzip libncurses6 libssl3t64 postgresql"
MISSING=""
for pkg in $PACKAGES; do
  dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "^install ok installed$" || MISSING="$MISSING $pkg"
done

if [ -n "$MISSING" ]; then
  echo "session-start: installing system packages:$MISSING"
  as_root apt-get update -qq
  # shellcheck disable=SC2086
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $MISSING
fi

## Erlang/OTP -----------------------------------------------------------------

# Both toolchains are guarded by a marker written only once the install has
# fully succeeded, never by the presence of the binary. A run interrupted
# between unpacking and finalising leaves a tree that looks usable but is not
# (OTP in particular still carries its build-time prefix), and a guard on
# bin/erl would take that for a good toolchain and wedge every later session.
# A missing marker means "reinstall from scratch", so a partial tree heals.

if [ ! -f "$OTP_DIR/.install-complete" ]; then
  echo "session-start: installing Erlang/OTP $OTP_VERSION"
  . /etc/os-release
  ARCH="$(dpkg --print-architecture)"
  OTP_TARBALL="https://builds.hex.pm/builds/otp/$ARCH/$ID-$VERSION_ID/OTP-$OTP_VERSION.tar.gz"

  TMP="$(mktemp -d)"
  trap 'as_root rm -rf "$TMP"' EXIT
  curl -fsSL "$OTP_TARBALL" -o "$TMP/otp.tar.gz"

  as_root rm -rf "$OTP_DIR"
  as_root mkdir -p "$OTP_DIR"
  # The published tarball has a single top-level directory; strip it.
  as_root tar -xzf "$TMP/otp.tar.gz" -C "$OTP_DIR" --strip-components=1
  # Precompiled OTP records its build-time prefix; Install rewrites it. It
  # requires the tree to already sit at its final path, so this runs in place.
  as_root "$OTP_DIR/Install" -minimal "$OTP_DIR"
  as_root touch "$OTP_DIR/.install-complete"

  as_root rm -rf "$TMP"
  trap - EXIT
fi

export PATH="$OTP_DIR/bin:$PATH"

## Elixir ---------------------------------------------------------------------

if [ ! -f "$ELIXIR_DIR/.install-complete" ]; then
  echo "session-start: installing Elixir $ELIXIR_VERSION (OTP $OTP_MAJOR)"
  TMP="$(mktemp -d)"
  trap 'as_root rm -rf "$TMP"' EXIT
  curl -fsSL "https://builds.hex.pm/builds/elixir/v$ELIXIR_VERSION-otp-$OTP_MAJOR.zip" -o "$TMP/elixir.zip"

  as_root rm -rf "$ELIXIR_DIR"
  as_root mkdir -p "$ELIXIR_DIR"
  as_root unzip -q "$TMP/elixir.zip" -d "$ELIXIR_DIR"
  as_root touch "$ELIXIR_DIR/.install-complete"

  as_root rm -rf "$TMP"
  trap - EXIT
fi

export PATH="$ELIXIR_DIR/bin:$PATH"

# Erlang reads the locale to pick its filename encoding; without a UTF-8 one it
# falls back to latin1 and Elixir warns on every invocation.
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

## Postgres -------------------------------------------------------------------

# config/test.exs connects as postgres/postgres on localhost. Start the cluster
# apt just installed and make sure that role exists with that password. Both
# steps are no-ops when already done, so this is safe to run every session.
if ! as_root pg_lsclusters -h 2>/dev/null | grep -q online; then
  echo "session-start: starting Postgres"
  as_root service postgresql start
fi

# `postgres` is the bootstrap superuser; give it the password the test config
# expects. ALTER is idempotent, so no need to check first.
as_postgres psql -tAc "ALTER USER postgres WITH PASSWORD 'postgres';" >/dev/null

## Project dependencies -------------------------------------------------------

mix local.hex --force --if-missing >/dev/null
mix local.rebar --force --if-missing >/dev/null

echo "session-start: fetching and compiling deps"
mix deps.get >/dev/null

# Warm both envs. :test is what `mix marquee.verify` and `mix test` use, but a
# bare `mix credo` or `mix format` defaults to :dev, and leaving that cold turns
# the session's first lint into a full dependency build. MIX_ENV is deliberately
# not exported to the session — each mix task picks its usual default.
MIX_ENV=dev mix compile >/dev/null
MIX_ENV=test mix compile >/dev/null

## Persist the environment for the session ------------------------------------

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export PATH=\"$ELIXIR_DIR/bin:$OTP_DIR/bin:\$PATH\""
    echo 'export LANG="C.UTF-8"'
    echo 'export LC_ALL="C.UTF-8"'
  } >> "$CLAUDE_ENV_FILE"
fi

echo "session-start: ready — $(elixir --version | tail -1)"
