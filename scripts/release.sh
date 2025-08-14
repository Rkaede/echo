#!/bin/bash

# Echo Release Script
# This script automates the release process for the Echo macOS app
# It handles versioning, building, signing, notarization, and Sparkle feed updates

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="Echo"
SCHEME_NAME="Echo"
CONFIGURATION="Release"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_DIR="${PROJECT_DIR}/archives"
EXPORT_DIR="${PROJECT_DIR}/exports"
DOCS_DIR="${PROJECT_DIR}/docs"
INFO_PLIST="${PROJECT_DIR}/echo/Info.plist"
APPCAST_URL="https://rkaede.github.io/echo/appcast.xml"
CURRENT_BRANCH=""  # Will be set in check_prerequisites

# Print colored output
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Load environment variables from .env file
load_env_file() {
    local env_file="${PROJECT_DIR}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        print_error ".env file not found at $env_file"
        print_error "Please create a .env file with your signing credentials"
        exit 1
    fi
    
    print_status "Loading environment variables from .env..."
    
    # Source the .env file
    set -a  # Automatically export variables
    source "$env_file"
    set +a  # Stop automatically exporting
    
    # Validate required variables
    local required_vars=("DEVELOPER_ID" "APPLE_ID" "TEAM_ID" "APP_PASSWORD")
    local missing_vars=()
    
    # Set default bundle identifier if not provided
    if [[ -z "$BUNDLE_IDENTIFIER" ]]; then
        BUNDLE_IDENTIFIER="io.littlecove.echo"
    fi
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing required environment variables: ${missing_vars[*]}"
        print_error "Please check your .env file"
        exit 1
    fi
    
    print_success "Environment variables loaded successfully"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check for Xcode
    if ! command -v xcodebuild &> /dev/null; then
        print_error "xcodebuild not found. Please install Xcode."
        exit 1
    fi
    
    # Check for git
    if ! command -v git &> /dev/null; then
        print_error "git not found. Please install git."
        exit 1
    fi
    
    # Check for create-dmg
    if ! command -v create-dmg &> /dev/null; then
        print_error "create-dmg not found. Please install it:"
        print_error "  brew install create-dmg"
        print_error "  or visit: https://github.com/create-dmg/create-dmg"
        exit 1
    fi
    
    # Check for xmlstarlet (used to inject release notes link into appcast)
    if ! command -v xmlstarlet &> /dev/null; then
        print_error "xmlstarlet not found. Please install it:"
        print_error "  brew install xmlstarlet"
        exit 1
    fi
    
    # Check for gh CLI (optional for GitHub releases)
    if ! command -v gh &> /dev/null; then
        print_warning "gh CLI not found. GitHub release creation will be skipped."
        print_warning "Install with: brew install gh"
        print_warning "Then authenticate with: gh auth login"
    fi
    
    # Check for clean git working directory
    if [[ -n $(git status --porcelain) ]]; then
        print_warning "Git working directory is not clean."
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Get current branch (handle detached HEAD)
    CURRENT_BRANCH=$(git branch --show-current)
    if [[ -z "$CURRENT_BRANCH" ]]; then
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        if [[ "$CURRENT_BRANCH" == "HEAD" || -z "$CURRENT_BRANCH" ]]; then
            CURRENT_BRANCH=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "")
            CURRENT_BRANCH=${CURRENT_BRANCH##*/}
        fi
    fi
    if [[ "$CURRENT_BRANCH" != "main" && -z "$CI" ]]; then
        print_warning "Not on main branch (current: $CURRENT_BRANCH)"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    print_success "Prerequisites check passed"
}

# Get current version from Info.plist
get_current_version() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST"
}

# Update version using agvtool with proper marketing version and build number separation
update_version() {
    local new_marketing_version=$1
    print_status "Updating marketing version to $new_marketing_version using agvtool..."
    
    # Get current build number
    local current_build=$(agvtool what-version -terse)
    print_status "Current build number: $current_build"
    
    # Update marketing version (CFBundleShortVersionString) in Info.plist and project.pbxproj
    agvtool new-marketing-version "$new_marketing_version"
    
    # Auto-increment build number (CURRENT_PROJECT_VERSION) 
    print_status "Auto-incrementing build number..."
    agvtool next-version -all
    
    # Get new build number for confirmation
    local new_build=$(agvtool what-version -terse)
    
    print_success "Marketing version updated to $new_marketing_version"
    print_success "Build number incremented from $current_build to $new_build"
}

# Clean build artifacts
clean_build() {
    print_status "Cleaning build artifacts..."
    
    rm -rf "$BUILD_DIR"
    rm -rf "$ARCHIVE_DIR"
    rm -rf "$EXPORT_DIR"
    
    xcodebuild clean -scheme "$SCHEME_NAME" -configuration "$CONFIGURATION" &>/dev/null
    
    print_success "Build artifacts cleaned"
}

