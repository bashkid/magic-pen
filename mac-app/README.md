# Magic Pen for macOS

A native menu-bar annotation app for drawing, highlighting, presenting, screenshots, and screen recording over your Mac workspace.

<p align="center"><img src="../docs/images/magic-pen-logo.png" alt="Magic Pen app logo" width="160"></p>

See the [main README](../README.md) for the complete feature comparison, Chrome installation, and project overview.

## Install a released app

Download the **Mac ZIP** from the [latest GitHub release](https://github.com/bashkid/magic-pen/releases/latest), extract it, and move `MagicPen.app` to Applications. Version 0.2.3 includes Apple silicon and Intel executables in one app bundle and requires macOS 14 or later.

The app is locally signed and is not notarized. If macOS blocks its first launch, use the system approval option in **System Settings → Privacy & Security**. Screen capture may require a separate permission grant.

## Requirements

- macOS **14 or later**.
- Xcode or a Swift development toolchain compatible with the package’s Swift tools **5.9** manifest.
- The macOS build and signing tools used by `swift build` and `codesign`.
- Optional: FFmpeg for WebM recording export.

## Build and launch

From the repository root:

```bash
./mac-app/build_app.sh
open mac-app/MagicPen.app
```

Or from this directory:

```bash
./build_app.sh
open MagicPen.app
```

The script builds a release executable, adds the icons and SwiftPM resource bundle, and signs the application locally. The result is `mac-app/MagicPen.app`. Use the packaged app for normal use.

Magic Pen has **no Dock icon**. Find its pen icon in the menu bar:

- **Left-click:** show or hide the annotation overlay and toolbar.
- **Right-click:** open Toggle Overlay and Quit Magic Pen.
- Quit an older running instance before opening a rebuilt copy.

## Features and controls

| Control | Behavior |
|---|---|
| Pointer | Let clicks reach the application beneath the overlay |
| Eye | Show or hide annotations without deleting them |
| Pen | Smooth freehand strokes, rounded caps, and supported-device pressure |
| Highlighter | Translucent freehand strokes |
| Shapes | Line, rectangle, ellipse, text, and laser tools |
| Eraser | Remove a touched stroke |
| Size | Change the current paint tool’s weight and opacity |
| Undo | Undo the last committed stroke; redo is available by keyboard |
| Clear | Remove annotations and reset history |
| Board | Start/stop recording or save/restore an editable session |
| Timer | Set or stop a movable on-screen countdown |
| Camera | Capture a region, full screen, or clipboard image |
| Clipboard | Copy a full-screen screenshot |

Drag the round logo to move the toolbar. Click it to collapse or expand the controls. Native popovers provide additional actions beside the selected control.

Use the quick swatches, palette, or system color picker to change color. Pen and highlighter settings expose weight **1–40** and opacity **5–100%**.

### Drawing behavior

The app creates a transparent overlay for each connected display and stores stroke points in global screen coordinates. The drawable area uses each screen’s usable workspace, leaving the menu bar and Dock accessible.

Freehand strokes are smoothed and keep per-point pressure when macOS reports it. A normal mouse keeps steady width. Erasing removes whole strokes rather than splitting or modifying their pixels.

Select Text and click the overlay to open a native text field. The text is committed when editing ends. The laser tool produces a fading trail while dragging.

### Countdown timer

Click Timer, enter the duration in minutes, and select **Start Timer**. The UI accepts **0.1–240 minutes** and starts at five minutes by default. Drag the visible countdown pill to move it.

The timer is independent of recording. It beeps and briefly displays **Done** when it reaches zero. Open the Timer panel again to stop it early.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+1` | Pointer |
| `Cmd+2` | Pen |
| `Cmd+3` | Highlighter |
| `Cmd+4` | Eraser |
| `Cmd+5` | Line |
| `Cmd+6` | Rectangle |
| `Cmd+7` | Ellipse |
| `Cmd+8` | Text |
| `Cmd+9` | Laser |
| `Cmd+Z` / `Cmd+Shift+Z` | Undo / redo |
| `Cmd+Delete` | Clear all annotations and history |
| `Cmd+C` | Copy a full-screen screenshot |
| `Cmd+S` | Take a full-screen screenshot |
| `Cmd+T` | Collapse or expand the toolbar |
| `Cmd+Q` | Quit Magic Pen |

The app must receive the keyboard event; these are not global shortcuts that override another application. Drawing shortcuts require an active overlay. `Cmd+Q` is handled whenever Magic Pen receives it.

## Save and restore drawings

Open **Board → Save session** to write an editable JSON session to:

```text
~/Library/Application Support/MagicPen/session.json
```

Open **Board → Restore session** to replace the current drawings with that saved session. Save explicitly before quitting if you want to keep new drawings.

The session includes shapes, text, colors, widths, opacity, and point pressure. Older session files without pressure data remain readable. Undo/redo history is not stored.

## Screenshots

Open Camera to choose **Drag a region**, **Whole screen**, or **Copy to clipboard**. The app uses macOS’s `screencapture` utility and hides its main toolbar while capturing; visible annotation overlays are included.

PNG files are written to:

```text
~/Pictures/MagicPen/
```

Clipboard captures go to the system clipboard. `Cmd+S` takes a screenshot; editable drawing sessions are saved separately through Board.

## Screen recording

1. Open **Board → Record screen**.
2. Grant the requested macOS screen-capture permission.
3. Record your demonstration on the main display.
4. Open Board again and choose **Stop recording**.

The recorder uses ScreenCaptureKit and AVAssetWriter. It targets **30 fps**, includes the cursor and annotation overlays, and excludes Magic Pen’s toolbar and auxiliary app windows. Recording captures the main display and currently has no audio.

Outputs are placed in:

```text
~/Movies/MagicPen/
```

The app first captures a temporary MOV. After stopping, it converts the recording to VP9 WebM if FFmpeg is available. It checks these executable paths:

```text
/opt/homebrew/bin/ffmpeg
/usr/local/bin/ffmpeg
/usr/bin/ffmpeg
```

If FFmpeg is absent or conversion fails, the app keeps a visible MOV file instead. Finder reveals the resulting recording after export finishes.

## Permissions and troubleshooting

| Issue | Action |
|---|---|
| No application window appears | Click Magic Pen’s menu-bar icon; the app does not use a normal main window or Dock icon. |
| Clicks cannot reach the app underneath | Select Pointer to enable click-through, or hide the overlay with the menu-bar icon. |
| Screen capture fails | Check Magic Pen’s Screen Recording access in System Settings → Privacy & Security. Relaunch if macOS requests it. |
| Pressure does not change width | Confirm the input device and driver report pressure to macOS. Ordinary mouse input uses constant width. |
| Recording saves as MOV | Check the supported FFmpeg locations or the app logs for a conversion error. |
| Startup reports a missing resource bundle | Rebuild with `build_app.sh`, which places the SwiftPM resource bundle in `MagicPen.app/Contents/Resources/`. |
| Changes do not appear | Quit the old instance, rebuild the app bundle, and launch that rebuilt bundle. |

Drawings and media files are stored locally. The app does not require an account or application server.

## Source layout

Paths below are relative to `Sources/MagicPen/` unless noted.

| File | Responsibility |
|---|---|
| `main.swift` | App startup and local keyboard shortcuts |
| `AppController.swift` | Menu-bar item, overlay visibility, toolbar lifecycle |
| `AnnotatorState.swift` | Tools, committed/live strokes, visibility, and history |
| `Stroke.swift` | Shapes, tool configuration, stroke points, and pressure data |
| `SessionStore.swift` | Backward-compatible editable JSON sessions |
| `UI/OverlayManager.swift` | Transparent overlay windows for connected displays |
| `UI/CanvasView.swift` | Stroke rendering, pointer/pressure input, text, and laser |
| `UI/ToolbarView.swift`, `ToolbarPanel.swift` | Floating toolbar and color controls |
| `UI/Popovers.swift`, `CellButton.swift` | Tool settings and action panels |
| `UI/CountdownTimerManager.swift` | Countdown state and movable display |
| `Capture/ScreenshotManager.swift` | Native screenshot commands |
| `Capture/RecordingManager.swift` | Capture filtering, video writing, and WebM conversion |
| `mac-app/Package.swift` | Package configuration at the package root |
| `mac-app/build_app.sh` | Release packaging at the package root |

Run `swift build` from `mac-app/` for a development build. Run `./build_app.sh` to recreate the release app bundle. Generated `.build/` files and `MagicPen.app/` are ignored by Git.

For a universal release build, pass both architectures to the packaging script:

```bash
./build_app.sh --arch arm64 --arch x86_64
```
