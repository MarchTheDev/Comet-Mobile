#!/usr/bin/env bash
# Report what is inside a finished IPA: the executable, the version, the icon
# catalog, and whether any signing material came along.
set -euo pipefail

IPA="${1:-out/Comet-unsigned.ipa}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

unzip -q "$IPA" -d "$TMP"
APP="$(find "$TMP/Payload" -maxdepth 1 -name '*.app' -print -quit)"
[ -n "$APP" ] || { echo "no .app inside the IPA" >&2; exit 1; }

plist="$APP/Info.plist"
echo "bundle: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist") $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist"))"
echo "minimum iOS: $(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$plist" 2>/dev/null || echo unknown)"
echo "executable: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
lipo -info "$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")" || true
[ -f "$APP/Assets.car" ] && echo "assets: Assets.car $(du -h "$APP/Assets.car" | cut -f1)" || echo "assets: none"
echo "swift files: $(find "$APP" -name '*.swift' | wc -l | tr -d ' ') (0 expected: sources are compiled)"
echo "signing: code signature $([ -d "$APP/_CodeSignature" ] && echo yes || echo no), provisioning profile $([ -f "$APP/embedded.mobileprovision" ] && echo yes || echo no)"
echo "size: $(du -h "$IPA" | cut -f1)"
