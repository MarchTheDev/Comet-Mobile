#!/usr/bin/env bash
#
# Fetch Comet at a pinned commit, build its web bundle, and lay it out for the
# iOS shell.
#
# Comet is a Tauri app: the interface is a React/Vite bundle that happens to talk
# to a Rust backend. This script produces that bundle (`web/dist`) and copies it
# into the app, along with the iOS icons Comet already ships.
#
#   COMET_REPO   override the clone URL      (default: MarchTheDev/Comet)
#   COMET_REF    commit, tag or branch        (default: the pinned commit below)
#   COMET_SRC    checkout location            (default: .comet)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Pinned so a build does not change under you. Bump it to pull in Comet changes:
#   COMET_REF=main scripts/prepare.sh
COMET_REPO="${COMET_REPO:-https://github.com/MarchTheDev/Comet.git}"
COMET_REF="${COMET_REF:-ab5a2e7efbc7a1403c42ce7cfdeaa28017864d56}"
COMET_BRANCH="${COMET_BRANCH:-arena/cfb6f0e0-comet}"
SRC="${COMET_SRC:-$ROOT/.comet}"

log() { printf '\033[1m==>\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
log "Comet source → $SRC"
if [ ! -d "$SRC/.git" ]; then
  rm -rf "$SRC"
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin "$COMET_REPO"
fi

if ! git -C "$SRC" cat-file -e "${COMET_REF}^{commit}" 2>/dev/null; then
  log "Fetching $COMET_REF"
  if ! git -C "$SRC" fetch --depth 1 --quiet origin "$COMET_REF" 2>/dev/null; then
    # Some hosts only serve reachable refs by name.
    log "That commit is not fetchable by hash; using $COMET_BRANCH instead"
    git -C "$SRC" fetch --depth 1 --quiet origin "$COMET_BRANCH"
    COMET_REF="$(git -C "$SRC" rev-parse FETCH_HEAD)"
  fi
fi
git -C "$SRC" checkout --quiet --force --detach "$COMET_REF"
RESOLVED="$(git -C "$SRC" rev-parse HEAD)"
log "At $(git -C "$SRC" log -1 --format='%h %s')"

# ---------------------------------------------------------------------------
log "Installing Comet's web dependencies"
if ! (cd "$SRC/web" && npm ci --no-audit --no-fund > "$ROOT/.comet-npm.log" 2>&1); then
  cat "$ROOT/.comet-npm.log"
  exit 1
fi

log "Building the page"
if ! (cd "$SRC/web" && npm run build > "$ROOT/.comet-build.log" 2>&1); then
  cat "$ROOT/.comet-build.log"
  exit 1
fi
if [ ! -f "$SRC/web/dist/index.html" ]; then
  echo "error: Comet's build produced no dist/index.html" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
log "Staging the page into app/Resources/www"
rm -rf "$ROOT/app/Resources/www"
mkdir -p "$ROOT/app/Resources/www"
cp -R "$SRC/web/dist/." "$ROOT/app/Resources/www/"

if [ ! -f "$ROOT/app/Resources/www/index.html" ]; then
  echo "error: app/Resources/www/index.html is missing" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
ICONS="$SRC/web/src-tauri/icons/ios"
CATALOG="$ROOT/app/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$CATALOG"
if [ -d "$ICONS" ]; then
  log "Copying Comet's iOS icons"
  cp "$ICONS"/*.png "$CATALOG"/
  if [ ! -f "$CATALOG/AppIcon-512@2x.png" ]; then
    echo "warning: Comet has no 1024×1024 icon; the App Store icon slot stays empty" >&2
  fi
else
  echo "warning: no iOS icons in the Comet checkout at $ICONS" >&2
fi

# ---------------------------------------------------------------------------
VERSION="$(cat "$SRC/VERSION" 2>/dev/null | tr -d '[:space:]')"
printf '%s\n' "${VERSION:-0.1.0}" > "$ROOT/.comet-version"
printf '%s\n' "$RESOLVED" > "$ROOT/.comet-ref"

log "Ready: Comet ${VERSION:-0.1.0} at ${RESOLVED:0:7}, $(du -sh "$ROOT/app/Resources/www" | cut -f1) of page assets"
