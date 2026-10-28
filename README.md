# Comet for iOS

An iPhone and iPad build of [Comet](https://github.com/MarchTheDev/Comet), the
local-first notes and files workspace, packaged as a plain **unsigned `.ipa`**
for sideloading. No TestFlight, no App Store, no developer account needed to
build one.

Comet itself is not modified. This repository is a shell that runs the real Comet
interface, unchanged, on top of a small native iOS host.

> **Status:** every build produces a real, installable IPA and checks its
> contents. That proves it compiles and packages; it does not prove every screen
> behaves on every device.

## How it works

Comet is a Tauri app: a React/Vite interface over a Rust backend, with nothing in
common with React Native. Rather than reimplement the interface, the shell keeps
it and replaces only the native half.

- The **page** is unchanged, served from `http://127.0.0.1:<port>` inside the app
  (WKWebView). Loopback is a real, *secure* origin, so `localStorage`, IndexedDB
  and WebCrypto — which Comet's settings, tags and password vault need — all
  work. A `file://` page is an opaque origin, and the password vault would not
  work at all.
- The **native commands** (`list_vault`, `read_note`, `write_note`, imports,
  pickers…) are implemented in Swift with the same names, arguments and JSON
  shapes as Comet's Rust ones.
- Tauri's JavaScript API is provided by one injected shim
  (`app/Resources/shim.js`) that implements `window.__TAURI_INTERNALS__`. That is
  the single funnel every `@tauri-apps/*` call goes through, so Comet's own
  bundle runs untouched.

## The IPA

Each build writes `out/Comet-unsigned.ipa` and attaches it to the `ios-latest`
draft release, so it downloads as an IPA rather than a zipped artifact. A build
also reports what it packaged:

```
ipa: out/Comet-unsigned.ipa (5.6M)
bundle: com.marco.comet 0.1.0, minimum iOS 16.0
executable: Comet, architectures arm64
page: index.html 3.5M, 200 PDF.js resources, shim.js 8.0K
signing: code signature no, provisioning profile no
assets: Assets.car 176K
```

## Installing it

The IPA is unsigned on purpose — a sideloading tool signs it with a certificate
of its own:

- **Sideloadly** (Windows/macOS): drop the `.ipa` in and sign in with an Apple ID.
- **AltStore / SideStore**: add the IPA as the source file.
- **Xcode**: drag `Comet.app` onto a connected device in *Window → Devices and
  Simulators*, with a team set in the project.

Notes:

- A **free Apple ID** gives a 7-day install that has to be re-signed afterwards.
  A paid developer account gives a year.
- Signing tools rewrite the bundle identifier (`com.marco.comet` here), and each
  identifier gets separate storage. Changing it looks like a fresh install:
  settings, tags and the password vault do not move across.
- Only the build needs a Mac; the IPA comes out of GitHub's macOS runners.

## What works

| Area | Notes |
| --- | --- |
| Workspaces | Any folder — the app's own `Comet` folder, another on the device, or one on iCloud Drive. Remembered across launches with a security-scoped bookmark. |
| Notes and files | Reading, editing, autosave, rename, move, delete, new notes and folders, search, tags, pins, favourites. Same path rules and refusals as the desktop app. |
| Views | List, gallery, Tree, Brain, calendar, to-do boards, whiteboards, settings. |
| Documents | Markdown editor, PDFs with the bundled PDF.js, EPUB reader, images, audio and video players. |
| Passwords | The AES-GCM vault works, because loopback is a secure origin and WebCrypto is available. Backups are written to `Comet backups/` in the app's Documents folder and offered through the share sheet. |
| Imports | The file picker and Comet's 512 KB chunked upload path, staged `.part` files included, so a cancelled import never leaves a half-written note. |

## What does not

- **Google Calendar and Drive.** The desktop app uses a Desktop OAuth client and
  the OS keyring. Not connected in this build; those settings report that they
  are unavailable. The local calendar is unaffected.
- **Tray, launch at login, close-to-tray.** Desktop ideas, answered as
  unavailable so the switches do not lie.
- **Desktop drag-and-drop from Finder.** Use the picker or Quick capture.
- **In-app updates.** Comet's updater installs a Windows/macOS build; here a new
  IPA is installed instead.

## Building it

Requirements: macOS with Xcode, plus Node 22 and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
scripts/build-ipa.sh          # fetch Comet, build the page, build the app
scripts/verify-ipa.sh         # optional: report what ended up in the bundle
```

The two halves:

- `scripts/prepare.sh` clones Comet at the pinned commit, runs its own
  `npm ci && npm run build`, and stages `web/dist` into `app/Resources/www`
  together with Comet's iOS icon set.
- `scripts/build-ipa.sh` generates the Xcode project from `project.yml`, builds
  for `iphoneos` with signing disabled, and zips `Payload/Comet.app` into an IPA.

To open it in Xcode instead:

```sh
scripts/prepare.sh && xcodegen generate && open CometMobile.xcodeproj
```

Set a team in *Signing & Capabilities*, then run on a device.

### Keeping up with Comet

`scripts/prepare.sh` pins a commit so a build does not change underfoot:

```sh
COMET_REF=main scripts/prepare.sh          # a branch, a tag, any commit
COMET_REPO=https://github.com/you/fork.git scripts/prepare.sh
```

## How it fits together

```
Comet.ipa
└── Comet.app
    ├── www/                  Comet's web bundle (index.html + PDF.js assets)
    ├── shim.js               implements window.__TAURI_INTERNALS__
    └── Comet                 Swift host
        ├── HTTPServer        loopback HTTP/1.1 on 127.0.0.1:47823
        ├── Site              serves www/, /__file (Range-aware), /__invoke
        ├── Bridge            the command table Comet calls
        ├── Workspace         file operations, path rules, staged imports
        └── Pickers           document picker, share sheet, backups
```

A command travels: page → `invoke()` → `POST /__invoke` → `Bridge` → `Workspace`
→ JSON back. Workspace media goes the other way: page → `convertFileSrc()` →
`http://127.0.0.1:<port>/__file?path=…` → bytes with `Content-Range` support,
which is what makes seeking in audio and video work.

The port is fixed (`47823`, with a few fallbacks) because the page's origin — and
therefore everything Comet has saved in `localStorage` — is keyed by host *and*
port. A changing port would look like a fresh install every launch.

### A few deliberate choices

- **A local server rather than a custom URL scheme.** A custom scheme would be
  tidier, but WKWebView does not treat it as a secure context, so
  `crypto.subtle` would be `undefined` and the password vault would be dead.
  `http://127.0.0.1` is both a secure context and a stable origin.
- **One request per connection.** The traffic is a page load, a handful of
  commands and streaming media; keep-alive would only add state to get wrong.
- **`NSAllowsArbitraryLoads`.** Needed for the page to load from plain HTTP on
  loopback. This is a sideloading build, not an App Store submission.
- **Answers, not silence, for desktop-only commands.** A switch that flips and
  does nothing is worse than one that reports it cannot.

## Repository layout

```
app/CometMobile/        the Swift host
app/Resources/          Info.plist, the bridge shim, generated www/ and icons
project.yml             XcodeGen spec (the .xcodeproj is generated)
scripts/prepare.sh      fetch Comet, build the page, stage assets
scripts/build-ipa.sh    build and package the IPA
scripts/verify-ipa.sh   report what is inside a finished IPA
tools/test-shim.mjs     drives the shim with the genuine @tauri-apps packages
.github/workflows/      CI: builds the IPA and publishes the draft release
```

## Checks

`node tools/test-shim.mjs` is worth running after touching the shim: it loads
`shim.js` exactly as the app does, then calls the real `@tauri-apps/api`,
`plugin-dialog`, `plugin-opener` and `plugin-autostart` packages and asserts the
commands that reach the native side.

`scripts/verify-ipa.sh out/Comet-unsigned.ipa` unpacks a finished IPA and checks
the executable architecture, the page, the icon catalog and that no signing
material came along for the ride.

## Licence

Comet is GPL-3.0, and so is this shell that builds and runs it — see
[`LICENSE`](LICENSE). The `.ipa` it produces contains Comet and is covered by the
same licence: building, installing and sharing it is fine, and the corresponding
source is this repository plus the pinned Comet commit recorded in
`scripts/prepare.sh`.
