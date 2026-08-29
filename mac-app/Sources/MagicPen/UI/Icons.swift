import AppKit

enum Icons {
    static let logo = load("logo")
    static let arrow = load("arrow")
    static let eye = load("eye")

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Simple SF Symbol-backed glyphs for tools that don't have a bundled
    /// bitmap - keeps the toolbar legible without shipping a full icon set.
    /// Regular weight at default config renders faint/thin against the white
    /// panel (no tint = a washed-out default gray) - medium weight plus an
    /// explicit dark tint in CellButton is what makes these pop the way the
    /// extension's `.cell { color: #17171a }` glyphs do.
    static func symbol(_ name: String, fallbackText: String = "") -> NSImage? {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: fallbackText)
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        return base?.withSymbolConfiguration(config)
    }
}
