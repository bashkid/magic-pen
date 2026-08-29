# Magic Pen

A Manifest V3 Chrome extension: draw, highlight, laser-point, screenshot and
screen-record on any page. Everything saves to your local disk.

## Load it

1. `chrome://extensions` -> enable **Developer mode**
2. **Load unpacked** -> select this folder
3. Click the extension icon on any page to show/hide the overlay (`Esc` hides)

## Interface

A detached round nib logo above a white vertical strip, matching the reference.
Drag the logo to move the toolbar; click it to collapse the strip.

| # | Cell | Click the cell | Click the corner triangle |
|---|---|---|---|
| 1 | Arrow | Pointer — page stays clickable | – |
| 2 | Eye | Show / hide all annotations on the page | – |
| 3 | Highlighter | Select highlighter | Colour, weight, opacity |
| 4 | Circle + slash | Shapes panel | Line, Rectangle, Ellipse, Text, Laser |
| 5 | Eraser | Select eraser | – |
| 6 | Pen (colour dot) | Select pen | Colour, weight, opacity |
| 7 | Solid dot | Size panel | Weight + opacity for the active tool |
| 8 | Undo arrow | Undo | Redo |
| 9 | Bin | Clear all | – |
| 10 | Monitor (colour dot) | Board panel | Screen shade, record, save, restore |
| 11 | Camera | Screenshot — drag a region | Region / full page / copy |
| 12 | Clipboard | Copy screenshot to clipboard | – |

The logo, arrow (pointer) and eye icons are bundled images in `src/icons/`
(`logo.png`, `arrow.webp`, `eye.png`), exposed to the content script via
`web_accessible_resources` in `manifest.json`.

Below the cells: a 2x2 block of quick colours (cyan, magenta, black, white) and
a large block showing the current colour — click it for the full palette.

A corner triangle always means "this cell has a submenu", exactly as in the
reference. The colour dots on Pen and Monitor show the live colour and turn red
while recording.

**Keyboard** — `Esc` closes a flyout, then hides the overlay.
`Cmd/Ctrl+Z` undo, `Cmd/Ctrl+Shift+Z` redo.

## Screenshot

From the More popover, click the camera, then either **drag a region** or
**click once** for the whole visible page. Annotations are included and the
toolbar hides itself from the shot. Saved as PNG, or copied straight to the
clipboard with the clipboard button.

## Recording

Click the record dot, pick a screen/window/tab, and click it again to stop.
Saved as `.webm` via a Save-As dialog.

### If recording fails

The status pill under the toolbar shows the real error. To see more:

- **Service worker log**: `chrome://extensions` -> this extension -> "service
  worker" link -> Console
- **Recorder log**: on that same page the offscreen document appears while
  recording; or run `chrome.runtime.getContexts({contextTypes:['OFFSCREEN_DOCUMENT']})`
  in the service worker console

Known constraints: `chrome://` and Chrome Web Store pages block content scripts
entirely, so the overlay will not appear there.

## Files

| File | Role |
|---|---|
| `manifest.json` | Permissions and entry points |
| `src/content.js` | Overlay: canvases, tools, toolbar, screenshot |
| `src/content.css` | Positions the canvases and toolbar host |
| `src/background.js` | Service worker: toggling, picker, downloads |
| `src/offscreen.html/.js` | Invisible page that runs `MediaRecorder` |

## Things worth understanding

**Why two canvases.** `strokeCanvas` holds committed strokes and redraws only on
change. `liveCanvas` clears every frame for the in-progress stroke, laser trail
and capture selection. One canvas would mean redrawing every old stroke 60x/sec.

**Why page coordinates.** Points are stored as `clientX + scrollX` and drawn with
a `-scrollX` translate, so annotations stay anchored to content while scrolling.

**Why an offscreen document.** MV3 service workers have no DOM and cannot run
`MediaRecorder`. `chrome.offscreen` creates an invisible real page for it. The
worker picks the screen and owns `chrome.downloads`; the offscreen page records.

**Why the ping handshake.** `createDocument()` resolves before the offscreen
page's script has registered its `onMessage` listener. Sending the stream id
immediately means it lands nowhere — the classic silent MV3 recording failure.
`ensureOffscreenReady()` pings until the page answers before sending work.

**Why shadow DOM.** The toolbar runs on arbitrary sites, so a shadow root keeps
the page's CSS out and ours in.

**Why device-pixel scaling on screenshots.** `captureVisibleTab` returns device
pixels; selection coords are CSS pixels. Cropping needs
`scale = img.width / window.innerWidth`.

## Ideas to build next

- Text and arrow tools
- Persist strokes per-URL in `chrome.storage.local`, restore on revisit
- Full-page (scrolling) screenshot by stitching several captures
- Record audio too: add an `audio` constraint in `offscreen.js`
