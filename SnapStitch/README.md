# SnapStitch

A free, no-watermark iOS utility that combines multiple screenshots into one long image — vertically (chat threads, articles) or horizontally (side-by-side comparisons) — with built-in crop and redaction tools (blur / pixelate / solid) for hiding sensitive info before you share.

Inspired by the "long screenshot merger" category of apps, but built from scratch as an original SwiftUI project and kept **fully free**: unlimited images, no watermark, no ads, no paywall.

## Requirements

- macOS with Xcode 15 or later
- iOS 16.0+ deployment target (uses `PhotosPicker`, `PhotosUI`)

## Opening the project

1. Pull this branch on a Mac.
2. Open `SnapStitch/SnapStitch.xcodeproj` in Xcode.
3. Select a simulator (or your device) and hit **Run** (⌘R).

No external dependencies — pure SwiftUI + UIKit/CoreImage, no SPM/CocoaPods packages required.

## Project structure

```
SnapStitch/
├── SnapStitchApp.swift        # @main entry point
├── ContentView.swift          # Root navigation flow
├── Models/
│   └── StitchModels.swift     # StitchImage, RedactionBox, enums
├── ViewModels/
│   └── StitchViewModel.swift  # App state, import/export logic
├── Services/
│   ├── ImageStitcher.swift    # Core Graphics/CoreImage compositing
│   └── PDFExporter.swift      # Single-page PDF export
└── Views/
    ├── ImportView.swift       # PhotosPicker entry screen
    ├── ArrangeView.swift      # Reorderable list + edit sheet
    ├── CropEditorView.swift   # Per-image top/bottom crop
    ├── RedactEditorView.swift # Draw-to-redact tool
    ├── PreviewExportView.swift# Live preview, layout options, export
    └── ShareSheet.swift       # UIActivityViewController wrapper
```

## How it works

1. **Import** — pick any number of screenshots from the photo library.
2. **Arrange** — drag to reorder, tap a thumbnail to crop or redact it.
3. **Crop** — trim the top/bottom of a screenshot with sliders and a live preview.
4. **Redact** — drag a rectangle over sensitive content, choose blur / pixelate / solid — all processed on-device.
5. **Preview & Export** — choose vertical/horizontal stitching, spacing, background color, and export as PNG, JPG, or PDF via the system share sheet.

## 10 ideas to extend the app

1. **Share Extension** — add an Action Extension target so users can start a stitch directly from the Photos app or Safari without opening SnapStitch first.
2. **Siri Shortcuts / App Intents** — expose an `AppIntent` (e.g. "Stitch My Screenshots") so the whole import → stitch → export flow can be automated or triggered by voice.
3. **Auto-detect status bar duplicates** — use Vision (`VNRecognizeTextRequest`) to detect and auto-crop the repeating status bar/notch across screenshots instead of manual slider cropping.
4. **Smart redaction suggestions** — run on-device text recognition to flag likely phone numbers, emails, and addresses and pre-place redaction boxes for the user to confirm.
5. **SwiftData persistence** — save in-progress stitch sessions so a user can close the app mid-edit and resume later instead of losing their arrangement.
6. **Drag-and-drop reordering with live thumbnails in the grid** — replace the List-based reorder with a `LazyVGrid` + `.draggable`/`.dropDestination` for a more visual, Photos-app-like arrange screen.
7. **iPad & multi-window support** — add a two-column `NavigationSplitView` layout (thumbnail rail + big canvas) to take advantage of iPad screen space.
8. **Undo/redo stack** — wrap crop and redaction edits in `UndoManager` so users can step back through changes per image.
9. **Batch export presets** — let users save named export presets (e.g. "WhatsApp square", "Twitter thread") bundling direction/spacing/background/format so repeat workflows are one tap.
10. **Watch for clipboard screenshots** — detect when new screenshots are added to the photo library while the app is open (via `PHPhotoLibraryChangeObserver`) and offer to append them to the current stitch automatically.
