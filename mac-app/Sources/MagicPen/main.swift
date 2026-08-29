import AppKit

/// Keyboard shortcuts, adapted from a reference screen-drawing app's
/// shortcut list (ScreenBrush) to the tools Magic Pen actually has - no
/// invented features for things we don't build (layers, badges, ghost
/// mode, etc). ⌘1-9 extends ScreenBrush's ⌘1-4 tool-switching pattern to
/// cover all nine of our tools, in the same order they appear in the
/// toolbar (ToolID.allCases: pointer, pen, highlighter, eraser, line,
/// rect, ellipse, text, laser).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppController.shared.start()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            let key = event.charactersIgnoringModifiers?.lowercased()

            // ⌘Q works regardless of overlay state - a second, always-
            // reachable way to quit alongside the menu bar's right-click
            // menu, for exactly the case where the overlay is eating
            // clicks meant for the menu bar.
            if key == "q" { AppController.shared.quit(); return nil }

            guard AnnotatorState.shared.active else { return event }

            if let key, let digit = Int(key), (1...9).contains(digit) {
                AnnotatorState.shared.selectTool(ToolID.allCases[digit - 1])
                return nil
            }

            switch key {
            case "z":
                if event.modifierFlags.contains(.shift) { AnnotatorState.shared.redo() } else { AnnotatorState.shared.undo() }
                return nil
            case "c":
                ScreenshotManager.shared.copyFullScreenToClipboard()
                return nil
            case "s":
                ScreenshotManager.shared.captureFullScreen()
                return nil
            case "t":
                AppController.shared.toggleToolbarCollapse()
                return nil
            default:
                break
            }
            // ⌘⌫ (Delete/Backspace) - Clear Screen. Backspace has no
            // printable character, so it's matched on keyCode (51) instead
            // of charactersIgnoringModifiers.
            if event.keyCode == 51 {
                AnnotatorState.shared.clearAll()
                return nil
            }
            return event
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
