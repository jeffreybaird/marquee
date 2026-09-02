#!/bin/bash
#
# SessionStart hook for Claude Code on the web.
#
# Installs the pinned BEAM toolchain, a local Postgres, a Linux chromedriver
# matching the container's Chromium, and the project's deps so `mix test`,
# `mix marquee.verify`, `mix credo` and `mix format` work in a fresh remote
# container. Ubuntu's packaged Erlang is far too old (OTP 25 on noble) and this
# project needs OTP 28 / Elixir 1.19, so the toolchain comes from the same
# precompiled builds erlef/setup-beam uses in CI rather than from apt.
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

## Chrome / chromedriver ------------------------------------------------------

# `mix test` boots Wallaby unconditionally (test/test_helper.exs starts the
# :wallaby app), and Wallaby's app start validates BOTH a chromedriver and a
# Chrome binary — without both the whole suite aborts before the first test,
# not just the `--only e2e` flows. The container ships Playwright's Chromium
# but no usable Linux chromedriver: the one committed under chromedriver/ is a
# macOS-arm build, and the stray /opt/node22/bin/chromedriver is a different
# major version that Chrome would reject at session start. So fetch a
# chromedriver whose version matches the installed Chromium from Chrome for
# Testing, and put both binaries on PATH under a dedicated dir that outranks
# the mismatched node one. Config stays untouched: Wallaby's default lookup
# searches PATH for `chromedriver` and `chromium`, which keeps macOS dev and CI
# on their own toolchains.

WALLABY_BIN="/opt/wallaby-bin"

# Find a Chrome/Chromium binary. Prefer one already on PATH, else fall back to
# the Playwright build (outside PATH, under a private name). readlink -f
# resolves to the real executable so relinking on a cached run can't form a
# self-referential symlink.
CHROME_BIN=""
for candidate in \
  "$(command -v chromium 2>/dev/null || true)" \
  "$(command -v chromium-browser 2>/dev/null || true)" \
  "$(command -v google-chrome 2>/dev/null || true)" \
  "$(command -v google-chrome-stable 2>/dev/null || true)" \
  "${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}/chromium" \
  "/opt/pw-browsers/chromium"; do
  if [ -n "$candidate" ] && { [ -x "$candidate" ] || [ -L "$candidate" ]; }; then
    CHROME_BIN="$(readlink -f "$candidate")"
    break
  fi
done

if [ -z "$CHROME_BIN" ] || [ ! -x "$CHROME_BIN" ]; then
  echo "session-start: WARNING no Chrome/Chromium binary found — Wallaby will not start, so mix test cannot boot" >&2
