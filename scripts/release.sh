#!/usr/bin/env bash
#
# release.sh — Build a keychord release artifact (.dmg) from this repo.
#
# Modes are detected from env vars:
#
#   unsigned     (default)
#     Produces dist/KeyChord-<version>.dmg ad-hoc signed. Suitable for
#     manual sharing over "trust me" channels. Gatekeeper will nag the
#     receiver on first launch.
#
#   signed       DEVELOPER_ID_APPLICATION=<cert-name>
#     Produces a DMG signed by the named "Developer ID Application"
#     certificate. Receivers see a trusted signature but Gatekeeper
#     still warns until notarization.
#
#   notarized    signed +
#                APPLE_ID=<apple-id-email>
#                APPLE_TEAM_ID=<10-char-team-id>
#                APPLE_APP_PASSWORD=<app-specific-password>
#     Uploads to Apple's notary service, waits, staples, and produces
#     a fully Gatekeeper-approved DMG.
#
#   sparkle      notarized +
#                SPARKLE_PRIVATE_KEY=<path-to-ed25519-private-key>
#                (or SPARKLE_KEYCHAIN_PROFILE=<name>)
#     Additionally signs the artifact with Sparkle's sign_update tool
#     and emits the `sparkle:edSignature` + length metadata ready for
#     pasting into appcast.xml.
#
# Usage:
#     ./scripts/release.sh <version>
#     VERSION must be a plain semver like 1.0.0 (no leading 'v').
#
# Output in dist/:
#     KeyChord.app                      — built app bundle
#     KeyChord-<version>.dmg            — distributable disk image
#     KeyChord-<version>.dmg.sha256     — SHA256 for Homebrew cask
#     sparkle-signature.txt             — if SPARKLE mode engaged
#
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <version>" >&2
    echo "example: $0 0.1.0" >&2
    exit 64
fi
VERSION="$1"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version must look like 1.0.0 (no 'v' prefix)" >&2
    exit 64
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: xcodebuild not found; install Xcode and run:" >&2
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
fi

PROJECT="keychord.xcodeproj"
SCHEME="keychord"
CONFIGURATION="Release"
DERIVED="build/DerivedData"
DIST="dist"
APP_NAME="KeyChord.app"
DMG_NAME="KeyChord-$VERSION.dmg"

# -----------------------------------------------------------------------------
# Mode detection
# -----------------------------------------------------------------------------

MODE="unsigned"
SIGN_IDENTITY="-"
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    MODE="signed"
    SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
