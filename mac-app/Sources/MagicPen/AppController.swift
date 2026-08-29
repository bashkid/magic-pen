import AppKit

/// Menu-bar coordinator: owns the status item and the toolbar panel, and
/// toggles the whole overlay system on/off. Equivalent to background.js's
/// action.onClicked handler + ANNOTATOR_TOGGLE message in the extension.
final class AppController {
    static let shared = AppController()
    private(set) var toolbarPanel: ToolbarPanel?
    private var statusItem: NSStatusItem?

    private init() {}

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let logo = Icons.logo {
                // Same white circular backdrop as the toolbar's logo -
                // matches the extension's `.logo img { background:#fff }`
                // instead of a bare glyph floating in the menu bar.
                let resized = NSImage(size: NSSize(width: 18, height: 18))
                resized.lockFocus()
                NSColor.white.setFill()
                NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 18, height: 18)).fill()
                logo.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
                resized.unlockFocus()
                button.image = resized
            } else {
                button.title = "🖊"
            }
            button.action = #selector(statusItemClicked)
            button.target = self
            // A status item button only sends its action on left-click by
            // default - right-clicks were silently doing nothing at all,
            // which is why the Quit menu never appeared.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Overlay", action: #selector(toggle), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Magic Pen", action: #selector(quit), keyEquivalent: "q")
            .target = self
        item.menu = nil // left-click toggles directly; right-click shows the menu
        self.statusItem = item
        self.rightClickMenu = menu
    }

    private var rightClickMenu: NSMenu?

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { toggle(); return }
        if event.type == .rightMouseUp {
            statusItem?.menu = rightClickMenu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            toggle()
        }
    }

    @objc func toggle() {
        let turningOn = !AnnotatorState.shared.active
        OverlayManager.shared.setActive(turningOn)
        if turningOn {
            let panel = toolbarPanel ?? ToolbarPanel()
            toolbarPanel = panel
            if let screen = NSScreen.main {
                // setFrameOrigin positions the window's BOTTOM-left corner
                // (AppKit's coordinate origin is bottom-left of the screen),
                // not the top-left - subtracting the panel's own height from
                // the screen's top edge is what actually pins its top near
                // the top of the screen. Getting this backwards is what put
                // the whole panel mostly off-screen above the display.
                let topMargin: CGFloat = 40
                let leftMargin: CGFloat = 40
                let x = screen.frame.minX + leftMargin
                let y = screen.frame.maxY - topMargin - panel.frame.height
                panel.setFrameOrigin(CGPoint(x: x, y: y))
            }
            panel.orderFrontRegardless()
        } else {
            toolbarPanel?.orderOut(nil)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
