<div align="center">

# Comet for iOS

**Comet's whole workspace, rebuilt as a native iPhone and iPad app.**

Notes, boards, calendar, feeds, tools, the encrypted vault and every reader —
one app, its own interface, and no account anywhere.

</div>

Comet on the desktop is a folder of ordinary files with a workspace drawn around
it. This is that workspace in SwiftUI, for a phone: the desktop's palettes, its
font, its panels and its vocabulary, laid out for a thumb. It is not a window
onto the desktop app and not a web view with a bar bolted on. It is the same
design, at the size of a hand.

## The idea

The app is a phone-shaped Comet, not a phone-shaped interpretation of one. Where
the desktop app has a sidebar, a cover card, a document header and a set of
small bordered panels, this app has the same — rearranged for a thumb rather
than a mouse, but drawn from the same measurements.

**The desktop's palette, value for value.** Canvas, panel, panel-soft, border,
border-strong, text, secondary, muted, accent, accent-ink, accent-soft: the
fourteen themes in Settings carry exactly the colours the desktop app uses, so a
workspace looks the same on a phone and on a monitor. `System` follows the
appearance.

**The desktop's type.** Manrope, carried in the bundle under the SIL Open Font
License, in the same weights the desktop uses — 800 for titles and eyebrows, 700
for labels, 500 for reading. Headings are tight and small, the way they are on
the desktop, rather than generous the way they are in iOS marketing shots.

**Flat panels, not glass.** Cards are one-pixel-bordered surfaces at a 12-point
corner radius with a barely-there shadow. Buttons are 38-point rectangles with
an 8-point radius. Chips are small, square-shouldered and quiet. Nothing blurs,
nothing glows, and there is no gradient anywhere except the cover card, which is
the accent colour, as on the desktop.

**No bar at the top.** That still holds. The desktop's sidebar becomes a bar at
the bottom of the screen: Today, Files, Search, Studio, a grid that opens
everything else, and the accent `+` that makes a note, a board, a whiteboard or
a folder. Titles live inside the content, above the thing they name.

## What is inside

| Surface | What it does |
| --- | --- |
| **Today** | A cover card with the date and the workspace, pinned notes, today's events, unread reading, what you touched last, and four doors to the rest. |
| **Files** | The folder itself: a path pill, filter chips (All / Folders / Notes / Boards / Media), tag chips, folders as tiles, files as rows, sort, pin, favourite, tags, rename, move, delete, import. |
| **Search** | Filenames, note text and boards, matched as you type, with the path under every result. |
| **Studio** | To-do boards and whiteboards on one bench, each with a live miniature. |
| **Note** | Markdown in two modes: reading, and writing with a formatting bar that edits around the cursor. Autosaves; shows words and reading time. |
| **Boards** | Kanban lists you can tick in place, move between lists, and edit in a sheet; and a whiteboard you can pan, pinch, draw on, and fill with text, to-do, shape and link cards. |
| **Calendar** | Months, days, events and notes, on the device, exporting a standard `.ics`. |
| **Feeds** | RSS, Atom and JSON feeds parsed locally, unread counts, saved articles, OPML in and out, and a reader in Comet's own type. |
| **Passwords** | AES-256-GCM vault with a master password, a recovery code, encrypted backups, and a generator. Comet's desktop vault format. |
| **Tools** | Calculator, unit and temperature conversion, dates, percentages and tax, password generator. |
| **Readers** | Images with pinch and zoom, PDFs with PDFKit, EPUB books chapter by chapter, audio, video and `.url` shortcuts. |
| **Sync** | The change journal is running and this screen shows exactly what is in place and what the update will add. |
| **Settings** | The desktop's fourteen palettes plus System, text size, editor type, haptics, week start, the workspace (with a check that the folder is really writable), about. |

### Comet's formats, unchanged

The app is a Comet client, not a new silo:

- A workspace is a folder. Notes are `.md`, to-do boards `.comet-todo`,
  whiteboards `.comet-whiteboard`, links `.url`; everything else is just files.
- Boards are read and written in Comet's versioned JSON, so a board made here
  opens on the desktop and vice versa.
- Tags, pins, favourites, order, calendar events, feeds and read state live in a
  profile beside the app, keyed to the workspace — never inside the user's files,
  exactly as the desktop app keeps them.
- The password vault is the same envelope: PBKDF2-SHA256 at 600,000 iterations
  over the master password, then AES-256-GCM over the vault. A
  `comet-passwords` backup from the desktop opens here.