# Build the app
build_app() {
    print_status "Building $PROJECT_NAME..."
    
    xcodebuild build \
        -scheme "$SCHEME_NAME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$BUILD_DIR" \
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
        CODE_SIGN_STYLE="Manual"
    
    if [ $? -ne 0 ]; then
        print_error "Build failed"
        exit 1
    fi
    
    print_success "Build completed"
}

# Archive the app
archive_app() {
    print_status "Archiving $PROJECT_NAME..."
    
    mkdir -p "$ARCHIVE_DIR"
    
    xcodebuild archive \
        -scheme "$SCHEME_NAME" \
        -configuration "$CONFIGURATION" \
        -archivePath "$ARCHIVE_DIR/$PROJECT_NAME.xcarchive" \
        -derivedDataPath "$BUILD_DIR" \
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
        CODE_SIGN_STYLE="Manual"
    
    if [ $? -ne 0 ]; then
        print_error "Archive failed"
        exit 1
    fi
    
    print_success "Archive completed"
}

# Export the app
export_app() {
    print_status "Exporting $PROJECT_NAME..."
    
    mkdir -p "$EXPORT_DIR"
    
    # Create export options plist
    cat > "$EXPORT_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>$DEVELOPER_ID</string>
</dict>
</plist>
EOF
    
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_DIR/$PROJECT_NAME.xcarchive" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_DIR/ExportOptions.plist"
    
    if [ $? -ne 0 ]; then
        print_error "Export failed"
        exit 1
    fi
    
    print_success "Export completed"
}

# Create DMG file using create-dmg tool
create_dmg() {
    local version=$1
    local dmg_name="${PROJECT_NAME}-${version}"
    local final_dmg="${EXPORT_DIR}/${dmg_name}.dmg"
    
    print_status "Creating DMG file with create-dmg..."
    
    # Remove any existing DMG files
    rm -f "$final_dmg"
    
    # Change to export directory
    cd "$EXPORT_DIR"
    
    # Create DMG using create-dmg tool
    create-dmg \
        --volname "$PROJECT_NAME" \
        --volicon "${PROJECT_NAME}.app/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "${PROJECT_NAME}.app" 175 190 \
        --hide-extension "${PROJECT_NAME}.app" \
        --app-drop-link 425 190 \
        --disk-image-size 500 \
        --format UDZO \
        --no-internet-enable \
        "${dmg_name}.dmg" \
        "${PROJECT_NAME}.app"
    
    if [ $? -ne 0 ]; then
        print_error "DMG creation failed"
        exit 1
    fi
    
    print_success "DMG file created: ${dmg_name}.dmg"
    
    # Return to project directory for subsequent operations
    cd "$PROJECT_DIR"
}

# Notarize the app
notarize_app() {
    local version=$1
    local dmg_file="${EXPORT_DIR}/${PROJECT_NAME}-${version}.dmg"
    
    print_status "Notarizing $PROJECT_NAME..."
    print_status "Using credentials from .env file..."
    
    # Submit DMG file for notarization
    print_status "Submitting DMG for notarization..."
    xcrun notarytool submit "$dmg_file" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait
    
    if [ $? -ne 0 ]; then
        print_error "DMG notarization failed"
        exit 1
    fi
    
    # Staple the notarization ticket to the DMG
    print_status "Stapling notarization ticket to DMG..."
    xcrun stapler staple "$dmg_file"
    
    print_success "DMG notarization completed"
}

