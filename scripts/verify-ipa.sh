#!/usr/bin/env bash
#
# Look inside the finished IPA and report what is actually in it.
#
# This is the last place a mistake shows up cheaply: a missing page, a stub
# executable, the wrong architecture or an unreadable Info.plist all get caught
# here instead of on someone's phone.
#
#   scripts/verify-ipa.sh out/Comet-unsigned.ipa
#
set -euo pipefail

IPA="${1:-out/Comet-unsigned.ipa}"
if [ ! -f "$IPA" ]; then
  echo "error: $IPA not found" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$IPA" -d "$WORK"

APP="$WORK/Payload/Comet.app"
fail() { echo "error: $*" >&2; exit 1; }

[ -d "$APP" ] || fail "the IPA has no Payload/Comet.app"
[ -f "$APP/Comet" ] || fail "the app has no executable"
[ -f "$APP/Info.plist" ] || fail "the app has no Info.plist"
[ -f "$APP/www/index.html" ] || fail "the Comet page is missing from the app"
[ -f "$APP/shim.js" ] || fail "the Tauri bridge shim is missing from the app"
[ -f "$APP/Assets.car" ] || fail "the compiled asset catalog is missing"

read_plist() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Info.plist" 2>/dev/null || echo "?"
}

BUNDLE_ID="$(read_plist CFBundleIdentifier)"
VERSION="$(read_plist CFBundleShortVersionString)"
BUILD="$(read_plist CFBundleVersion)"
MINIMUM="$(read_plist MinimumOSVersion)"
EXECUTABLE="$(read_plist CFBundleExecutable)"

ARCH="$(lipo -archs "$APP/$EXECUTABLE" 2>/dev/null || echo unknown)"
PAGE_SIZE="$(du -h "$APP/www/index.html" | cut -f1)"
PDFJS_COUNT="$(find "$APP/www/pdfjs" -type f 2>/dev/null | wc -l | tr -d ' ')"
SHIM_SIZE="$(du -h "$APP/shim.js" | cut -f1)"
IPA_SIZE="$(du -h "$IPA" | cut -f1)"
SIGNED="no"
[ -d "$APP/_CodeSignature" ] && SIGNED="yes"
PROVISION="no"
[ -f "$APP/embedded.mobileprovision" ] && PROVISION="yes"

echo "ipa: $IPA ($IPA_SIZE)"
echo "bundle: $BUNDLE_ID $VERSION ($BUILD), minimum iOS $MINIMUM"
echo "executable: $EXECUTABLE, architectures $ARCH"
echo "page: index.html $PAGE_SIZE, $PDFJS_COUNT PDF.js resources, shim.js $SHIM_SIZE"
echo "signing: code signature $SIGNED, provisioning profile $PROVISION"
echo "assets: Assets.car $(du -h "$APP/Assets.car" | cut -f1)"

if [ "$ARCH" = "unknown" ] || ! echo "$ARCH" | grep -q "arm64"; then
  fail "the executable is not an arm64 iOS binary"
fi
if [ "$SIGNED" = "yes" ] || [ "$PROVISION" = "yes" ]; then
  echo "note: this IPA carries signing material; a truly unsigned build should not" >&2
fi
