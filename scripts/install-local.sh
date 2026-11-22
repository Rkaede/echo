#!/usr/bin/env bash
#
# Build Echo from the current working tree and install it to /Applications.
#
#   scripts/install-local.sh         Release build -> /Applications/Echo.app
#   scripts/install-local.sh --dev   Debug build   -> /Applications/Echo Dev.app
#
# The Debug build has its own bundle id (io.littlecove.echo.dev), so it keeps
# separate settings, history, keys and permissions and can sit next to the
# release copy. It also has the debug menu items. Only one copy should run at a
# time, because both listen for the same shortcuts: installing one quits the
# other.
#
# This is the "use it every day" path, as opposed to scripts/release.sh, which
# also notarizes, builds a DMG and publishes an appcast. Notarization is only
# needed for apps that other people download; a locally built app never gets a
# quarantine flag, so Gatekeeper lets it run as-is.
#
# Signing uses a real Developer ID identity when one is present. That matters
# for more than formality: macOS keys microphone/accessibility grants and
# Keychain items to the code signing identity, so a stable identity means the
# permissions and the stored API key survive every reinstall. Ad-hoc signing
# (the fallback) produces a new identity on each build, and macOS re-asks for
# permissions every time.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="Echo"
BUILD_DIR="${PROJECT_DIR}/build/local"
RELEASE_INSTALL_PATH="/Applications/Echo.app"
DEV_INSTALL_PATH="/Applications/Echo Dev.app"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
info() { printf '  %s\n' "$1"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$1"; }
fail() { printf '\033[31m  ✗ %s\033[0m\n' "$1" >&2; exit 1; }

case "${1:-}" in
  "")
    CONFIGURATION="Release"
    INSTALL_PATH="$RELEASE_INSTALL_PATH"
    OTHER_INSTALL_PATH="$DEV_INSTALL_PATH"
    ;;
  --dev)
    CONFIGURATION="Debug"
    INSTALL_PATH="$DEV_INSTALL_PATH"
    OTHER_INSTALL_PATH="$RELEASE_INSTALL_PATH"
    ;;
  *)
    fail "Unknown option: $1 (use --dev for the Debug build)"
    ;;
esac

# Quits the copy of Echo installed at the given path, if it is running.
quit_app_at() {
  local path="$1"
  pgrep -f "^${path}/Contents/MacOS/Echo" >/dev/null 2>&1 || return 0
  info "Quitting the running ${path##*/}…"
  pkill -f "^${path}/Contents/MacOS/Echo" || true
  for _ in $(seq 1 20); do
    pgrep -f "^${path}/Contents/MacOS/Echo" >/dev/null 2>&1 || break
    sleep 0.25
  done
}

# --- Pick a signing identity ------------------------------------------------
# Preference order: Developer ID (stable, survives reinstalls) > Apple
# Development > any self-signed code signing cert > ad-hoc.
pick_identity() {
  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  local name
  for prefix in "Developer ID Application" "Apple Development" "Mac Developer"; do
    name="$(printf '%s\n' "$identities" \
      | grep -o "\"${prefix}[^\"]*\"" \
      | head -1 \
      | tr -d '"')"
    if [[ -n "$name" ]]; then
      printf '%s' "$name"
      return
    fi
  done

  # Any remaining codesigning identity, e.g. a self-signed cert made in
  # Keychain Access (Certificate Assistant > Create a Certificate >
  # Code Signing, self-signed root). Still a stable identity.
  name="$(printf '%s\n' "$identities" | grep -o '"[^"]*"' | head -1 | tr -d '"')"
  if [[ -n "$name" ]]; then
    printf '%s' "$name"
    return
  fi

  printf '%s' "-"
}

bold "Echo — local build and install"

SIGN_IDENTITY="$(pick_identity)"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  warn "No code signing identity found; falling back to ad-hoc signing."
  warn "macOS will re-ask for microphone and accessibility access after each rebuild,"
  warn "and the Keychain-stored API key will not carry over."
else
  info "Signing identity: ${SIGN_IDENTITY}"
fi

GIT_SHA="$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
GIT_DIRTY=""
if ! git -C "$PROJECT_DIR" diff --quiet HEAD 2>/dev/null; then
  GIT_DIRTY=" (uncommitted changes)"
fi
info "Source: ${GIT_SHA}${GIT_DIRTY}"

# --- Build ------------------------------------------------------------------
bold "Building ${CONFIGURATION}…"
BUILD_LOG="${BUILD_DIR}/xcodebuild.log"
mkdir -p "$BUILD_DIR"

set +e
xcodebuild build \
  -project "${PROJECT_DIR}/Echo.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  CODE_SIGN_STYLE="Manual" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  >"$BUILD_LOG" 2>&1
BUILD_STATUS=$?
set -e

if [[ $BUILD_STATUS -ne 0 ]]; then
  grep -E "error:|error " "$BUILD_LOG" | head -20 >&2 || true
  fail "Build failed. Full log: ${BUILD_LOG}"
fi

APP_PATH="${BUILD_DIR}/Build/Products/${CONFIGURATION}/Echo.app"
[[ -d "$APP_PATH" ]] || fail "Build reported success but no app at ${APP_PATH}"

WARNING_COUNT="$(grep -c "warning:" "$BUILD_LOG" || true)"
info "Built ${APP_PATH##*/} (${WARNING_COUNT} warnings)"

# --- Verify the signature before replacing a working install ----------------
bold "Verifying signature…"
codesign --verify --deep --strict "$APP_PATH" 2>/dev/null \
  || fail "Signature verification failed; refusing to install."
info "$(codesign -dv "$APP_PATH" 2>&1 | grep '^Identifier=' || echo 'Identifier=?')"

# --- Install ----------------------------------------------------------------
bold "Installing to ${INSTALL_PATH}…"

# Quit only copies installed in /Applications. A debug build running from Xcode
# lives in DerivedData and is left alone.
quit_app_at "$INSTALL_PATH"

if [[ -d "$INSTALL_PATH" ]]; then
  rm -rf "$INSTALL_PATH"
fi
cp -R "$APP_PATH" "$INSTALL_PATH"

# Locally built apps are not quarantined, but strip the attribute defensively
# in case the build directory inherited one.
xattr -dr com.apple.quarantine "$INSTALL_PATH" 2>/dev/null || true

VERSION="$(defaults read "${INSTALL_PATH}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo '?')"
BUILD_NUM="$(defaults read "${INSTALL_PATH}/Contents/Info" CFBundleVersion 2>/dev/null || echo '?')"
info "Installed version ${VERSION} (build ${BUILD_NUM}) from ${GIT_SHA}"

bold "Launching…"
# Done last, so a failed build leaves the other copy running.
quit_app_at "$OTHER_INSTALL_PATH"
open "$INSTALL_PATH"

printf '\n'
bold "Done."
info "Installed: ${INSTALL_PATH}"
info "Build log: ${BUILD_LOG}"