fi
if [[ "$MODE" == "signed" \
   && -n "${APPLE_ID:-}" \
   && -n "${APPLE_TEAM_ID:-}" \
   && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    MODE="notarized"
fi
if [[ "$MODE" == "notarized" && -n "${SPARKLE_PRIVATE_KEY:-}${SPARKLE_KEYCHAIN_PROFILE:-}" ]]; then
    MODE="sparkle"
fi

echo "==> keychord $VERSION — mode: $MODE"

# -----------------------------------------------------------------------------
# Clean + build
# -----------------------------------------------------------------------------

rm -rf build "$DIST"
mkdir -p build "$DIST"

echo "==> Building ($CONFIGURATION, identity=$SIGN_IDENTITY)..."
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    MARKETING_VERSION="$VERSION" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES

APP_SRC="$DERIVED/Build/Products/$CONFIGURATION/$APP_NAME"
if [[ ! -d "$APP_SRC" ]]; then
    echo "error: built app missing at $APP_SRC" >&2
    exit 1
fi
cp -R "$APP_SRC" "$DIST/"

codesign --verify --verbose=2 "$DIST/$APP_NAME"

# -----------------------------------------------------------------------------
# Notarize (optional)
# -----------------------------------------------------------------------------

if [[ "$MODE" == "notarized" || "$MODE" == "sparkle" ]]; then
    echo "==> Zipping for notarization..."
    NOTARIZE_ZIP="$DIST/KeyChord-notarize.zip"
    ditto -c -k --keepParent "$DIST/$APP_NAME" "$NOTARIZE_ZIP"

    echo "==> Submitting to Apple notary service..."
    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait

    echo "==> Stapling..."
    xcrun stapler staple "$DIST/$APP_NAME"
    rm -f "$NOTARIZE_ZIP"
fi

# -----------------------------------------------------------------------------
# DMG
# -----------------------------------------------------------------------------

echo "==> Building DMG..."
DMG_PATH="$DIST/$DMG_NAME"
STAGING="$(mktemp -d)"
cp -R "$DIST/$APP_NAME" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create \
    -volname "KeyChord $VERSION" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"
rm -rf "$STAGING"

shasum -a 256 "$DMG_PATH" | awk '{print $1}' > "$DMG_PATH.sha256"
echo "==> SHA256: $(cat "$DMG_PATH.sha256")"

# -----------------------------------------------------------------------------
# Sparkle signing (optional)
# -----------------------------------------------------------------------------

if [[ "$MODE" == "sparkle" ]]; then
    if ! command -v sign_update >/dev/null 2>&1; then
        echo "warn: sign_update not in PATH — skipping Sparkle signature" >&2
    else
        echo "==> Signing DMG with Sparkle Ed25519 key..."
        if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
            SIG="$(sign_update -f "$SPARKLE_PRIVATE_KEY" "$DMG_PATH")"
        else
            SIG="$(sign_update -p "$SPARKLE_KEYCHAIN_PROFILE" "$DMG_PATH")"
        fi
        echo "$SIG" > "$DIST/sparkle-signature.txt"
        echo "==> Sparkle signature written to $DIST/sparkle-signature.txt"

        # --- Auto-update appcast.xml -------------------------------------------
        APPCAST="$REPO_ROOT/docs/appcast.xml"
        if [[ -f "$APPCAST" ]]; then
            ED_SIG="$(echo "$SIG" | grep -oP '(?<=edSignature=")[^"]*')"
            DMG_LEN="$(stat -f%z "$DMG_PATH")"
            DMG_URL="https://github.com/yangflow/keychord/releases/download/v${VERSION}/${DMG_NAME}"
            PUB_DATE="$(date -R 2>/dev/null || date '+%a, %d %b %Y %H:%M:%S %z')"

            ITEM="\\
    <item>\\
      <title>Version ${VERSION}</title>\\
      <pubDate>${PUB_DATE}</pubDate>\\
      <sparkle:version>${VERSION}</sparkle:version>\\
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>\\
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>\\
      <enclosure url=\"${DMG_URL}\"\\
                 type=\"application/octet-stream\"\\
                 sparkle:edSignature=\"${ED_SIG}\"\\
                 length=\"${DMG_LEN}\" />\\
    </item>"

            # Insert before the closing </channel> tag
            if grep -q '<!-- Prepend new <item>' "$APPCAST"; then
                sed -i '' "s|<!-- Prepend new <item> blocks here for each release. -->|<!-- Prepend new <item> blocks here for each release. -->\n${ITEM}|" "$APPCAST"
            else
                sed -i '' "s|</channel>|${ITEM}\n  </channel>|" "$APPCAST"
            fi
            echo "==> appcast.xml updated with v${VERSION} entry"
        else
            echo "    Paste this into the <enclosure> of appcast.xml."
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Update Homebrew tap
# -----------------------------------------------------------------------------

SHA256="$(cat "$DMG_PATH.sha256")"
CASK_FILE="$REPO_ROOT/scripts/keychord.rb"
if [[ -f "$CASK_FILE" ]]; then
    sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/" "$CASK_FILE"
    sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$SHA256\"/" "$CASK_FILE"
    echo "==> Updated scripts/keychord.rb (version=$VERSION, sha256=$SHA256)"

    # Push to homebrew-tap if the repo exists locally as a sibling
    TAP_DIR="$REPO_ROOT/../homebrew-tap"
    if [[ -d "$TAP_DIR/Casks" ]]; then
        cp "$CASK_FILE" "$TAP_DIR/Casks/keychord.rb"
        git -C "$TAP_DIR" add Casks/keychord.rb
        git -C "$TAP_DIR" commit -m "Update keychord to $VERSION" 2>/dev/null && \
        git -C "$TAP_DIR" push && \
        echo "==> Pushed homebrew-tap update"
    fi
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "Release $VERSION built in $DIST/:"
ls -la "$DIST"
echo ""
echo "Next steps:"
echo "  1. gh release create v$VERSION \\"
echo "       --title 'KeyChord $VERSION' \\"
echo "       $DMG_PATH"
echo "  2. Update Formula/keychord.rb (or your tap) with the new version"
echo "     and the SHA256 from $DMG_PATH.sha256"
case "$MODE" in
    sparkle)
        echo "  3. Push docs/appcast.xml (auto-updated) to GitHub Pages"
        ;;
    unsigned)
        echo "  Note: unsigned build. Recipients must 'xattr -cr KeyChord.app' or"
        echo "        right-click → Open on first launch."
        ;;
esac
