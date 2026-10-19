#!/bin/bash
# Builds a universal rundown.app, signs it with a Developer ID, notarises and staples it, and zips it into
# build/rundown.zip, ready to attach to a GitHub release. Add --publish to also create the release.
#
# One-time setup:
#   - a "Developer ID Application" certificate and its private key, in the login keychain or in SIGNING_KEYCHAIN
#   - notary credentials: xcrun notarytool store-credentials rundown-notary --key <AuthKey.p8> --key-id <id> --issuer <uuid>
#
# Usage: scripts/release.sh [--publish]
set -euo pipefail
cd "$(dirname "$0")/.."

APP=rundown
BUNDLE=build/$APP.app
ZIP=build/$APP.zip
PROFILE=${NOTARY_PROFILE:-rundown-notary}
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
# Optional dedicated keychain (unlocked here so codesign never waits on a GUI password prompt):
# SIGNING_KEYCHAIN, with its password in the file next to it named keychain-pass.
KEYCHAIN=${SIGNING_KEYCHAIN:-$HOME/.config/rundown-signing/signing.keychain-db}
KEYCHAIN_ARGS=()
if [ -f "$KEYCHAIN" ]; then
  security unlock-keychain -p "$(cat "$(dirname "$KEYCHAIN")/keychain-pass")" "$KEYCHAIN"
  KEYCHAIN_ARGS=(--keychain "$KEYCHAIN")
fi
IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning ${KEYCHAIN_ARGS[1]:+"${KEYCHAIN_ARGS[1]}"} | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}
[ -n "$IDENTITY" ] || { echo "No Developer ID Application identity in the keychain." >&2; exit 1; }

echo "→ rundown $VERSION, signing as: $IDENTITY"
swift test
swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP

rm -rf "$BUNDLE" "$ZIP"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP"
cp Info.plist "$BUNDLE/Contents/Info.plist"
codesign --force --options runtime --timestamp "${KEYCHAIN_ARGS[@]}" --sign "$IDENTITY" "$BUNDLE"
codesign --verify --strict --verbose=2 "$BUNDLE"

echo "→ notarising (usually a few minutes)"
ditto -c -k --keepParent "$BUNDLE" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$BUNDLE"
rm -f "$ZIP"
ditto -c -k --keepParent "$BUNDLE" "$ZIP"
spctl --assess --type execute --verbose=2 "$BUNDLE"
echo "→ $ZIP ready"

if [ "${1:-}" = "--publish" ]; then
  gh release create "v$VERSION" "$ZIP" --title "rundown $VERSION" --notes-file - <<NOTES
Download **rundown.zip**, unzip, drag **rundown.app** to Applications and open it. Signed and notarised; needs macOS 14 or later.

Try it with one of the [examples](https://github.com/adisidev/rundown/tree/main/examples), e.g. \`grant-intake.md\` for a meeting checklist.
NOTES
  echo "→ https://github.com/adisidev/rundown/releases/latest/download/$APP.zip"
fi
