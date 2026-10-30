#!/bin/bash
#
# Builds, signs (Developer ID), notarizes and staples the RemoteMac app, then packages it
# into a notarized, stapled DMG:  dist/CouchRemote-<version>.dmg
#
# One-time setup (see README "Putting the Mac app on your personal laptop"):
#   - a "Developer ID Application" certificate in your login keychain
#   - a notarytool keychain profile:  xcrun notarytool store-credentials couchremote ...
# This script never asks for, reads, or stores any Apple ID password.
#
# Usage:  scripts/release-mac.sh

set -euo pipefail

PROFILE="couchremote"
SCHEME="RemoteMac"
APP_NAME="CouchRemote"

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build/release"
DIST="$ROOT/dist"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# --- Preconditions -----------------------------------------------------------------------

step "Checking preconditions"

if [[ -n "$(git status --porcelain)" ]]; then
    git status --short >&2
    die "Uncommitted changes. Commit or stash them first so the DMG always matches a commit."
fi

IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
[[ -n "$IDENTITY" ]] || die "No 'Developer ID Application' certificate in the keychain.
Create one: Xcode > Settings > Accounts > your team > Manage Certificates > + > Developer ID Application."
echo "Signing identity: $IDENTITY"

xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || die "No working notarytool profile named '$PROFILE'. Create it yourself with:
  xcrun notarytool store-credentials $PROFILE --apple-id <email> --team-id 5PYDBJJN92 --password <app-specific password>"

command -v xcodegen >/dev/null || die "xcodegen not found (brew install xcodegen)."

VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' project.yml | head -1)"
BUILD_NUMBER="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' project.yml | head -1)"
[[ -n "$VERSION" && -n "$BUILD_NUMBER" ]] || die "Could not read MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml."
echo "Version: $VERSION ($BUILD_NUMBER)  commit: $(git rev-parse --short HEAD)"

# Submits a file to Apple's notary service and waits. Prints the log and fails unless accepted.
notarize() {
    local file="$1" json status id
    step "Notarizing $(basename "$file") (usually 2-10 minutes)"
    json="$(xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait --output-format json)" \
        || { echo "$json" >&2; die "notarytool submit failed."; }
    status="$(plutil -extract status raw -o - - <<<"$json")"
    id="$(plutil -extract id raw -o - - <<<"$json")"
    echo "Submission $id: $status"
    if [[ "$status" != "Accepted" ]]; then
        xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
        die "Notarization of $(basename "$file") was not accepted ($status). Log above."
    fi
}

# --- Build ----------------------------------------------------------------------------------

step "Generating the Xcode project"
xcodegen generate

rm -rf "$BUILD"
mkdir -p "$BUILD" "$DIST"

step "Archiving $SCHEME (Release)"
xcodebuild archive \
    -project CouchRemote.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$BUILD/$APP_NAME.xcarchive" \
    | tail -n 5

step "Exporting with Developer ID signing"
xcodebuild -exportArchive \
    -archivePath "$BUILD/$APP_NAME.xcarchive" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$BUILD/export" \
    | tail -n 5

APP="$BUILD/export/$APP_NAME.app"
[[ -d "$APP" ]] || die "Export did not produce $APP."

# --- Verify the signed app before spending time on notarization -------------------------

step "Verifying the signature, Hardened Runtime and entitlements"
codesign --verify --deep --strict --verbose=2 "$APP"
SIGNING_INFO="$(codesign -dvv "$APP" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$SIGNING_INFO" || die "App is not signed with Developer ID."
grep -q "flags=0x[0-9a-f]*(.*runtime.*)" <<<"$SIGNING_INFO" || die "Hardened Runtime is not enabled."
ENTITLEMENTS="$(codesign -d --entitlements - "$APP" 2>&1 || true)"
if grep -q "get-task-allow" <<<"$ENTITLEMENTS"; then die "get-task-allow is present (a debug entitlement)."; fi
if grep -q "com.apple.security.app-sandbox" <<<"$ENTITLEMENTS"; then die "The app sandbox is on; input injection would not work."; fi
echo "OK: Developer ID, Hardened Runtime, no get-task-allow, not sandboxed."

# --- Notarize + staple the app --------------------------------------------------------------

ZIP="$BUILD/$APP_NAME-notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"

step "Stapling the app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# --- DMG ---------------------------------------------------------------------------------

DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGE="$BUILD/dmg"

step "Building $(basename "$DMG")"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"   # the stapled app
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"

notarize "$DMG"

step "Stapling the DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# An unversioned copy, so https://github.com/<repo>/releases/latest/download/CouchRemote.dmg
# (the README button and the phone app's link) always serves the newest build.
cp "$DMG" "$DIST/$APP_NAME.dmg"

# --- Final Gatekeeper check ---------------------------------------------------------------

step "Gatekeeper assessment"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
spctl --assess --type execute --verbose=2 "$APP"

printf '\n\033[32mDone.\033[0m  %s  (%s)\n' "$DMG" "$(du -h "$DMG" | cut -f1)"
echo "Version $VERSION ($BUILD_NUMBER) from commit $(git rev-parse --short HEAD)."
echo "Publish with: gh release create v$VERSION \"$DMG\" \"$DIST/$APP_NAME.dmg\" --title \"CouchRemote $VERSION\""
