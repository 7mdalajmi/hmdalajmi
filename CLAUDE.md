# Project notes for Claude

## Typography: Thmanyah Sans is the default font

Use **Thmanyah Sans (خط ثمانية)** for all Arabic and Latin text in this owner's work:
image designs (posters, social posts, covers, mockups), app UIs, and pages.
Do not design or propose new typefaces unless the owner asks for it explicitly.

### Files and names

Five static weights, OpenType (CFF) files in `SnapStitch/SnapStitch/Fonts/`:

| Weight | CSS `font-weight` | File | PostScript name |
|---|---|---|---|
| Light | 300 | `ThmanyahSans-Light.otf` | `thmanyahsans-Light` |
| Regular | 400 | `ThmanyahSans-Regular.otf` | `thmanyahsans-Regular` |
| Medium | 500 | `ThmanyahSans-Medium.otf` | `thmanyahsans-Medium` |
| Bold | 700 | `ThmanyahSans-Bold.otf` | `thmanyahsans-Bold` |
| Black | 900 | `ThmanyahSans-Black.otf` | `thmanyahsans-Black` |

If the folder is missing in a fresh checkout, ask the owner for the font package
instead of substituting another typeface.

### Image designs

- Lay the design out in HTML and render it to PNG with Playwright (`deviceScaleFactor: 2`).
- Load the font with `@font-face` pointing at the local `.otf` files (one rule per weight, same family name),
  and wait for `document.fonts.ready` before taking the screenshot.
- Arabic body text: `line-height` 1.6 or more. The font's built-in line height (1.25) is too tight for Arabic with diacritics.
- Add `word-spacing: 0.2em` to Arabic text. Without it, words after ر / ز / و can look joined (for example «نور كتاب»).
  Set it on the text elements themselves (for example `#design * { word-spacing: .2em }`): an `em` value set on a parent
  is computed from the parent's font size and inherited as a fixed length. Large headlines need much less (about `0.05em`).
- Headlines can use the extended (swash) letterforms: `font-feature-settings: 'ss01'`.
- Weights that read well: Regular/Medium for text, Bold/Black for headlines.

### Apps (SnapStitch, iOS)

- Fonts are bundled and registered under `UIAppFonts` in `SnapStitch/SnapStitch/Info.plist`.
- In SwiftUI use `Theme.text(size, weight:, relativeTo:)` or the presets (`Theme.body`, `Theme.headline`, `Theme.title2`, ...).
  They map `Font.Weight` to the right file and scale with Dynamic Type.
- In UIKit use `AppFont.uiFont(...)`. Navigation bar titles are set in `SnapStitchApp.init()`.
- `Theme.mono` stays system monospaced on purpose, for numeric metadata such as frame counters.

### Published web pages

Published pages cannot load fonts from outside hosts. Embed the weights you need as base64 `@font-face` sources
(each weight adds roughly 320 KB, so embed only the weights the page uses).
The owner confirmed on 2026-11-05 that the font's license allows using and publishing the files.
