#!/usr/bin/env bash
#
# Build an unsigned Comet.ipa.
#
# "Unsigned" means exactly that: no Apple developer identity, no provisioning
# profile, no TestFlight. Sideloading tools (Sideloadly, AltStore, SideStore,
# Xcode) sign the bundle themselves with whatever certificate you have, which is
# the only way to install an IPA without an App Store review or a paid account.
#
#   scripts/build-ipa.sh                # prepare Comet, then build
#   scripts/build-ipa.sh --skip-prepare  # build what is already staged
#
# Output: out/Comet-unsigned.ipa
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SKIP_PREPARE=0
for argument in "$@"; do
  case "$argument" in
    --skip-prepare) SKIP_PREPARE=1 ;;
    *) echo "unknown option: $argument" >&2; exit 2 ;;
  esac
done

log() { printf '\033[1m==>\033[0m %s\n' "$*"; }

if [ "$SKIP_PREPARE" -eq 0 ]; then
  "$ROOT/scripts/prepare.sh"
fi

if [ ! -f "$ROOT/app/Resources/www/index.html" ]; then
  echo "error: the Comet page is not staged yet; run scripts/prepare.sh first" >&2
  exit 1
fi

VERSION="$(cat "$ROOT/.comet-version" 2>/dev/null || echo 0.1.0)"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"

if ! command -v xcodebuild >/dev/null; then
  echo "error: xcodebuild is missing. iOS apps can only be built on macOS with Xcode." >&2
  exit 1
fi
if ! command -v xcodegen >/dev/null; then
  log "Installing XcodeGen (needed to write the .xcodeproj)"
  if command -v brew >/dev/null; then
    brew install xcodegen
  else
    echo "error: install XcodeGen first: https://github.com/yonaskolb/XcodeGen" >&2
    exit 1
  fi
fi

log "Generating CometMobile.xcodeproj"
xcodegen generate --spec project.yml

log "Building Comet $VERSION ($BUILD_NUMBER) for iOS arm64"
xcodebuild \
  -project CometMobile.xcodeproj \
  -scheme Comet \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

APP="$ROOT/build/Build/Products/Release-iphoneos/Comet.app"
if [ ! -d "$APP" ]; then
  echo "error: the build finished without producing $APP" >&2
  exit 1
fi
if [ ! -f "$APP/Comet" ]; then
  echo "error: $APP has no executable" >&2
  exit 1
fi

# An IPA is a zip with a single top-level "Payload" directory.
log "Packaging the IPA"
rm -rf "$ROOT/out/Payload" "$ROOT/out/Comet-unsigned.ipa"
mkdir -p "$ROOT/out/Payload"
ditto "$APP" "$ROOT/out/Payload/Comet.app"
(cd "$ROOT/out" && ditto -c -k --sequesterRsrc --keepParent Payload "Comet-unsigned.ipa")

IPA="$ROOT/out/Comet-unsigned.ipa"
log "Built $IPA ($(du -h "$IPA" | cut -f1))"
echo
echo "Install it with Sideloadly, AltStore/SideStore, or Xcode's Devices window."
echo "The bundle identifier is $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || echo 'com.marco.comet')."
