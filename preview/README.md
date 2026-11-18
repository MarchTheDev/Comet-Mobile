# Design preview

`index.html` is a browser reproduction of the app's interface: the same
palettes, type scale, floating bar and screens, written in one self-contained
file. Its only image is `comet-mark.png`, the app's own icon.

It is not the app, and it does not try to be. The touch, the sheets springing
from the bottom edge, the haptics and the readers are SwiftUI only.

Open it directly, or serve it:

```sh
python3 -m http.server 8080 --directory preview
```

Then open <http://localhost:8080>.

Pick a palette from the row at the top, use the bar to move between Today,
Library, Calendar and More, tap the `+` in the middle of it for quick capture,
and open a note or a board to see the document screens. Everything that is not
a tab — feeds, passwords, tools, sync, settings — is a row on More.