# Update Sparkle appcast
update_appcast() {
    local version=$1
    local dmg_file="${EXPORT_DIR}/${PROJECT_NAME}-${version}.dmg"
    
    print_status "Updating Sparkle appcast..."
    
    # Create docs directory if it doesn't exist
    mkdir -p "$DOCS_DIR"
    
    # Determine build number for sparkle:version
    local build_number
    build_number=$(agvtool what-version -terse 2>/dev/null || /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || echo "")
    if [[ -z "$build_number" ]]; then
        print_warning "Unable to determine build number; falling back to marketing version for sparkle:version"
        build_number="$version"
    fi
    
    # Check if generate_appcast exists
    if command -v generate_appcast &> /dev/null; then
        print_status "Using generate_appcast tool..."
        generate_appcast "$EXPORT_DIR" -o "$DOCS_DIR/appcast.xml"
    else
        print_error "generate_appcast not found. Please install Sparkle's generate_appcast."
        print_error "brew install --cask sparkle or build from Sparkle repo"
        exit 1
    fi
    
    # Inject sparkle:releaseNotesLink pointing to our hosted HTML release notes (via xmlstarlet)
    local release_notes_url="https://rkaede.github.io/echo/Echo-${version}.html"
    local xpath="/rss/channel/item[title='${version}' or sparkle:shortVersionString='${version}']"
    xmlstarlet ed \
        -N sparkle='http://www.andymatuschak.org/xml-namespaces/sparkle' \
        -d "${xpath}/sparkle:releaseNotesLink" \
        -s "${xpath}" -t elem -n "sparkle:releaseNotesLink" -v "${release_notes_url}" \
        "$DOCS_DIR/appcast.xml" > "$DOCS_DIR/appcast.xml.tmp" \
        && mv "$DOCS_DIR/appcast.xml.tmp" "$DOCS_DIR/appcast.xml"

    # Point enclosure URL to the GitHub Releases asset for this tag
    local enclosure_url="https://github.com/Rkaede/echo/releases/download/v${version}/Echo.dmg"
    xmlstarlet ed \
        -N sparkle='http://www.andymatuschak.org/xml-namespaces/sparkle' \
        -u "${xpath}/enclosure/@url" -v "${enclosure_url}" \
        "$DOCS_DIR/appcast.xml" > "$DOCS_DIR/appcast.xml.tmp" \
        && mv "$DOCS_DIR/appcast.xml.tmp" "$DOCS_DIR/appcast.xml"

    print_success "Appcast updated with DMG file"
}

# Generate HTML release notes from CHANGELOG
generate_release_notes_html() {
    local version=$1
    print_status "Generating HTML release notes from CHANGELOG for ${version}..."
    mkdir -p "$DOCS_DIR"
    "${PROJECT_DIR}/scripts/changelog-to-html.sh" "$version" > "${DOCS_DIR}/Echo-${version}.html"
    if [[ $? -ne 0 || ! -s "${DOCS_DIR}/Echo-${version}.html" ]]; then
        print_error "Failed to generate HTML release notes"
        exit 1
    fi
    print_success "Release notes generated: ${DOCS_DIR}/Echo-${version}.html"
}

# Commit and tag the release
commit_and_tag() {
    local version=$1
    
    print_status "Committing version changes..."
    
    git add "$INFO_PLIST"
    git add "$DOCS_DIR/appcast.xml" 2>/dev/null || true
    git add "$DOCS_DIR/Echo-${version}.html" 2>/dev/null || true
    git add "${PROJECT_DIR}/CHANGELOG.md" 2>/dev/null || true
    git add "${PROJECT_DIR}/Echo.xcodeproj/project.pbxproj" 2>/dev/null || true
    
    git commit -m "release: ${version}"
    
    print_status "Creating git tag v${version}..."
    git tag -a "v${version}" -m "Release version ${version}"
    
    print_status "Pushing commits and tags to remote..."
    git push origin "$CURRENT_BRANCH"
    git push origin "v${version}"
    
    print_success "Version committed, tagged, and pushed"
}

# Create GitHub release
create_github_release() {
    local version=$1
    local dmg_file="${EXPORT_DIR}/${PROJECT_NAME}-${version}.dmg"
    local release_markdown_file="${DOCS_DIR}/Echo-${version}.md"
    
    # Check if gh CLI is available
    if ! command -v gh &> /dev/null; then
        print_warning "gh CLI not found. Skipping GitHub release creation."
        return 0
    fi
    
    # Check if user is authenticated
    if ! gh auth status &> /dev/null; then
        print_error "Not authenticated with GitHub. Run: gh auth login"
        return 1
    fi
    
    # Extract release notes from CHANGELOG.md at repo root
    local changelog_file="${PROJECT_DIR}/CHANGELOG.md"
    if [[ ! -f "$changelog_file" ]]; then
        print_error "CHANGELOG not found at: ${PROJECT_DIR}/CHANGELOG.md"
        return 1
    fi

    # Extract section starting at "## Echo X.Y.Z" or "## X.Y.Z" until next "## ", excluding the heading line
    local tmp_notes
    tmp_notes=$(mktemp)
    awk -v ver="$version" '
        BEGIN { in_section=0 }
        /^##[[:space:]]+Echo[[:space:]]+/ {
            if ($0 ~ "^##[[:space:]]+Echo[[:space:]]+" ver "(\\b|$)") { in_section=1; next } else if (in_section) { exit }
        }
        /^##[[:space:]]+[0-9]/ {
            if ($0 ~ "^##[[:space:]]+" ver "(\\b|$)") { in_section=1; next } else if (in_section) { exit }
        }
        { if (in_section) print }
    ' "$changelog_file" > "$tmp_notes"

    if [[ ! -s "$tmp_notes" ]]; then
        print_error "Could not find changelog section for version $version in CHANGELOG.md"
        rm -f "$tmp_notes"
        return 1
    fi

    print_status "Creating GitHub release..."

    local release_title="Echo ${version}"
    local tag_name="v${version}"

    # Upload both versioned and stable-named DMGs so README latest link works
    local stable_dmg="${EXPORT_DIR}/${PROJECT_NAME}.dmg"
    gh release create "$tag_name" \
        --title "$release_title" \
        --notes-file "$tmp_notes" \
        "$stable_dmg"

    local gh_status=$?
    rm -f "$tmp_notes"

    if [ $gh_status -eq 0 ]; then
        print_success "GitHub release created successfully!"
        print_status "Release URL: $(gh release view "$tag_name" --web --repo $(gh repo view --json url -q .url) 2>/dev/null || echo "Check GitHub releases page")"
    else
        print_error "Failed to create GitHub release"
        return 1
    fi
}

