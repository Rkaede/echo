#!/usr/bin/env bash
#
# Put Echo back to a first-launch state so onboarding runs again, while keeping
# transcription history (the history rows and their recordings).
#
#   scripts/reset-onboarding.sh                  Reset /Applications/Echo.app
#   scripts/reset-onboarding.sh --dev            Reset /Applications/Echo Dev.app
#
# Options:
#   --keep-keys          Leave the Groq and OpenRouter API keys in the Keychain
#   --keep-profiles      Leave profiles as they are (otherwise the defaults come back)
#   --keep-permissions   Leave microphone/accessibility/input monitoring grants alone
#   --no-launch          Don't open Echo afterwards
#   --dry-run            Print what would happen without changing anything
#   -y, --yes            Skip the confirmation prompt
#
# What is reset:
#   - All preferences (onboarding flag, shortcuts, selected models, Sparkle state...)
#   - Profiles: removed, and Echo seeds the default profiles on its next launch
#   - API keys in the Keychain (service "com.echo.app")
#   - Privacy permissions (tccutil reset All <bundle id>)
#   - Recordings kept for "Retry Failed Recording"
#
# What is kept:
#   - transcription_history rows in echo.sqlite and the recordings/ folder
#   - logs/
#
# Before changing anything it copies the preferences plist and echo.sqlite to
# ~/.echo-reset-backups/<time>-<bundle id>/ (the newest 10 are kept).
#
# Not reset: "Open Echo at login". macOS has no command to remove one app's
# login item; the last onboarding step sets it from its checkbox anyway.
#
# The Keychain items are shared by the release and dev builds (same service and
# account names), so removing keys for one removes them for both.

set -euo pipefail

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
info() { printf '  %s\n' "$1"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$1"; }
fail() { printf '\033[31m  ✗ %s\033[0m\n' "$1" >&2; exit 1; }

BUNDLE_ID="io.littlecove.echo"
APP_PATH="/Applications/Echo.app"
KEEP_KEYS=0
KEEP_PROFILES=0
KEEP_PERMISSIONS=0
LAUNCH=1
DRY_RUN=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dev) BUNDLE_ID="io.littlecove.echo.dev"; APP_PATH="/Applications/Echo Dev.app" ;;
    --keep-keys) KEEP_KEYS=1 ;;
    --keep-profiles) KEEP_PROFILES=1 ;;
    --keep-permissions) KEEP_PERMISSIONS=1 ;;
    --no-launch) LAUNCH=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "Unknown option: $1 (see --help)" ;;
  esac
  shift
done

CONTAINER="$HOME/Library/Containers/$BUNDLE_ID/Data"
PREFS_PLIST="$CONTAINER/Library/Preferences/$BUNDLE_ID.plist"
DATA_DIR="$CONTAINER/Library/Application Support/Echo"
DB_PATH="$DATA_DIR/echo.sqlite"
FAILED_DIR="$DATA_DIR/failed-recordings"
KEYCHAIN_SERVICE="com.echo.app"
KEYCHAIN_ACCOUNTS=(groq-api-key openrouter-api-key)
BACKUP_ROOT="$HOME/.echo-reset-backups"
BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-$BUNDLE_ID"

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    info "would run: $*"
  else
    "$@"
  fi
}

[[ -d "$CONTAINER" ]] || fail "No data for $BUNDLE_ID at $CONTAINER. Has it been run yet?"

history_count="?"
if [[ -f "$DB_PATH" ]]; then
  history_count=$(sqlite3 -readonly "$DB_PATH" "SELECT COUNT(*) FROM transcription_history;" 2>/dev/null || echo "?")
fi

bold "Reset Echo ($BUNDLE_ID) for onboarding"
info "Keeps: $history_count history entries and their recordings, logs"
info "Resets: preferences$([[ $KEEP_PROFILES -eq 0 ]] && echo ", profiles")$([[ $KEEP_KEYS -eq 0 ]] && echo ", API keys")$([[ $KEEP_PERMISSIONS -eq 0 ]] && echo ", permissions"), failed recordings"
if [[ $KEEP_KEYS -eq 0 ]]; then
  warn "The Groq and OpenRouter keys are deleted for both the release and dev builds."
  warn "Have them to hand to paste back in, or pass --keep-keys."
