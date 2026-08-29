# Magic Pen (Mac)

A native macOS menu-bar app: the same idea as the Chrome extension, but for
the whole screen instead of one browser tab. Draw, highlight, laser-point,
screenshot and screen-record anywhere on your Mac.

## Run it

```
./build_app.sh
open MagicPen.app
```

The app has no Dock icon (`LSUIElement`) - look for the pen logo in the menu
bar. **Click** the menu bar icon to show/hide the annotation overlay and
toolbar. **Right-click** it for a menu (Toggle / Quit).

## Interface

The toolbar panel floats above everything, on every Space. Drag its logo to
move it, click it (without dragging) to collapse the cell strip - same as the
Chrome extension. Cells, top to bottom: Pointer (click-through), Eye
(show/hide all annotations), Highlighter, Shapes (line/rect/ellipse/text/
laser), Eraser, Pen, Size, Undo (⌘Z, redo ⇧⌘Z), Clear, Board (record/save/
restore), Camera (screenshot), Copy.

Clicking a cell with more options opens a native popover next to it - macOS
repositions those automatically if they'd run off-screen, so there's no
manual "flip to the left edge" logic to maintain here (that was a real bug we
had to fix by hand in the Chrome extension's flyouts).

The current-colour swatch is a native `NSColorWell`, so you get the system
colour picker for free instead of a hand-built palette.

## Screenshots & recording

- **Screenshot** shells out to `/usr/sbin/screencapture` (region drag, full
  screen, or straight to clipboard) - it draws the native crosshair selector
  and, since annotation strokes live in real on-screen windows rather than an
  invisible canvas, captures them automatically. No manual compositing step.
- **Recording** uses ScreenCaptureKit + AVAssetWriter, saved as `.mov` to
  `~/Movies/MagicPen/`. **First use will prompt for Screen Recording
  permission** in System Settings → Privacy & Security → Screen Recording -
  this is a one-time macOS system prompt, not something the app controls.
  Grant it, then click Record again.
- Screenshots save to `~/Pictures/MagicPen/`.

## What's different from the Chrome extension

There's no "page" to key annotations to system-wide, so Save/Restore (in the
Board popover) is one flat session file at
`~/Library/Application Support/MagicPen/session.json`, not per-URL.

No global keyboard shortcut to toggle the overlay from outside the app yet -
toggling is via the menu-bar icon. Adding a system-wide hotkey is possible
but needs the Accessibility permission and a hotkey-registration library or
Carbon `RegisterEventHotKey`; left out of this first pass to keep the
permission ask minimal.

## Project layout

| File | Role |
|---|---|
| `Package.swift` | SPM manifest (macOS 14+, AppKit + ScreenCaptureKit) |
| `Sources/MagicPen/main.swift` | App entry point, ⌘Z/⇧⌘Z monitor |
| `AppController.swift` | Menu-bar item, toggles the overlay + toolbar |
| `AnnotatorState.swift` | Shared drawing state (tools, strokes, undo/redo) |
| `UI/OverlayManager.swift` | One borderless full-screen window per display |
| `UI/CanvasView.swift` | Per-screen drawing surface, mouse handling |
| `UI/ToolbarView.swift` / `ToolbarPanel.swift` | The floating cell toolbar |
| `UI/Popovers.swift`, `CellButton.swift` | Flyout panels and cell buttons |
| `Capture/ScreenshotManager.swift` | `screencapture` wrapper |
| `Capture/RecordingManager.swift` | ScreenCaptureKit recorder |
| `SessionStore.swift` | Save/restore all strokes as JSON |
| `build_app.sh` | Packages a signed `.app` bundle from the SPM build |
