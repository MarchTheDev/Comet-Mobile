# Comet for iOS

An iPhone and iPad build of [Comet](https://github.com/MarchTheDev/Comet), the
local-first notes and files workspace — packaged as a plain, **unsigned `.ipa`**
you can sideload. No TestFlight, no App Store, no Apple Developer account needed
to *build* one.

Comet itself is not modified. This repository is a shell that runs the real Comet
interface, unchanged, on top of a small native iOS host.

> **Status:** the pipeline builds a real, installable IPA on every push (see
> [`Actions → iOS`](../../actions/workflows/ios.yml)). That proves it compiles
> and packages. It does not prove every screen behaves on every device — if
> something looks wrong on yours, open an issue with what you saw.

---

## Short answer on Expo

You asked whether [Expo](https://expo.dev) could help. It can't, for a specific
reason worth knowing before you spend time on it:

**Comet is a Tauri app, not a React Native app.** Its interface is React and
Vite, and everything it can do — reading notes from a folder, watching for
changes, the tray icon, autostart, the keyring — is Rust behind Tauri's IPC.
Expo compiles *React Native* to native views; it has no React DOM, no
`localStorage`, no Tauri backend. Handing Comet's source to Expo would produce an
app that renders nothing and implements none of its file commands.

So the question is not "which framework" but "how does a desktop web app with a
native file backend run on iOS". The answer used here:

- The **page** is unchanged, served from `http://127.0.0.1:<port>` inside the app
  (WKWebView). Loopback is a real, *secure* origin, so `localStorage`,
  IndexedDB and WebCrypto — which Comet's settings, tags and password vault need
  — all work. A `file://` page would not be a secure context and the password
  vault would not work at all.
- The **native commands** (`list_vault`, `read_note`, `write_note`, imports,
  pickers…) are reimplemented in Swift with the same names, arguments and JSON
  shapes as Comet's Rust ones.
- Tauri's JavaScript API is provided by one injected shim
  (`app/Resources/shim.js`) that implements `window.__TAURI_INTERNALS__`. That is
  the single funnel every `@tauri-apps/*` call goes through, so Comet's own
  bundle runs untouched.

## Getting the IPA

1. Open **Actions → iOS → Run workflow** (or just push a commit).
2. Wait ~10 minutes (a macOS runner has to be free first).
3. Download the **`Comet-unsigned-ipa`** artifact at the bottom of the run and
   unzip it — GitHub always wraps artifacts in a `.zip`. Inside is
   `Comet-unsigned.ipa`.

The run's summary also prints what ended up inside the package. If you would
rather not use CI at all, `scripts/build-ipa.sh` does the same thing on your own
Mac.

By default it builds the pinned Comet commit in `scripts/prepare.sh`. Pass a
different `comet_ref` in the workflow input to build, say, `main`:

```
Actions → iOS → Run workflow → comet_ref: main
```

## Installing it

The IPA is unsigned on purpose — your tool signs it with your own certificate:

- **Sideloadly** (Windows/macOS) — drop the `.ipa` in, sign in with your Apple ID.
- **AltStore / SideStore** — add the IPA as a source file.
- **Xcode** — `xcodebuild` it yourself, or drag `Comet.app` onto a connected
  device in *Window → Devices and Simulators* (this needs a team in the project).

Notes:

- With a **free Apple ID** the install lasts **7 days** before it has to be
  re-signed. A paid developer account gives a year.
- Your signing tool rewrites the bundle identifier (`com.marco.comet` here), and
  each identifier gets its own separate storage. Changing it looks like a fresh
  install — settings, tags and the password vault do not move across.
- Nothing here needs a Mac except to build from source. The artifact comes from
  GitHub's macOS runners.

## What works

| Area | Notes |
| --- | --- |
| Workspaces | Pick any folder — this app's `Comet` folder, another on the device, or one on iCloud Drive. Remembered across launches with a security-scoped bookmark. |
| Notes and files | Reading, editing, autosave, rename, move, delete, new notes and folders, search, tags, pins, favourites. Same path rules and refusals as the desktop app. |
| Views | List, gallery, Tree, Brain, calendar, to-do boards, whiteboards, settings. |
| Documents | Markdown editor, PDFs (with the bundled PDF.js), EPUB reader, images, audio and video players. |
| Passwords | The AES-GCM vault works: loopback is a secure origin, so WebCrypto is available. Backups are written to `Comet backups/` in the app's Documents folder and offered through the share sheet. |
| Imports | The file picker and Comet's 512 KB chunked upload path, staged `.part` files included, so a cancelled import never leaves a half-written note. |

## What does not

- **Google Calendar and Drive.** The desktop app uses a Desktop OAuth client and
  the OS keyring. Not connected in this build; those settings say so instead of
  failing silently. The local calendar is unaffected.
- **Tray, launch at login, close-to-tray.** Desktop ideas, answered as
  unavailable so the switches do not lie.
- **Desktop drag-and-drop from Finder.** There is no Finder. Use the picker or
  Quick capture.
- **In-app updates.** Comet's updater installs a Windows/macOS build. Here you
  install a newer IPA.

## Building it yourself

Requirements: macOS with Xcode, plus Node 22 and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
scripts/build-ipa.sh        # fetches Comet, builds the page, builds the app
open out/Comet-unsigned.ipa # well, drag it to your sideloading tool
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

`scripts/prepare.sh` pins a commit so a build does not change under you:

```sh
COMET_REF=main scripts/prepare.sh          # or a tag, or a full commit hash
COMET_REPO=https://github.com/you/fork.git scripts/prepare.sh
```

## How it fits together

```
Comet.ipa
└── Comet.app
    ├── www/                  Comet's real web bundle (index.html + PDF.js assets)
    ├── shim.js               implements window.__TAURI_INTERNALS__
    └── Comet                 Swift host
        ├── HTTPServer        loopback HTTP/1.1 on 127.0.0.1:47823
        ├── Site              serves www/, /__file (Range-aware), /__invoke
        ├── Bridge            the command table Comet calls
        ├── Workspace         file operations, path rules, staged imports
        └── Pickers           document picker, share sheet, backups
```

A command travels: page → `invoke()` → `POST /__invoke` → `Bridge` → `Workspace`
→ JSON back. Deliveries of workspace media go the other way: page →
`convertFileSrc()` → `http://127.0.0.1:<port>/__file?path=…` → bytes with
`Content-Range` support, which is what makes seeking in audio and video work.

The port is fixed (`47823`, with a few fallbacks) because the page's origin — and
therefore every byte Comet has saved in `localStorage` — is keyed by host *and*
port. A changing port would look like a fresh install every launch.

### Notes on a few deliberate choices

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
app/Resources/Assets…   committed catalog, icons copied in at build time
project.yml             XcodeGen spec (the .xcodeproj is generated)
scripts/prepare.sh      fetch Comet, build the page, stage assets
scripts/build-ipa.sh    build and package the IPA
tools/test-shim.mjs     drives the shim with the genuine @tauri-apps packages
.github/workflows/      CI: builds the IPA on every push
```

`node tools/test-shim.mjs` is worth running after touching the shim: it loads
`shim.js` exactly as the app does, then calls the real `@tauri-apps/api`,
`plugin-dialog`, `plugin-opener` and `plugin-autostart` packages and asserts the
commands that reach the native side.

## Licence

Comet is GPL-3.0, and so is this shell that builds and runs it — see
[`LICENSE`](LICENSE). The `.ipa` this produces contains Comet and is therefore
covered by the same licence: it is fine to build, install and share, and the
corresponding source is this repository plus the pinned Comet commit recorded in
`scripts/prepare.sh`.
