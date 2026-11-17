# Design

The app is not a phone-shaped version of the desktop window. It has no navigation
bar, no sidebar, no toolbar, and no table of contents. What replaces them is a
set of rules small enough to hold in mind.

## The three floating things

1. **The dock**, at the bottom: Today, Files, Search, Studio. Three glass
   capsules with a sliding lens behind the current one. It floats over the
   content with a gradient scrim behind it, so lists can scroll beneath without
   being cut by a bar.
2. **The orb**, beside the dock: one circle, slightly larger, carrying the
   accent gradient. It opens everything the dock does not hold — calendar,
   feeds, vault, tools, sync, settings — as an overlay of destinations, not a
   sidebar.
3. **The lens**, top-left, in screens that go deeper: a 38-point circle with a
   chevron, or an × when a screen is a detour rather than a place.

Nothing else is fixed. Titles live in the scroll and leave when the content
does.

## Rhythm

Screens are built from four moves, in order:

- A **module header** or **screen header**: a small uppercase eyebrow, a large
  title in the display face, and a subtitle that says something true.
- A **hero card** for the one thing that matters on that screen — today's date,
  the folder path, the current month.
- **Cards** at 26–30 pt radius with a hairline and a soft lift, separated by 14
  to 18 points, sectioned by uppercase labels.
- A **trailing accessory** in the header: a glass circle for a secondary action,
  a filled gradient circle for the primary one.

Every screen follows that, which is why none of them needs a bar to explain
itself.

## Palettes

Sixteen palettes, each a complete world of eight values: `canvasGradient`,
`surface`, `raised`, `ink`, `secondary`, `tertiary`, `accent`, `accentTwo`,
`hairline`, plus `isDark`. Nothing in the app names a colour directly; every
view reads `@Environment(\.comet)`.

| Palette | Idea |
| --- | --- |
| Midnight | Deep blue-black, cold cyan accent. The default. |
| Aurora | Teal and violet over near-black. |
| Ember | Warm charcoal, amber and rust. |
| Sakura | Paper pink, ink dark, blossom accent. |
| Matcha | Muted green over bone. |
| Navy / Emerald / Rubellite | Single-hue worlds, each with its own shadow. |
| Gothic / Frog / Nightjar / Onyx | Dark, saturated, a little strange. |
| 0807 Light / 0807 Dark | The desktop app's pair, for continuity. |
| Daylight | Bright, high contrast, legible outdoors. |
| Auto | Follows the system, resolving to Midnight or Daylight. |

Because the palette supplies both accents and both surfaces, a sheet, a chip, a
selected dock lens and the aurora background all change together. There is no
half-themed corner.

## Type

One family for the interface (SF Pro), one for reading (New York via
`Font.system(.serif)`), one mono for code, calculation and paths. Three sizes
matter:

- **Display** — 28 to 40 pt, tight tracking, for the one title per screen.
- **Prose** — 16 to 17 pt with generous line spacing for notes and articles.
- **Label** — 10.5 to 13 pt, uppercase with wide tracking for eyebrows and
  section labels.

`CometSettings.textScale` multiplies the whole scale from 85% to 125% and is
applied through the environment, so no view can forget it.

## Motion

Three curves, no more:

- `Motion.snappy` (0.28 s, 0.86 damping) for selection, presses and sheet
  contents.
- `Motion.gentle` (0.45 s) for palette changes, expands and layout.
- Implicit spring for cards appearing, staggered by 40 ms per row through
  `Stagger`, capped so a long list does not become a slideshow.

The aurora background drifts on a slow timeline — 40 seconds per cycle — which
is only visible if you look for it, which is the point.

## Touch

- Dock and orb sit in the bottom fifth of the screen.
- Every interactive element is at least 38 points, most are 44.
- Primary actions are on the right of headers and the bottom of sheets.
- Sheets use a 34 pt corner radius, a grabber, and the palette's own surface, so
  a sheet looks like it belongs to the screen behind it.
- Long-press is never the only way to reach something: every context menu has an
  equivalent in a sheet.

## Haptics

`Haptics.select()` on a chip or a dock lens, `Haptics.press()` on a primary
action, `Haptics.drop()` when a drag lands, `Haptics.warn()` on a failure, and a
single tick on completing a to-do. They are disabled by one switch in Settings,
and the model is where the truth is kept.

## What was rejected

- **A top bar.** It would have been the honest thing to port, and the user asked
  for the opposite.
- **A tab bar as the whole navigation.** Four tabs cannot hold thirteen
  surfaces, and a fifth "More" tab is a drawer with extra steps. Hence the orb.
- **A desktop two-pane layout on iPad.** The iPad gets more room, larger cards
  and wider margins — not a second pane. Portrait and landscape are the same app.
- **A web view.** The first attempt embedded the desktop front end and hid its
  chrome. Something inside a shim still moves, sizes and scrolls like a website.
  This app draws its own everything.
