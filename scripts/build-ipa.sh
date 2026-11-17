#!/usr/bin/env bash
# Build Comet for iOS as an unsigned .ipa.
#
#   scripts/build-ipa.sh            # generate the project, compile, package
#   scripts/build-ipa.sh --archive  # also zip the dSYMs
#
# Requires macOS with Xcode and XcodeGen (brew install xcodegen).
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_NUMBER="${BUILD_NUMBER:-1}"
OUT="out"
DERIVED="build"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required: brew install xcodegen" >&2
  exit 1
fi

echo "==> generating the Xcode project"
xcodegen generate >/dev/null

echo "==> building for iphoneos (unsigned)"
mkdir -p "$OUT" "$DERIVED"
set -o pipefail
xcodebuild \
  -project CometMobile.xcodeproj \
  -scheme Comet \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=iOS' \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build 2>&1 | tee .xcodebuild.log | grep -E "^(error|warning:|note:|\*\* )" || true

APP="$DERIVED/Build/Products/Release-iphoneos/Comet.app"
if [ ! -d "$APP" ]; then
  echo "build did not produce Comet.app — see .xcodebuild.log" >&2
  tail -40 .xcodebuild.log >&2
  exit 1
fi

echo "==> packaging"
rm -rf "$OUT/Payload" "$OUT/Comet.app" "$OUT/Comet-unsigned.ipa"
mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/Comet.app"
(cd "$OUT" && zip -qry "Comet-unsigned.ipa" Payload)
rm -rf "$OUT/Payload"

if [ "${1:-}" = "--archive" ] && compgen -G "$DERIVED/Build/Products/Release-iphoneos/*.dSYM" >/dev/null; then
  (cd "$DERIVED/Build/Products/Release-iphoneos" && zip -qry "$OLDPWD/$OUT/Comet-dSYMs.zip" ./*.dSYM)
fi

size=$(du -h "$OUT/Comet-unsigned.ipa" | cut -f1)
echo "ipa: $OUT/Comet-unsigned.ipa ($size)"
echo "bundle: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || echo unknown)"
echo "executable: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist" 2>/dev/null || echo unknown)"
