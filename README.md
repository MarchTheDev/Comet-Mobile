# Comet for iOS

An iPhone and iPad build of [Comet](https://github.com/MarchTheDev/Comet), the
local-first notes and files workspace, packaged as a plain **unsigned `.ipa`**
for sideloading. No TestFlight, no App Store, no developer account needed to
build one.

Comet itself is not modified. This repository is a shell that runs the real Comet
interface, unchanged, on top of a small native iOS host, plus a mobile layer that
gives it a phone's shape: no sidebar at all, a translucent bar, a floating glass
dock, a Library sheet, and Comet's content restyled for touch. The layer is injected CSS and JavaScript
(`app/Resources/mobile/`), so updating the pinned Comet commit does not create
conflicts.

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

## The mobile interface

The interface on a phone is **not** a narrower desktop. There is no sidebar at
all: a 330 pt drawer over a 390 pt screen is one app covering another, and
everything in it exists to answer one of two questions — where am I, and what
else can I do. Those are a dock and a sheet.

| | |
| --- | --- |
| Bar | Transparent over the Matterhorn and glass once content scrolls under it. Back on the leading edge when there is somewhere to go, the current name, search on the trailing edge. |
| Dock | A floating glass capsule, inset from the edges, above the home indicator, with a tinted lens on the selected tab: **Files, Search, Calendar, Library**. |
| Create | Its own floating button above the dock — a phone's main verb does not belong in a tab slot. |
| Library | A page sheet holding what the sidebar used to: the workspace switcher, then Browse (All files, Pinned, Favorites, Tree, Brain) and Tools (Calendar, Passwords, Manage tags, Settings), each with the count the app itself shows — and the build number at the bottom, because a sideloaded app has no other way to say which build it is. |
| Search | Comet's own search, opened full-screen from the app's search button: same query, same results, keyboard up. |
| Rows | 68 pt tall, 16.5 pt titles, always-visible menu buttons — there is no hover on a phone. |
| Sheets | Inset cards with a grabber rising from the bottom edge, for menus and dialogs. |
| Status bar | Follows the theme, reported from the page through the bridge. |
| Haptics | Every dock press, sheet row, long press and edge swipe goes through the Taptic Engine. |
| Edge swipe | Dragging in from the left edge goes back, like every other iOS app. |

A page cannot do haptics, the status bar or an edge swipe for itself, so those
three come from Swift (`Presence.swift`).

Comet's sidebar is still in the DOM, still holds its state, and is never drawn:
the sheet presses its rows. That is what keeps routing, counts and permissions
Comet's own — the Library sheet is a lens on the app, not a second application.
The workspace switcher is the app's own menu; while it is open the sidebar
itself becomes the sheet, showing only that menu (`:has()`, iOS 15.4+).

What is kept:

- **The Matterhorn.** Comet's artwork, full-bleed behind the file list, with the
  bar transparent over it at the top of the page.
- **Every palette and both themes.** The layer only ever reads Comet's CSS
  variables (`--canvas`, `--accent`, `--text`, …), so whatever is picked in
  Settings carries through, including the status bar.
- **Typography and shape.** Comet's own type scale and radii; the layer changes
  placement and weight, not the design language.
- **Every feature.** Nothing is hidden or disabled. What the sidebar contained
  is in the Library sheet, the create menu or the document toolbar.

It is scoped to `html.comet-mobile`, a class only added by `mobile.js` inside the
iOS shell, so the same bundle opened on a desktop is untouched. Above 760 px the
layout relaxes back towards the desktop arrangement for iPad.

### The black screen, and why the page paints its own background

Comet's stylesheet paints `.app-shell` and leaves `html` and `body` transparent.
In a browser that is invisible; in a web view it is not, because WKWebView's own
backing surface is black. Any frame where Comet's shell does not cover the
viewport — the inset change while a native sheet like the workspace picker is
dismissed is exactly that — showed black. So the layer paints `--canvas` on
`html`, `body` and `#root`, the worst possible frame is the app's own colour, and
the shell nudges the layer to repaint when the page becomes visible again.

For the same reason only *small* surfaces get `backdrop-filter`. A full-screen
blurred layer is what makes WKWebView lose its backing store after a native sheet,
and at that size a plain tint is indistinguishable.

## The IPA

Each build writes `out/Comet-unsigned.ipa` and attaches it to the `ios-latest`
draft release, so it downloads as an IPA rather than a zipped artifact. A build
also reports what it packaged:

```
ipa: out/Comet-unsigned.ipa (5.6M)
bundle: com.march.comet 0.1.0 (15), minimum iOS 16.0
executable: Comet, architectures arm64
page: index.html 3.5M, 200 PDF.js resources, shim.js 8.0K
mobile layer: mobile.css 32K, mobile.js 32K
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
- Signing tools rewrite the bundle identifier (`com.march.comet` by default, or
  set `BUNDLE_ID` when building), and each identifier gets separate storage.
  Changing it looks like a fresh install: settings, tags and the password vault
  do not move across. That is why the default changed once, from `com.marco.comet`
  to `com.march.comet`: an install of the old build is a different app, so reopen
  your workspace in the new one.
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
    ├── mobile.css            the phone layout, scoped to html.comet-mobile
    ├── mobile.js             bar, dock, Library sheet, long press, edge swipe
    └── Comet                 Swift host
        ├── HTTPServer        loopback HTTP/1.1 on 127.0.0.1:47823
        ├── Site              serves www/, /__file (Range-aware), /__invoke
        ├── Bridge            the command table Comet calls
        ├── Workspace         file operations, path rules, staged imports
        ├── Pickers           document picker, share sheet, backups
        └── Presence          haptics and the status bar
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
app/CometMobile/Presence.swift  haptics and the status bar, the two things a page cannot do
app/Resources/          Info.plist, the bridge shim, the mobile layer, generated www/ and icons
app/Resources/mobile/   mobile.css and mobile.js: the phone interface over Comet's page
project.yml             XcodeGen spec (the .xcodeproj is generated)
scripts/prepare.sh      fetch Comet, build the page, stage assets
scripts/build-ipa.sh    build and package the IPA
scripts/verify-ipa.sh   report what is inside a finished IPA
tools/test-shim.mjs     drives the shim with the genuine @tauri-apps packages
tools/test-mobile.mjs   drives the real Comet UI with the mobile layer installed
.github/workflows/      CI: builds the IPA and publishes the draft release
```

## Checks

`node tools/test-shim.mjs` is worth running after touching the shim: it loads
`shim.js` exactly as the app does, then calls the real `@tauri-apps/api`,
`plugin-dialog`, `plugin-opener` and `plugin-autostart` packages and asserts the
commands that reach the native side.

`node tools/test-mobile.mjs` is the guard on the mobile layer, and it is the
check that matters for appearance. It bundles Comet's real `src/App.tsx`, mounts
it in jsdom against the same bridge shim, then loads `mobile.js` on top and
presses the tabs, the drawer, the New sheet and a long press on a real file. It
asserts what the layer depends on still exists — that a tab reaches the app's own
view, that a long press opens *that row's* menu and does not also open the file,
that the header names the open document, that back is offered exactly when there
is somewhere to go and actually walks it, that scrolling turns the bar to glass,
that a dock press asks the bridge for a tap — plus the CSS invariants: the
stylesheet is scoped, the page paints its own background, the full-screen veils
do not blur, the dock really is glass and has a fallback, menus and dialogs are
inset sheets, inputs are 16 px so iOS does not zoom, and the layers stack in the
intended order.

jsdom has no layout engine, so this proves structure and behaviour, not
appearance. The first run on a device is still the first time anyone sees it.

`scripts/verify-ipa.sh out/Comet-unsigned.ipa` unpacks a finished IPA and checks
the executable architecture, the page, the mobile layer, the icon catalog and
that no signing material came along for the ride.

## Licence

Comet is GPL-3.0, and so is this shell that builds and runs it — see
[`LICENSE`](LICENSE). The `.ipa` it produces contains Comet and is covered by the
same licence: building, installing and sharing it is fine, and the corresponding
source is this repository plus the pinned Comet commit recorded in
`scripts/prepare.sh`.
