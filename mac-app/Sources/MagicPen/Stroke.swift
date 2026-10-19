import AppKit

enum ToolID: String, CaseIterable {
    case pointer, pen, highlighter, eraser, line, rect, ellipse, text, laser
}

enum ShapeKind {
    case free, line, rect, ellipse, text
}

struct ToolConfig {
    var color: NSColor
    var width: CGFloat
    var alpha: CGFloat
}

/// One committed (or in-progress) mark on the canvas. Points are stored in
/// screen coordinates (the overlay window already spans the full screen, so
/// there is no scroll/page offset to track, unlike the browser version).
struct Stroke {
    var shape: ShapeKind
    var color: NSColor
    var width: CGFloat
    var alpha: CGFloat
    var points: [CGPoint] = []
    var pressures: [CGFloat] = []
    var text: String = ""
    var fontSize: CGFloat = 20
}

struct LaserPoint {
    var point: CGPoint
    var time: TimeInterval
}
