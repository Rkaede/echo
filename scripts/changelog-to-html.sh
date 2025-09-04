#!/bin/bash
# =============================================================================
# Echo Changelog to HTML Converter
# =============================================================================
# Converts the X.Y.Z section (supports "## Echo X.Y.Z" or "## X.Y.Z") from
# CHANGELOG.md to HTML for Sparkle release notes.
#
# USAGE:
#   ./scripts/changelog-to-html.sh <version> [changelog_file]
#
# OUTPUT:
#   HTML to stdout
# =============================================================================

set -euo pipefail

VERSION="${1:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG_FILE="${2:-"${ROOT_DIR}/CHANGELOG.md"}"

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version> [changelog_file]" >&2
  exit 1
fi

if [ ! -f "$CHANGELOG_FILE" ]; then
  echo "Error: Changelog file '$CHANGELOG_FILE' not found" >&2
  exit 1
fi

# Extract version section after "## Echo X.Y.Z" or "## X.Y.Z" up to next "## "
extract_version_section() {
  local version="$1" file="$2"
  awk -v ver="$version" '
    BEGIN { in_section=0 }
    /^##[[:space:]]+Echo[[:space:]]+/ {
      if ($0 ~ "^##[[:space:]]+Echo[[:space:]]+" ver "(\\b|$)") { in_section=1; next } else if (in_section) { exit }
    }
    /^##[[:space:]]+[0-9]/ {
      if ($0 ~ "^##[[:space:]]+" ver "(\\b|$)") { in_section=1; next } else if (in_section) { exit }
    }
    { if (in_section) print }
  ' "$file"
}

markdown_to_html() {
  local text="$1"
  # Use pandoc to convert markdown to HTML
  echo "$text" | pandoc -f markdown -t html --wrap=none
}

version_content="$(extract_version_section "$VERSION" "$CHANGELOG_FILE" || true)"

if [ -z "$version_content" ]; then
  cat <<EOF
<h2>Echo ${VERSION}</h2>
<p>Latest update to Echo with fixes and improvements.</p>
<p><a href="https://github.com/Rkaede/echo/blob/main/CHANGELOG.md">View full changelog</a></p>
EOF
  exit 0
fi

# Convert the entire version content to HTML using pandoc
markdown_to_html "$version_content"

echo "<p><a href=\"https://github.com/Rkaede/echo/blob/main/CHANGELOG.md\">View full changelog</a></p>"


