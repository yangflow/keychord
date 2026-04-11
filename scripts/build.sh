#!/usr/bin/env bash
#
# build.sh — Build KeyChord.app for local use.
#
# Produces an ad-hoc-signed .app in dist/KeyChord.app. Ad-hoc signing
# is enough for personal use on your own Mac: Gatekeeper will prompt
# once on first launch and then remember. It is NOT enough to share
# the .app with another Mac — see the "Upgrade path" section below.
#
# Prerequisites
# -------------
# - Xcode installed and selected as the developer toolchain:
#     sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
#
# Usage
# -----
#   ./scripts/build.sh
#
# Output
# ------
#   dist/KeyChord.app  — copy/move to /Applications and launch.
#
# Next steps after build
# ----------------------
#   mv dist/KeyChord.app /Applications/
#   xattr -cr /Applications/KeyChord.app     # strip quarantine if any
#   open /Applications/KeyChord.app
#
# Upgrade path: signed + notarized (for sharing with others)
# ----------------------------------------------------------
# Requires an Apple Developer Program membership ($99/year) and a
# "Developer ID Application" certificate installed in your login
# keychain. Then adapt this script:
#
#   1. Replace CODE_SIGN_IDENTITY="-" with the exact certificate name,
#      e.g. "Developer ID Application: Your Name (TEAMID)".
#   2. After the build, zip the .app and submit with notarytool:
#        ditto -c -k --keepParent dist/KeyChord.app dist/KeyChord.zip
#        xcrun notarytool submit dist/keychord.zip \
#            --apple-id YOUR_APPLE_ID \
#            --team-id YOUR_TEAM_ID \
#            --password "@keychain:AC_PASSWORD" \
#            --wait
#   3. Staple the ticket:
#        xcrun stapler staple dist/KeyChord.app
#   4. Optionally wrap in a DMG with hdiutil create.
#
# For a one-off sharable build you can also drive the whole flow
# from Xcode: Product → Archive → Distribute App → Developer ID.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="keychord.xcodeproj"
SCHEME="keychord"
CONFIGURATION="Release"
DERIVED_DATA="build/DerivedData"
DIST_DIR="dist"
APP_NAME="KeyChord.app"

# -----------------------------------------------------------------------------
# Prereq check
# -----------------------------------------------------------------------------

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: xcodebuild not found in PATH" >&2
    exit 1
fi

DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEV_DIR" != *"Xcode.app"* ]]; then
    echo "error: xcode-select currently points to '$DEV_DIR'" >&2
    echo "       Switch to the full Xcode install:" >&2
    echo "         sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Clean
# -----------------------------------------------------------------------------

echo "==> Cleaning previous artifacts..."
rm -rf build "$DIST_DIR"
mkdir -p build "$DIST_DIR"

# -----------------------------------------------------------------------------
# Build (Release, ad-hoc signed)
# -----------------------------------------------------------------------------

echo "==> Building $SCHEME ($CONFIGURATION, ad-hoc signed)..."
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER=""

APP_SRC="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME"
if [[ ! -d "$APP_SRC" ]]; then
    echo "error: did not find $APP_SRC after build" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Export to dist/
# -----------------------------------------------------------------------------

echo "==> Copying to $DIST_DIR/..."
cp -R "$APP_SRC" "$DIST_DIR/"

# Verify signature
echo "==> Verifying signature..."
codesign --verify --verbose=2 "$DIST_DIR/$APP_NAME"

# Size / info
APP_PATH="$DIST_DIR/$APP_NAME"
SIZE=$(du -sh "$APP_PATH" | cut -f1)
echo ""
echo "✓ Built $APP_PATH ($SIZE)"
echo ""
echo "To install:"
echo "  mv $APP_PATH /Applications/"
echo "  xattr -cr /Applications/$APP_NAME"
echo "  open /Applications/$APP_NAME"