# Main release process
main() {
    echo "======================================"
    echo "       Echo Release Script"
    echo "======================================"
    echo
    
    # Load environment variables
    load_env_file
    
    # Check prerequisites
    check_prerequisites
    
    # Get current version
    CURRENT_VERSION=$(get_current_version)
    print_status "Current version: $CURRENT_VERSION"
    
    # Get previous tag
    PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    
    # Prompt for new version
    read -p "Enter new version number: " NEW_VERSION
    
    if [[ -z "$NEW_VERSION" ]]; then
        print_error "Version number cannot be empty"
        exit 1
    fi
    
    # Verify CHANGELOG exists and contains the target version section
    CHANGELOG_FILE="${PROJECT_DIR}/CHANGELOG.md"
    if [[ ! -f "$CHANGELOG_FILE" ]]; then
        print_error "CHANGELOG not found at: ${PROJECT_DIR}/CHANGELOG.md"
        exit 1
    fi
    if ! rg -n "^##(\\s+Echo)?\\s+${NEW_VERSION}(\\b|$)" "$CHANGELOG_FILE" > /dev/null; then
        print_error "CHANGELOG.md missing section for version ${NEW_VERSION} (expected heading '## Echo ${NEW_VERSION}' or '## ${NEW_VERSION}')"
        exit 1
    fi

    print_success "Found CHANGELOG section for ${NEW_VERSION}"
    
    # Confirm release
    echo
    print_warning "This will create a release for Echo ${NEW_VERSION}"
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    
    # Update version
    update_version "$NEW_VERSION"
    
    # Clean and build
    clean_build
    build_app
    archive_app
    export_app
    
    # Create DMG distribution file
    create_dmg "$NEW_VERSION"
    
    # Generate HTML release notes for Sparkle
    generate_release_notes_html "$NEW_VERSION"
    
    # Notarize (optional)
    read -p "Notarize the app? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        notarize_app "$NEW_VERSION"
    fi
    
    # Create stable-named DMG for latest download link
    cp -f "${EXPORT_DIR}/${PROJECT_NAME}-${NEW_VERSION}.dmg" "${EXPORT_DIR}/${PROJECT_NAME}.dmg"
    print_success "Stable DMG created: ${EXPORT_DIR}/${PROJECT_NAME}.dmg"
    
    # Temporarily move stable DMG to avoid duplicate error in appcast generation
    mv "${EXPORT_DIR}/${PROJECT_NAME}.dmg" "${EXPORT_DIR}/${PROJECT_NAME}.dmg.tmp"
    
    # Update appcast
    update_appcast "$NEW_VERSION"
    
    # Restore stable DMG after appcast generation
    mv "${EXPORT_DIR}/${PROJECT_NAME}.dmg.tmp" "${EXPORT_DIR}/${PROJECT_NAME}.dmg"
    
    # Commit and tag
    read -p "Commit and tag release? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        commit_and_tag "$NEW_VERSION"
        
        # Create GitHub release
        echo
        read -p "Create GitHub release? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            create_github_release "$NEW_VERSION"
        fi
    fi
    
    echo
    print_success "Release ${NEW_VERSION} completed successfully!"
    echo
    echo "Next steps:"
    if command -v gh &> /dev/null && gh auth status &> /dev/null; then
        echo "1. GitHub release was created with DMG attachment"
        echo "2. Update appcast.xml on GitHub (if needed)"
    else
        echo "1. Create GitHub release manually and upload:"
        echo "   - ${EXPORT_DIR}/${PROJECT_NAME}-${NEW_VERSION}.dmg"
        echo "2. Update appcast.xml on GitHub"
        echo "3. Install gh CLI for automated releases: brew install gh"
    fi
    echo
}

# Run main function
main "$@"