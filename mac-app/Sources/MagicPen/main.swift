import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppController.shared.start()
        // ⌘Z / ⇧⌘Z work while any of our own windows (toolbar, overlay) are key.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard AnnotatorState.shared.active, event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "z" else { return event }
            if event.modifierFlags.contains(.shift) { AnnotatorState.shared.redo() } else { AnnotatorState.shared.undo() }
            return nil
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
