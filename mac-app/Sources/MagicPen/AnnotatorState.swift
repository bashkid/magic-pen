import AppKit

extension Notification.Name {
    static let annotatorStateChanged = Notification.Name("annotatorStateChanged")
    static let annotatorLiveChanged = Notification.Name("annotatorLiveChanged") // in-progress stroke / laser, high frequency
}

/// Central, shared drawing state - the Swift analogue of the closures and
/// module-level vars at the top of content.js (TOOLS, strokes, tool, etc).
/// Strokes are stored in GLOBAL SCREEN coordinates (AppKit's bottom-left
/// origin, spanning all displays) so the same array can be rendered into one
/// overlay window per screen without any per-page scroll offset to track.
final class AnnotatorState {
    static let shared = AnnotatorState()

    static let quickColors: [NSColor] = [
        NSColor(hex: "#00aeef"), NSColor(hex: "#ec008c"),
        NSColor(hex: "#000000"), NSColor(hex: "#ffffff")
    ]
    static let palette: [NSColor] = [
        "#000000", "#ffffff", "#e8352a", "#ff8a00", "#fff200",
        "#17a969", "#00aeef", "#007aff", "#ec008c", "#9930f2"
    ].map { NSColor(hex: $0) }

    var tools: [ToolID: ToolConfig] = [
        .pointer:     ToolConfig(color: .black, width: 1, alpha: 1),
        .pen:         ToolConfig(color: NSColor(hex: "#ec008c"), width: 3, alpha: 1),
        .highlighter: ToolConfig(color: NSColor(hex: "#fff200"), width: 18, alpha: 0.35),
        .eraser:      ToolConfig(color: .black, width: 24, alpha: 1),
        .line:        ToolConfig(color: .black, width: 3, alpha: 1),
        .rect:        ToolConfig(color: .black, width: 3, alpha: 1),
        .ellipse:     ToolConfig(color: .black, width: 3, alpha: 1),
        .text:        ToolConfig(color: .black, width: 5, alpha: 1),
        .laser:       ToolConfig(color: NSColor(hex: "#e8352a"), width: 8, alpha: 1)
    ]

    private(set) var currentTool: ToolID = .pen
    private(set) var lastPaintTool: ToolID = .pen
    private(set) var strokes: [Stroke] = []
    private(set) var undone: [Stroke] = []
    private(set) var annotationsVisible = true
    var recording = false
    var active = false

    // in-progress (not yet committed) state - broadcast on the high-frequency channel
    var currentStroke: Stroke?
    var laserPoints: [LaserPoint] = []

    private init() {}

    private func announce() {
        NotificationCenter.default.post(name: .annotatorStateChanged, object: nil)
    }
    func announceLive() {
        NotificationCenter.default.post(name: .annotatorLiveChanged, object: nil)
    }

    func selectTool(_ tool: ToolID) {
        currentTool = tool
        if tool != .pointer && tool != .eraser { lastPaintTool = tool }
        announce()
    }

    func setColor(_ color: NSColor) {
        guard lastPaintTool != .pointer else { return }
        tools[lastPaintTool]?.color = color
        announce()
    }
    func currentColor() -> NSColor { tools[lastPaintTool]?.color ?? .black }

    func setWidth(_ width: CGFloat, for tool: ToolID) {
        tools[tool]?.width = width
        announce()
    }
    func setAlpha(_ alpha: CGFloat, for tool: ToolID) {
        tools[tool]?.alpha = alpha
        announce()
    }

    func commit(_ stroke: Stroke) {
        strokes.append(stroke)
        undone.removeAll()
        announce()
    }

    func eraseNear(_ point: CGPoint) {
        let radius = tools[.eraser]?.width ?? 24
        let before = strokes.count
        strokes.removeAll { stroke in
            stroke.points.contains { hypot($0.x - point.x, $0.y - point.y) < radius }
        }
        if strokes.count != before { announce() }
    }

    func undo() {
        guard let last = strokes.popLast() else { return }
        undone.append(last)
        announce()
    }
    func redo() {
        guard let last = undone.popLast() else { return }
        strokes.append(last)
        announce()
    }
    func clearAll() {
        strokes.removeAll()
        undone.removeAll()
        announce()
    }

    func strokesSnapshot() -> [Stroke] { strokes }
    func replaceAll(with newStrokes: [Stroke]) {
        strokes = newStrokes
        undone.removeAll()
        announce()
    }

    func toggleAnnotationsVisible() {
        annotationsVisible.toggle()
        announce()
    }
}

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s.removeAll { $0 == "#" }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
