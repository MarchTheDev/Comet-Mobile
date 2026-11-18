# Design

The app follows the desktop app's visual language. The two are laid out for
different hands — a bottom bar instead of a sidebar, one column instead of two —
but they are painted with the same values, set in the same type, and built from
the same small vocabulary of panels.

## The mapping

The desktop app's stylesheet defines twelve variables per theme:

```
--canvas  --panel  --panel-soft  --panel-raised
--border  --border-strong
--text    --text-secondary  --text-muted
--accent  --accent-ink  --accent-soft
```

`Palette` in `CometApp/Design/Palette.swift` carries those twelve, with those
names, for the same fourteen themes: the default light and dark Comet palettes,
Emerald, Rubellite, Navy, 0807 Light, 0807 Dark, Sakura, Matcha, Ember, Gothic,
Frog, Nightjar and Onyx — plus `System`, which chooses between the two Comet
palettes with the device appearance. The hex values are copied from
`web/src/index.css` and `:root[data-palette="…"]`, so switching theme on one
device and opening the workspace on the other is not a change of colour scheme.

`CometTheme` resolves a palette into everything a view paints with and travels
down through the environment as `\.comet`. No view names a colour.

| Desktop | App |
| --- | --- |
| `--canvas` | `theme.canvas` |
| `--panel` | `theme.surface` |
| `--panel-soft` | `theme.soft` |
| `--panel-raised` | `theme.raised` |
| `--border` | `theme.hairline`, `theme.border` |
| `--border-strong` | `theme.strongLine` |
| `--text` | `theme.ink` |
| `--text-secondary` | `theme.secondary` |
| `--text-muted` | `theme.tertiary` |
| `--accent` | `theme.accent` |
| `--accent-ink` | `theme.accentInk` |
| `--accent-soft` | `theme.accentSoft` |

## Type

The desktop sets everything in Manrope. The app carries five static cuts of the
font — 400, 500, 600, 700, 800 — under `CometApp/Resources/Fonts/`, with the SIL
Open Font License beside them, and registers them in `UIAppFonts`. `CometType`
maps a weight to the matching cut and applies the scale the user sets in
Settings:

- **Display** — page titles, 800 weight, tight tracking, 22–30 pt.
- **Title** — panel headings, 600–700, 13–16 pt.
- **Label** — eyebrows and section labels, 700–800, 9.5–12 pt, uppercase with
  0.1em tracking.
- **Prose** — reading, 500, 14 pt with 1.9 line height.
- **Mono** — paths, counts, code.

If the font is ever missing from the bundle the type falls back to the system
face rather than failing to draw.

## Surfaces

Three shapes, and no others:

- **Panel** — `theme.surface`, 1 pt `--border`, 12 pt radius, a shadow of
  `0 4px 14px` at six percent. Everything is a panel: a card, a sheet row, a
  list, a toolbar.
- **Inset** — `theme.soft` with the same border, for fields, calendar cells and
  kanban columns.
- **Accent fill** — `theme.accent` with white ink, for the one primary action on
  a screen: the `+` in the bar, New item, Unlock, Save.

Corners run from 8 points (controls) through 14 (rows, fields) to 18 for tiles
and 26 for the cover card. `cometCard(radius:)` clamps at 22, so a screen written
against the older, squarer design still reads as the same app.

## Chrome

There is no navigation bar. The screen starts with its own content.

- **The bar at the bottom floats**: a 24-point rounded surface, one-pixel
  border, inset 12 points from the sides and 16 from the bottom edge, with the
  accent `+` as a 52-point rounded square in the middle. Today and Library sit
  on its left, Calendar and More on its right, and the selected item is
  `--accent-ink` with a heavier glyph.
- **There is no drawer.** The desktop's sidebar does not come along: its rows
  become the More screen — workspace, search, boards, feeds, vault, tools, sync,
  tags, settings — each an icon tile, a title and a line of detail, grouped into
  two bordered panels. Search and the boards are screens without a slot in the
  bar; the bar keeps Library lit while you are in either.
- **The mark is the app icon**: the comet, clipped to a squircle at the top of
  the cover card and of More, 34–40 points.
- **The header inside the scroll** is the desktop's document header: an
  eyebrow in `--text-muted` at 9.5 pt, a title in `--text` at 26–30 pt, a
  subtitle in `--text-secondary`, and small square buttons on the right.
- **The cover card** on Today is the desktop's `.cover-card`: a filled accent
  panel carrying the date, the greeting and the workspace, with light ink.
- **Sheets** are panels: the canvas colour, a 14 pt top radius, a grabber, a
  title at 20–22 pt and rows that are panels themselves.

## Motion and touch

Motion is small and quick: a 0.2 s ease for selection, 0.32 s for sheets, a
short stagger for lists. Presses scale to 0.97 rather than bouncing. Haptics
answer selection, presses, drops and errors, and one switch turns them off.

Every control is at least 34 points, the primary action is never in a corner,
and long-press never carries an action that is not also on a visible button.

## What was rejected

- **A top bar.** Even now that the app follows the desktop's design, the desktop
  header does not become an iOS navigation bar; the title still scrolls with the
  content.
- **The mountain cover photograph.** The desktop's cover card uses a picture.
  The app uses the palette's accent instead, so a theme change repaints the
  whole screen and no stock image ships in the bundle.
- **Glass and blur.** Beautiful on a marketing page; not what the desktop looks
  like. The app is flat panels and borders.
- **A web view.** The first attempt embedded the desktop front end and hid its
  chrome. Something inside a shim still moves, sizes and scrolls like a website.
  This app draws its own everything.