- Markdown support matches Comet's subset: headings, lists, checkbox lists,
  quotes, fenced code, rules, tables, emphasis, code, links and images.

## Sync, prepared rather than pretended

Cross-device sync is the next thing to arrive, so the app is built to receive it
rather than to be rewritten for it.

Every change the app makes goes through the model and is recorded in a journal
as a fact: device, time, action, **relative path**, optional previous path, and a
content digest. Deletes are facts, not absences. Identity is relative, so a
workspace moved from `On My iPhone` to iCloud Drive is still the same workspace.
The profile is one versioned JSON document, decoded field by field so an older
build can open a newer profile without discarding it.

That is what a transport needs to reconcile two devices without downloading
everything, and it is already running today. The Sync screen says so plainly:
what is in place, what the update will do, and a switch that stays off until it
does something. See [`docs/sync.md`](docs/sync.md).

## Building it

Requirements: macOS with Xcode 15 or newer, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
scripts/build-ipa.sh          # generate the project, compile, package the IPA
scripts/verify-ipa.sh         # report what ended up in out/Comet-unsigned.ipa
```

The IPA is unsigned on purpose. A sideloading tool signs it with a certificate
of its own:

- **Sideloadly** (Windows/macOS): drop the `.ipa` in and sign in with an Apple ID.
- **AltStore / SideStore**: add the IPA as the source file.
- **Xcode**: `scripts/build-ipa.sh`, then drag `Comet.app` onto a connected
  device in *Window → Devices and Simulators*, with a team set in the project.

A free Apple ID gives a 7-day install that has to be re-signed afterwards; a paid
developer account gives a year. Only the build needs a Mac — the IPA comes out of
GitHub's macOS runners, and CI attaches it to the draft release `ios-latest`.

### In Xcode

```sh
xcodegen generate
open CometMobile.xcodeproj
```

Set a team in *Signing & Capabilities*, then run.

### Tests

```sh
xcodegen generate
xcodebuild test -project CometMobile.xcodeproj -scheme Comet \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

They cover the calculator, the Markdown subset, both board formats, the calendar
export, feed parsing and OPML, the workspace store's containment and naming, the
tolerant profile reader, and the vault envelope. CI runs them on a simulator
beside every build; the workflow picks whichever iPhone the runner has.

## Repository layout

```
CometApp/
  App/                 the app entry point, the shell, the model
  Design/              palettes, theme, aurora background, chrome, components
  Model/               entry kinds, profile, boards, markdown, feeds, epub, sync journal, tools
  Store/               workspace files, profile + journal, vault, services
  Features/
    Today/ Files/ Search/ Studio/ Note/ Calendar/ Feeds/ Vault/ Tools/
    Reader/ Settings/ Shared/
  Resources/           Info.plist, asset catalog and app icon
Tests/                 unit tests for the model, stores and formats
project.yml            XcodeGen spec (the .xcodeproj is generated)
scripts/               build and verify the IPA
docs/                  design notes and the sync plan
preview/               the design preview, in a browser
.github/workflows/     CI: compile, test, package, publish the draft release
```

### How a screen is put together

`RootView` resolves the palette once and hands it down through the environment
as `\.comet`, together with the type scale as `\.type`. Views never reach for a
global. `CometModel` owns the folder, the files, the profile, the vault and the
navigation state; screens call methods on it and it writes, journals and
republishes. The file system is only touched by `WorkspaceStore`, which checks
every path stays inside the chosen folder and writes atomically.

## What it does not do

- **Google Calendar and Drive.** The desktop app's OAuth client is desktop-only;
  nothing here signs into Google. The local calendar and the workspace are
  unaffected.
- **Tray, launch at login, tray on close.** Desktop ideas. They are absent rather
  than present and broken.
- **In-app updates.** A new build is a new IPA.
- **Sync**, for now — see above.

## Design notes

[`docs/design.md`](docs/design.md) covers the mapping from the desktop's CSS
variables to the app's palette, the type scale, the chrome and the reasons it
sits where it does. [`preview/`](preview/)
contains a browser preview of the same screens for looking at the design without
a device.

## Licence

Comet is GPL-3.0, and so is this app — see [`LICENSE`](LICENSE). The app contains
no Comet code; it reads and writes the formats of
[MarchTheDev/Comet](https://github.com/MarchTheDev/Comet), whose source and
licence are the other half of the corresponding source for a build.

The interface is set in **Manrope**, bundled under the SIL Open Font License
1.1; the licence is at `CometApp/Resources/Fonts/Manrope-OFL.txt`.
