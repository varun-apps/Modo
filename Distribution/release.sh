#!/usr/bin/env bash
#
# Modo release pipeline.
#
# Usage:   ./Distribution/release.sh <version>
# Example: ./Distribution/release.sh 1.1
#
# Prerequisites (one-time setup):
#   * Apple Developer ID Application certificate installed in the login keychain
#   * Notary credentials stored in the keychain, e.g.:
#       xcrun notarytool store-credentials modo-notary \
#           --apple-id you@example.com \
#           --team-id YOURTEAMID \
#           --password "app-specific-password"
#     (override the profile name by exporting NOTARY_PROFILE before running.)
#   * Sparkle's EdDSA keypair generated via `generate_keys` (private key in keychain)
#   * `gh` CLI authenticated against GitHub (`gh auth login`)
#
# What this script does:
#   1. Archive Modo in Release configuration
#   2. Export a Developer ID build
#   3. Zip the .app
#   4. Submit to Apple notary service and wait
#   5. Staple the notarization ticket to the .app
#   6. Re-zip the stapled .app
#   7. Sign the zip with Sparkle's sign_update tool (EdDSA)
#   8. Print the <item> snippet ready to paste into Distribution/appcast.xml
#   9. Optionally create a GitHub release with both the zip and the appcast
#
# After running this script, edit Distribution/appcast.xml to add the new
# <item> (snippet printed at the end) and run the final `gh release create`
# command the script prints.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi

VERSION="$1"
SCHEME="Modo"
PROJECT="Modo.xcodeproj"
TEAM_ID="${TEAM_ID:-REPLACE_WITH_YOUR_TEAM_ID}"
NOTARY_PROFILE="${NOTARY_PROFILE:-modo-notary}"
REPO="${REPO:-varun-apps/Modo}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/Modo.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/Modo.app"
ZIP_PATH="$BUILD_DIR/Modo-$VERSION.zip"

# Find Sparkle's sign_update tool inside the resolved SPM artifacts.
SIGN_UPDATE="$(find ~/Library/Developer/Xcode/DerivedData -name sign_update -type f 2>/dev/null | head -n 1 || true)"
if [[ -z "$SIGN_UPDATE" ]]; then
  echo "Could not find sign_update tool. Build the project once in Xcode so Sparkle resolves." >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> 1/8  Archiving…"
xcodebuild -project "$ROOT/$PROJECT" \
           -scheme "$SCHEME" \
           -configuration Release \
           -archivePath "$ARCHIVE_PATH" \
           archive | xcpretty || true

echo "==> 2/8  Exporting Developer ID build…"
xcodebuild -exportArchive \
           -archivePath "$ARCHIVE_PATH" \
           -exportPath "$EXPORT_DIR" \
           -exportOptionsPlist "$ROOT/Distribution/ExportOptions.plist"

echo "==> 3/8  Zipping app for notarization…"
( cd "$EXPORT_DIR" && ditto -c -k --keepParent Modo.app "$ZIP_PATH" )

echo "==> 4/8  Submitting to notary service (this can take a few minutes)…"
xcrun notarytool submit "$ZIP_PATH" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait

echo "==> 5/8  Stapling notarization ticket…"
xcrun stapler staple "$APP_PATH"

echo "==> 6/8  Re-zipping stapled app…"
rm -f "$ZIP_PATH"
( cd "$EXPORT_DIR" && ditto -c -k --keepParent Modo.app "$ZIP_PATH" )

echo "==> 7/8  Signing zip with Sparkle EdDSA key…"
SIGN_LINE="$("$SIGN_UPDATE" "$ZIP_PATH")"
SIGNATURE="$(echo "$SIGN_LINE" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')"
LENGTH="$(echo "$SIGN_LINE" | sed -nE 's/.*length="([^"]+)".*/\1/p')"
PUBDATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"

echo "==> 8/8  Paste this <item> at the top of <channel> in Distribution/appcast.xml:"
cat <<EOF

    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <pubDate>$PUBDATE</pubDate>
      <description><![CDATA[
        <ul>
          <li>TODO: list the changes</li>
        </ul>
      ]]></description>
      <enclosure
        url="https://github.com/$REPO/releases/download/v$VERSION/Modo-$VERSION.zip"
        sparkle:edSignature="$SIGNATURE"
        length="$LENGTH"
        type="application/octet-stream" />
    </item>

EOF

echo "After updating Distribution/appcast.xml, publish with:"
echo
echo "  gh release create v$VERSION \\"
echo "      $ZIP_PATH \\"
echo "      $ROOT/Distribution/appcast.xml \\"
echo "      --repo $REPO --title \"Modo $VERSION\" --notes-file CHANGELOG.md"
echo
echo "Done."
