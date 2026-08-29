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
    static func symbol(_ name: String, fallbackText: String = "") -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: fallbackText)
    }
}