else
  CHROME_VERSION="$("$CHROME_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if [ -z "$CHROME_VERSION" ]; then
    echo "session-start: WARNING could not read a version from $CHROME_BIN — skipping chromedriver provisioning" >&2
  else
    CHROME_MAJOR="${CHROME_VERSION%%.*}"
    CHROMEDRIVER_DIR="/opt/chromedriver/$CHROME_VERSION"
    CFT_BASE="https://storage.googleapis.com/chrome-for-testing-public"

    # Marker-guarded like the BEAM installs: a missing marker means reinstall,
    # so an interrupted run heals, and a Chromium bump installs a fresh driver.
    if [ ! -f "$CHROMEDRIVER_DIR/.install-complete" ]; then
      echo "session-start: installing chromedriver for Chromium $CHROME_VERSION"

      ARCH="$(dpkg --print-architecture)"
      if [ "$ARCH" != "amd64" ]; then
        echo "session-start: WARNING arch is $ARCH but Chrome for Testing only ships a linux64 chromedriver" >&2
      fi

      TMP="$(mktemp -d)"
      trap 'as_root rm -rf "$TMP"' EXIT

      # Chrome for Testing publishes a chromedriver per Chromium release. Prefer
      # the exact version; fall back to the milestone's latest build if that
      # exact one was never published (same major keeps Chrome from rejecting
      # the session — Wallaby only warns on a patch mismatch).
      DRIVER_URL="$CFT_BASE/$CHROME_VERSION/linux64/chromedriver-linux64.zip"
      if ! curl -fsSL "$DRIVER_URL" -o "$TMP/chromedriver.zip"; then
        echo "session-start: exact chromedriver $CHROME_VERSION not published — falling back to milestone $CHROME_MAJOR latest"
        MILESTONE_JSON="https://googlechromelabs.github.io/chrome-for-testing/latest-versions-per-milestone.json"
        DRIVER_VERSION="$(curl -fsSL "$MILESTONE_JSON" \
          | grep -oE "\"$CHROME_MAJOR\":\{[^}]*\"version\":\"[0-9.]+\"" \
          | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
        if [ -z "$DRIVER_VERSION" ]; then
          echo "session-start: could not resolve a chromedriver for Chromium major $CHROME_MAJOR" >&2
          exit 1
        fi
        curl -fsSL "$CFT_BASE/$DRIVER_VERSION/linux64/chromedriver-linux64.zip" -o "$TMP/chromedriver.zip"
      fi

      unzip -q "$TMP/chromedriver.zip" -d "$TMP"
      as_root rm -rf "$CHROMEDRIVER_DIR"
      as_root mkdir -p "$CHROMEDRIVER_DIR"
      # The published zip nests the binary under chromedriver-linux64/.
      as_root install -m 0755 "$TMP/chromedriver-linux64/chromedriver" "$CHROMEDRIVER_DIR/chromedriver"
      as_root touch "$CHROMEDRIVER_DIR/.install-complete"

      as_root rm -rf "$TMP"
      trap - EXIT
    fi

    # Expose both binaries under the names Wallaby's Linux lookup expects. This
    # dir is prepended to PATH below so its `chromedriver` outranks the stray,
    # mismatched /opt/node22/bin/chromedriver. Symlinks are refreshed every run
    # so a cached driver install still gets wired up.
    as_root mkdir -p "$WALLABY_BIN"
    as_root ln -sf "$CHROMEDRIVER_DIR/chromedriver" "$WALLABY_BIN/chromedriver"
    as_root ln -sf "$CHROME_BIN" "$WALLABY_BIN/chromium"
    export PATH="$WALLABY_BIN:$PATH"
    echo "session-start: chromedriver ready — $(chromedriver --version | head -1)"
  fi
fi

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

## Frontend toolchain ---------------------------------------------------------

# CI type-checks and unit-tests assets/ with the npm packages locked in
# assets/package-lock.json (see .github/workflows/ci.yml). Node 22 ships in the
# remote container image; install the same locked packages so
# `npm run typecheck --prefix assets` and `npm test --prefix assets` match CI.
if command -v npm >/dev/null 2>&1; then
  echo "session-start: installing assets npm packages"
  npm ci --prefix assets --no-audit --no-fund >/dev/null
else
  echo "session-start: npm not found; skipping the assets toolchain (no type-check or JS tests)" >&2
fi

## Frontend assets ------------------------------------------------------------

# Wallaby e2e drives real browser pages whose interactive controls (modals,
# method=post buttons, live navigation) need the compiled JS/CSS bundle. Without
# it those pages are inert and the browser tests fail even though they load. CI
# builds assets before `mix test --only e2e`; do the same here so the e2e suite
# is runnable. assets.setup installs the tailwind + esbuild binaries (idempotent,
# --if-missing); assets.build writes priv/static/assets, which Plug.Static then
# serves. Runs after the npm install above so esbuild can resolve any package
# imports. Only worth doing when a browser was actually wired up above.
if [ -x "$WALLABY_BIN/chromedriver" ]; then
  echo "session-start: building frontend assets for e2e"
  mix assets.setup >/dev/null
  mix assets.build >/dev/null
fi

## Persist the environment for the session ------------------------------------

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  # WALLABY_BIN goes first so its chromedriver outranks /opt/node22/bin's
  # mismatched one. Only add it when it was actually populated this run.
  WALLABY_PATH_PREFIX=""
  if [ -x "$WALLABY_BIN/chromedriver" ]; then
    WALLABY_PATH_PREFIX="$WALLABY_BIN:"
  fi
  {
    echo "export PATH=\"$WALLABY_PATH_PREFIX$ELIXIR_DIR/bin:$OTP_DIR/bin:\$PATH\""
    echo 'export LANG="C.UTF-8"'
    echo 'export LC_ALL="C.UTF-8"'
  } >> "$CLAUDE_ENV_FILE"
fi

echo "session-start: ready — $(elixir --version | tail -1)"
