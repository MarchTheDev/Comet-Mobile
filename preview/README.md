# Design preview

`index.html` is a browser reproduction of the app's interface: the same
palettes, type scale, dock, orb and screens, written in one self-contained file
with no external assets. It is for looking at the design without a device.

It is not the app, and it does not try to be. The touch, the sheets springing
from the bottom edge, the drifting aurora and the readers are SwiftUI only.

Open it directly, or serve it:

```sh
python3 -m http.server 8080 --directory preview
```

Then open <http://localhost:8080>.

Pick a palette from the row at the top, tap the dock to move between Today,
Files, Search and Studio, tap a note to open it, and tap the orb for Calendar,
Feeds, Passwords, Tools, Sync and Settings.
