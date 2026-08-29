import AppKit

final class ToolbarPanel: NSPanel {
    init() {
        // Width: exactly the 40pt cell width, no outer margin - the
        // extension's cells/colour row/swatches all run flush to the strip's
        // edges with zero side padding, only the strip's own border shows.
        // Height must fit the content precisely: logo (44) + 12 cells at
        // 34pt with no gaps (408, hairlines instead) + colour quad (22) +
        // colour well (30) + margins between them (~20) = ~518pt. A shorter
        // panel silently clips the colour row and well outside the window.
        super.init(contentRect: NSRect(x: 0, y: 0, width: 40, height: 520),
                    styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
                    backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // The toolbar strip is a fixed white panel (matching the Chrome
        // extension's design, which never adapts to page/OS dark mode
        // either). Without pinning the appearance, semantic colors like
        // NSColor.labelColor - which SF Symbol icons tint with by default -
        // flip to near-white under system Dark Mode, making them invisible
        // against our still-white background.
        appearance = NSAppearance(named: .aqua)
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        contentView = ToolbarView(frame: NSRect(x: 0, y: 0, width: 40, height: 520))
    }
}
