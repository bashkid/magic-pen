import AppKit

/// One per screen. Renders the shared AnnotatorState.strokes (stored in
/// global screen coordinates) translated into this window's local space, and
/// owns pointer handling for whichever screen the mouse is actually on.
final class CanvasView: NSView {
    private let state = AnnotatorState.shared
    private var fadeTimer: Timer?
    private var activeTextField: NSTextField?
    private var textFieldOrigin: CGPoint = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        NotificationCenter.default.addObserver(self, selector: #selector(redrawNow),
                                                name: .annotatorStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(redrawNow),
                                                name: .annotatorLiveChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func redrawNow() { needsDisplay = true }

    // global screen point -> local view point (bottom-left origin throughout, no flip)
    private func local(_ p: CGPoint) -> CGPoint {
        guard let origin = window?.frame.origin else { return p }
        return CGPoint(x: p.x - origin.x, y: p.y - origin.y)
    }
    private func globalPoint(from event: NSEvent) -> CGPoint {
        guard let window else { return event.locationInWindow }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard state.annotationsVisible else { return }
        for stroke in state.strokes { drawStroke(stroke) }
        if let cur = state.currentStroke { drawStroke(cur) }
        drawLaser()
    }

    private func path(for stroke: Stroke) -> NSBezierPath {
        let pts = stroke.points.map(local)
        let path = NSBezierPath()
        path.lineWidth = stroke.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        guard let a = pts.first else { return path }
        switch stroke.shape {
        case .line:
            path.move(to: a); if let b = pts.last { path.line(to: b) }
        case .rect:
            guard let b = pts.last else { break }
            path.appendRect(NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                    width: abs(b.x - a.x), height: abs(b.y - a.y)))
        case .ellipse:
            guard let b = pts.last else { break }
            path.appendOval(in: NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                        width: abs(b.x - a.x), height: abs(b.y - a.y)))
        case .free:
            path.move(to: a)
            for p in pts.dropFirst() { path.line(to: p) }
            if pts.count == 1 { path.line(to: CGPoint(x: a.x + 0.1, y: a.y)) }
        case .text:
            break
        }
        return path
    }

    private func drawStroke(_ stroke: Stroke) {
        if stroke.shape == .text {
            guard let a = stroke.points.first else { return }
            let p = local(a)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: stroke.fontSize),
                .foregroundColor: stroke.color.withAlphaComponent(stroke.alpha)
            ]
            // AppKit draws text upward from the baseline-adjacent origin; we
            // stored the click point as the top-left, like the JS textBaseline='top'.
            (stroke.text as NSString).draw(at: CGPoint(x: p.x, y: p.y - stroke.fontSize),
                                            withAttributes: attrs)
            return
        }
        let path = path(for: stroke)
        stroke.color.withAlphaComponent(stroke.alpha).setStroke()
        path.stroke()
    }

    private func drawLaser() {
        guard state.laserPoints.count > 1 else { return }
        let cfg = state.tools[.laser]!
        let now = ProcessInfo.processInfo.systemUptime
        let fadeMs: TimeInterval = 0.7
        for i in 1..<state.laserPoints.count {
            let p0 = state.laserPoints[i - 1], p1 = state.laserPoints[i]
            let life = 1 - (now - p1.time) / fadeMs
            guard life > 0 else { continue }
            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineWidth = cfg.width * CGFloat(life)
            path.move(to: local(p0.point))
            path.line(to: local(p1.point))
            cfg.color.withAlphaComponent(CGFloat(life)).setStroke()
            path.stroke()
        }
    }

    // ---------------------------------------------------------------- input
    override func mouseDown(with event: NSEvent) {
        guard state.active, state.currentTool != .pointer else { return }
        let p = globalPoint(from: event)

        if state.currentTool == .text {
            beginTextEntry(at: p, in: event)
            return
        }
        if state.currentTool == .laser {
            state.laserPoints.append(LaserPoint(point: p, time: ProcessInfo.processInfo.systemUptime))
            startFadeTimerIfNeeded()
            return
        }
        if state.currentTool == .eraser {
            state.eraseNear(p)
            return
        }
        let cfg = state.tools[state.currentTool]!
        let shape: ShapeKind = [.line: ShapeKind.line, .rect: .rect, .ellipse: .ellipse][state.currentTool] ?? .free
        state.currentStroke = Stroke(shape: shape, color: cfg.color, width: cfg.width, alpha: cfg.alpha, points: [p])
        state.announceLive()
    }

    override func mouseDragged(with event: NSEvent) {
        guard state.active, state.currentTool != .pointer else { return }
        let p = globalPoint(from: event)
        switch state.currentTool {
        case .laser:
            state.laserPoints.append(LaserPoint(point: p, time: ProcessInfo.processInfo.systemUptime))
        case .eraser:
            state.eraseNear(p)
        case .text:
            break
        default:
            state.currentStroke?.points.append(p)
        }
        state.announceLive()
    }

    override func mouseUp(with event: NSEvent) {
        guard state.active else { return }
        if var cur = state.currentStroke, !cur.points.isEmpty {
            if cur.shape != .free, cur.points.count == 1 { cur.points.append(cur.points[0]) }
            state.commit(cur)
        }
        state.currentStroke = nil
        state.announceLive()
    }

    private func startFadeTimerIfNeeded() {
        guard fadeTimer == nil else { return }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let now = ProcessInfo.processInfo.systemUptime
            self.state.laserPoints.removeAll { now - $0.time > 0.7 }
            if self.state.laserPoints.isEmpty {
                timer.invalidate()
                self.fadeTimer = nil
            }
            self.state.announceLive()
        }
    }

    // ------------------------------------------------------------ text tool
    private func beginTextEntry(at globalP: CGPoint, in event: NSEvent) {
        let cfg = state.tools[.text]!
        let size = cfg.width * 4
        let p = local(globalP)
        let field = NSTextField(frame: NSRect(x: p.x, y: p.y - size, width: 240, height: size + 10))
        field.font = .systemFont(ofSize: size)
        field.textColor = cfg.color
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
        textFieldOrigin = globalP
    }

    private func commitTextField() {
        guard let field = activeTextField else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        activeTextField = nil
        guard !value.isEmpty else { return }
        let cfg = state.tools[.text]!
        state.commit(Stroke(shape: .text, color: cfg.color, width: cfg.width, alpha: cfg.alpha,
                             points: [textFieldOrigin], text: value, fontSize: cfg.width * 4))
    }
}

extension CanvasView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextField()
    }
}