fi
[[ $DRY_RUN -eq 1 ]] && info "(dry run: nothing will change)"

if [[ $ASSUME_YES -eq 0 && $DRY_RUN -eq 0 ]]; then
  read -r -p "  Continue? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { info "Cancelled."; exit 0; }
fi

bold "Quitting Echo"
if pgrep -f "$APP_PATH/Contents/MacOS/" >/dev/null || osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null | grep -q true; then
  run osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  if [[ $DRY_RUN -eq 0 ]]; then
    for _ in {1..20}; do
      osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null | grep -q true || break
      sleep 0.25
    done
    if osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null | grep -q true; then
      warn "Echo didn't quit; forcing it."
      pkill -f "$APP_PATH/Contents/MacOS/" || true
      sleep 0.5
    fi
  fi
  info "Quit."
else
  info "Not running."
fi

bold "Backing up"
run mkdir -p "$BACKUP_DIR"
if [[ -f "$PREFS_PLIST" ]]; then
  run cp "$PREFS_PLIST" "$BACKUP_DIR/"
fi
if [[ -f "$DB_PATH" ]]; then
  # .backup folds in the WAL, so the copy is complete on its own.
  run sqlite3 "$DB_PATH" ".backup '$BACKUP_DIR/echo.sqlite'"
fi
info "$BACKUP_DIR"
if [[ $DRY_RUN -eq 0 ]]; then
  # Keep only the newest 10 backups.
  ls -1d "$BACKUP_ROOT"/*/ 2>/dev/null | sort -r | tail -n +11 | while read -r old; do rm -rf "$old"; done
fi

bold "Preferences"
if [[ -f "$PREFS_PLIST" ]]; then
  # Go through cfprefsd (not rm) so no cached copy is written back later.
  run defaults delete "${PREFS_PLIST%.plist}" 2>/dev/null || true
  info "Cleared."
else
  info "None saved."
fi

bold "Profiles"
if [[ $KEEP_PROFILES -eq 1 ]]; then
  info "Kept."
elif [[ -f "$DB_PATH" ]]; then
  run sqlite3 "$DB_PATH" "DELETE FROM profile_apps; DELETE FROM profiles;"
  info "Removed; Echo recreates the defaults on launch."
else
  info "No database yet."
fi

bold "Failed recordings"
if [[ -d "$FAILED_DIR" ]]; then
  run rm -rf "$FAILED_DIR"
  info "Removed."
else
  info "None."
fi

bold "API keys"
if [[ $KEEP_KEYS -eq 1 ]]; then
  info "Kept."
else
  for account in "${KEYCHAIN_ACCOUNTS[@]}"; do
    removed=0
    while security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$account" >/dev/null 2>&1; do
      if [[ $DRY_RUN -eq 1 ]]; then
        info "would delete Keychain item $KEYCHAIN_SERVICE / $account"
        removed=1
        break
      fi
      security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$account" >/dev/null 2>&1 \
        || fail "Couldn't delete $account from the Keychain."
      removed=1
    done
    [[ $removed -eq 1 ]] && info "Deleted $account." || info "No $account."
  done
fi

bold "Permissions"
if [[ $KEEP_PERMISSIONS -eq 1 ]]; then
  info "Kept."
else
  run tccutil reset All "$BUNDLE_ID"
fi

if [[ $LAUNCH -eq 1 ]]; then
  bold "Opening Echo"
  if [[ -d "$APP_PATH" ]]; then
    run open "$APP_PATH"
  else
    run open -b "$BUNDLE_ID"
  fi
fi

bold "Done"
[[ $DRY_RUN -eq 0 ]] && info "To undo the preferences and profiles, copy the files in $BACKUP_DIR back (with Echo quit)."
exit 0
