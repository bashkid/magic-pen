import AppKit

/// Owns one borderless, transparent, full-screen window per display. Mirrors
/// content.js's strokeCanvas/liveCanvas pair conceptually, except here a
/// single CanvasView per screen redraws both committed and live strokes -
/// AppKit's needsDisplay coalescing makes the two-canvas split unnecessary.
final class OverlayManager {
    static let shared = OverlayManager()
    private var windows: [NSWindow] = []
    private let state = AnnotatorState.shared

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild),
                                                name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(syncClickThrough),
                                                name: .annotatorStateChanged, object: nil)
    }

    func setActive(_ on: Bool) {
        state.active = on
        if on {
            buildWindows()
        } else {
            windows.forEach { $0.orderOut(nil) }
            windows.removeAll()
        }
        NotificationCenter.default.post(name: .annotatorStateChanged, object: nil)
    }

    @objc private func rebuild() {
        guard state.active else { return }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        buildWindows()
    }

    private func buildWindows() {
        for screen in NSScreen.screens {
            // visibleFrame (not frame) - covering the full physical screen at
            // .statusBar level meant this window sat over the real menu bar
            // strip too, and while a drawing tool was active (non-click-
            // through) it swallowed clicks meant for the actual system menu
            // bar before they got there, including clicks on our own status
            // item - there was no way to reach Quit. Excluding the menu
            // bar/Dock region entirely fixes that; drawing simply can't
            // reach those strips, which is the right tradeoff.
            let rect = screen.visibleFrame
            let window = NSWindow(contentRect: rect, styleMask: [.borderless],
                                   backing: .buffered, defer: false, screen: screen)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .statusBar // above normal app windows, including full-screen-menubar apps
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = (state.currentTool == .pointer)
            let canvas = CanvasView(frame: NSRect(origin: .zero, size: rect.size))
            canvas.autoresizingMask = [.width, .height]
            window.contentView = canvas
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    @objc private func syncClickThrough() {
        let clickThrough = !state.active || state.currentTool == .pointer
        windows.forEach { $0.ignoresMouseEvents = clickThrough }
    }
}
