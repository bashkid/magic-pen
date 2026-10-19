import AppKit

/// One per screen. Renders the shared AnnotatorState.strokes (stored in
/// global screen coordinates) translated into this window's local space, and
/// owns pointer handling for whichever screen the mouse is actually on.
final class CanvasView: NSView {
    private let state = AnnotatorState.shared
    private var fadeTimer: Timer?
    private var activeTextField: NSTextField?
    private var textFieldOrigin: CGPoint = .zero
    private var lastPenPressure: CGFloat = 1

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
        if stroke.shape == .free {
            drawFreeStroke(stroke)
            return
        }
        let path = path(for: stroke)
        stroke.color.withAlphaComponent(stroke.alpha).setStroke()
        path.stroke()
    }

    private func drawFreeStroke(_ stroke: Stroke) {
        let points = stroke.points.map(local)
        guard let first = points.first else { return }
        let pressures = stroke.points.indices.map { index -> CGFloat in
            guard index < stroke.pressures.count else { return 1 }
            return min(max(stroke.pressures[index], 0), 1)
        }
        let color = stroke.color.withAlphaComponent(stroke.alpha)
        color.setStroke()

        guard points.count > 1 else {
            let width = stroke.width * pressureScale(pressures.first ?? 1)
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: first.x - width / 2, y: first.y - width / 2,
                                        width: width, height: width)).fill()
            return
        }

        var samples: [(point: CGPoint, radius: CGFloat)] = []
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6,
                                   y: p1.y + (p2.y - p0.y) / 6)
            let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6,
                                   y: p2.y - (p3.y - p1.y) / 6)
            let distance = hypot(p2.x - p1.x, p2.y - p1.y)
            let steps = min(max(Int(distance / 5), 2), 8)
            let startPressure = pressures[index]
            let endPressure = pressures[index + 1]

            for step in (index == 0 ? 0 : 1)...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let inverse = 1 - t
                let point = CGPoint(
                    x: inverse * inverse * inverse * p1.x + 3 * inverse * inverse * t * control1.x
                        + 3 * inverse * t * t * control2.x + t * t * t * p2.x,
                    y: inverse * inverse * inverse * p1.y + 3 * inverse * inverse * t * control1.y
                        + 3 * inverse * t * t * control2.y + t * t * t * p2.y
                )
                let pressure = startPressure + (endPressure - startPressure) * t
                samples.append((point, max(1, stroke.width * pressureScale(pressure)) / 2))
            }
        }

        guard let first = samples.first, let last = samples.last else { return }
        var leftEdge: [CGPoint] = []
        var rightEdge: [CGPoint] = []
        for index in samples.indices {
            let previous = samples[max(index - 1, 0)].point
            let next = samples[min(index + 1, samples.count - 1)].point
            var dx = next.x - previous.x
            var dy = next.y - previous.y
            let length = hypot(dx, dy)
            if length > 0.001 { dx /= length; dy /= length } else { dx = 1; dy = 0 }
            let offsetX = -dy * samples[index].radius
            let offsetY = dx * samples[index].radius
            leftEdge.append(CGPoint(x: samples[index].point.x + offsetX,
                                    y: samples[index].point.y + offsetY))
            rightEdge.append(CGPoint(x: samples[index].point.x - offsetX,
                                     y: samples[index].point.y - offsetY))
        }

        let outline = NSBezierPath()
        outline.move(to: leftEdge[0])
        for point in leftEdge.dropFirst() { outline.line(to: point) }
        for point in rightEdge.reversed() { outline.line(to: point) }
        outline.close()
        color.setFill()
        outline.fill()
        for sample in [first, last] {
            let diameter = sample.radius * 2
            NSBezierPath(ovalIn: NSRect(x: sample.point.x - sample.radius,
                                        y: sample.point.y - sample.radius,
                                        width: diameter, height: diameter)).fill()
        }
    }

    private func pressureScale(_ pressure: CGFloat) -> CGFloat {
        0.2 + 0.8 * min(max(pressure, 0), 1)
    }

    private func pressure(from event: NSEvent, fallback: CGFloat) -> CGFloat {
        let value = CGFloat(event.pressure)
        let carriesPressure = event.type == .pressure || event.type == .tabletPoint
            || (value > 0 && value < 1)
        return carriesPressure ? min(max(value, 0), 1) : fallback
    }

    private func appendStrokeSample(at point: CGPoint, pressure: CGFloat) {
        guard var stroke = state.currentStroke else { return }
        if let index = stroke.points.indices.last,
           hypot(stroke.points[index].x - point.x, stroke.points[index].y - point.y) < 0.5 {
            if stroke.pressures.indices.contains(index) { stroke.pressures[index] = pressure }
        } else {
            stroke.points.append(point)
            stroke.pressures.append(pressure)
        }
        state.currentStroke = stroke
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
        lastPenPressure = pressure(from: event, fallback: 1)
        state.currentStroke = Stroke(shape: shape, color: cfg.color, width: cfg.width, alpha: cfg.alpha,
                                     points: [p], pressures: [lastPenPressure])
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
            lastPenPressure = pressure(from: event, fallback: lastPenPressure)
            appendStrokeSample(at: p, pressure: lastPenPressure)
        }
        state.announceLive()
    }

    override func pressureChange(with event: NSEvent) {
        guard state.active, state.currentStroke?.shape == .free else { return }
        lastPenPressure = min(max(CGFloat(event.pressure), 0), 1)
        appendStrokeSample(at: globalPoint(from: event), pressure: lastPenPressure)
        state.announceLive()
    }

    override func mouseUp(with event: NSEvent) {
        guard state.active else { return }
        if var cur = state.currentStroke, !cur.points.isEmpty {
            if cur.shape != .free, cur.points.count == 1 {
                cur.points.append(cur.points[0])
                cur.pressures.append(cur.pressures.first ?? 1)
            }
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
        // Two-part fix for typed characters silently going nowhere: the app
        // runs as an LSUIElement accessory (no Dock icon), so its windows
        // don't receive keyboard events unless the app is explicitly
        // activated even after becoming key (OverlayWindow.canBecomeKey).
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
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
