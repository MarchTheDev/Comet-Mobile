# Sync: what is in place, and what arrives

The Sync screen in the app says the same thing in fewer words. This is the long
version: what the app already guarantees, what the future transport has to do
with it, and why it was built this way before there was anything to sync to.

## The promise

Two devices holding the same workspace should converge without either one being
the truth. A note written on the phone on a train and a note written on the
desktop at home should both survive; the same note edited in both places should
resolve by time, not by luck; a delete should stay deleted instead of returning
because the other side still has the file.

Comet's desktop app already syncs through a two-phase *prepare / apply / publish*
cycle over a remote folder. This app keeps the same shape, because a phone should
not need a different protocol from a desktop.

## What already exists

### 1. Everything is a relative path

`Entry.relativePath` — `notes/Ideas.md`, `boards/Release.comet-todo` — is the
identity of a file. No absolute URLs, no bookmarks, no volume identifiers. A
workspace moved from *On My iPhone* to iCloud Drive, or restored onto a new
device in a different container, keeps every identity it had. Nothing in the
journal, the profile, the pin list or the tag list has to be rewritten when that
happens.

### 2. The journal records facts

`SyncJournal` stores `ChangeRecord`s:

```swift
struct ChangeRecord {
    let id: String          // stable, sortable
    let at: Date            // when the app saw it happen
    let device: String      // "Aurora-iPhone", stable per install
    let action: ChangeAction// create, update, delete, move, rename, ...
    let path: String        // where it happened
    let previousPath: String?
    let digest: String?     // FNV-1a of the content, when there is content
}
```

Three deliberate choices sit in that struct:

- **Deletes are facts.** The app records that a path was deleted rather than
  letting the absence of a file stand for it. Absence cannot distinguish "never
  existed here" from "deleted here", and a sync engine built on absence
  resurrects files forever.
- **Moves carry both paths.** A rename is one record, not a delete plus a create,
  so the other side can move the file and keep its pins, tags and read state.
- **Digests, not contents.** Two devices can compare `digest` to know whether
  they differ without shipping the body first. `Digest` is FNV-1a over the bytes,
  which is enough for change detection and costs nothing on a phone.

The journal is capped by count and age (`ProfileStore.compactJournal`), and the
Sync screen shows how many records it holds and offers to compact it. Until a
transport consumes it, compacting loses nothing — the files themselves are the
state.

### 3. The profile is one versioned document

Tags, pins, favourites, manual order, calendar events, feeds, read and saved
state, and the sync keys (`@calendar`, `@feeds`, `@tag`, `@profile`) all live in
`profile.json` beside the app, per workspace, keyed by
`Digest(workspacePathHint + "|" + workspaceName)`.

The document carries a schema version, and `ProfileStore` decodes field by field
with defaults. An older build opening a newer profile keeps what it understands
and does not throw the rest away — the difference matters the first time two
devices run different versions of the app.

### 4. Writes are atomic and contained

`WorkspaceStore` resolves every relative path against the chosen folder and
refuses anything that escapes it. Writes go to disk atomically, text is UTF-8,
imports are staged, and the size limit (16 MB) matches the desktop app's. A sync
engine that crashes mid-write leaves either the old file or the new one, never
half of each.

### 5. A device identity exists

`SyncJournal.deviceName` is generated once per install and kept in the profile
directory, so records can be attributed without an account.

## What the update will add

1. **A remote.** A folder the app can write to — WebDAV, an S3-compatible
   bucket, or a user-chosen folder inside iCloud Drive or a synced provider.
   The setting is a URL plus credentials, stored in the Keychain, not in
   settings JSON.
2. **The three phases, per device.**
   - *Prepare*: upload this device's journal and its current profile version to a
     staging area named after the device. Nothing is merged yet.
   - *Apply*: read every other device's staging area, reconcile records by path
     and time, and write the result into the workspace and the profile.
   - *Publish*: upload the reconciled journal and profile, then clear the staging
     areas that were consumed.
3. **Conflict policy**, in this order:
   - A path edited on only one device since the last sync takes that edit.
   - A path edited on both keeps the newer version and writes the older one
     beside it as `Name (conflict, Device, 2026-11-17).md`, so nobody loses words.
   - A rename wins over a delete; a delete younger than a rename wins over the
     rename. Deletes are compared by timestamp, and the journal keeps them long
     enough for the comparison to be possible.
   - Profile merges are per key: tags and pins union, order prefers the newer
     manual order, events and feeds resolve by id and timestamp.
4. **The screen turns on.** The switch stops being a promise, the device card
   lists the remote, and the journal count becomes a sync status with a last-run
   time.
5. **Background refresh** through `BGAppRefreshTask`, so a sync happens when the
   phone is charged and on Wi-Fi rather than when the app is open.

## What will not be built

- **An account.** The remote is a folder the user already controls. There is no
  Comet server and none is planned.
- **Live collaborative editing.** Files converge between syncs; they are not
  co-edited character by character.
- **Sync of the password vault through the app's own transport.** The vault is
  already encrypted at rest; if it syncs through a user-chosen folder, it does so
  as the ciphertext it is — the master password never leaves the device.

## Reading the code

| Concern | File |
| --- | --- |
| Records, device identity, digest | `CometApp/Model/SyncJournal.swift` |
| Profile document, keys, hashing | `CometApp/Model/Settings.swift`, `CometApp/Model/Profile.swift` |
| Persistence, journal cap, summary | `CometApp/Store/ProfileStore.swift` |
| Where every mutation is recorded | `CometApp/App/CometModel.swift` |
| What the user is told | `CometApp/Features/Settings/SyncScreen.swift` |
