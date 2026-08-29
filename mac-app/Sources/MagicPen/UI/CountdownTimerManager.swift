import AppKit

/// A small always-on-top pill showing a running MM:SS countdown - the Timer
/// cell's flyout starts/stops this. Independent of recording: it's just a
/// visible on-screen timer (for timeboxing a demo, a talk, etc.), not
/// something that drives any other feature.
final class CountdownTimerManager {
    static let shared = CountdownTimerManager()
    private init() {}

    private var window: NSWindow?
    private var label: NSTextField?
    private var tickTimer: Timer?
    private var remainingSeconds: Int = 0

    var isRunning: Bool { tickTimer != nil }
    var remaining: Int { remainingSeconds }

    func start(minutes: Double) {
        stop()
        remainingSeconds = max(1, Int((minutes * 60).rounded()))
        buildWindow()
        updateLabel()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        announce()
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        window?.orderOut(nil)
        window = nil
        label = nil
        announce()
    }

    private func tick() {
        remainingSeconds -= 1
        guard remainingSeconds > 0 else {
            // Short on purpose - "Time's up" at the same large fill-the-box
            // font size the digits use would overflow the box's width.
            updateLabel(text: "Done")
            NSSound.beep()
            tickTimer?.invalidate()
            tickTimer = nil
            // Leave the "Time's up" pill visible for a moment instead of
            // vanishing the instant it hits zero - stop() (which tears the
            // window down) fires a beat later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.stop() }
            return
        }
        updateLabel()
    }

    private func updateLabel(text: String? = nil) {
        label?.stringValue = text ?? format(remainingSeconds)
    }

    private func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func announce() {
        NotificationCenter.default.post(name: .annotatorStateChanged, object: nil)
    }

    private func buildWindow() {
        guard let screen = NSScreen.main else { return }
        let width = Self.points(forCentimeters: 2.5, on: screen)
        let height = width * 0.42 // same proportions as the original 96x36 pill, just scaled up
        let size = NSSize(width: width, height: height)
        let origin = CGPoint(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height - 24)
        let win = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless],
                            backing: .buffered, defer: false, screen: screen)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .statusBar
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // The user drags this anywhere on screen - unlike the click-through
        // annotation overlays, this one has to actually accept mouse events
        // for that (isMovableByWindowBackground moves the window on any
        // background drag, no custom mouseDown handling needed).
        win.isMovableByWindowBackground = true

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        container.layer?.cornerRadius = height / 4

        let lbl = NSTextField(labelWithString: "")
        // Sized to the box, not just a font size that happens to fit inside
        // it - the digits should fill the countdown box, not sit small in
        // the middle of it.
        lbl.font = .monospacedDigitSystemFont(ofSize: height * 0.62, weight: .bold)
        lbl.textColor = .black
        lbl.alignment = .center
        lbl.lineBreakMode = .byClipping // a stray long value clips cleanly instead of "12:3..."
        // Pinned to the container's center rather than stretched to its full
        // bounds - a stretched NSTextField draws its text top-aligned inside
        // that frame instead of vertically centered, which is what read as
        // "top center" instead of dead center.
        lbl.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            lbl.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        win.contentView = container
        win.orderFrontRegardless()
        window = win
        label = lbl
    }

    /// AppKit points aren't a fixed physical size - they scale with each
    /// display's pixel density - so a literal "2.5cm" needs the display's
    /// actual physical width (CGDisplayScreenSize, in millimeters) to convert
    /// correctly instead of assuming the old 72-points-per-inch print
    /// convention, which is off on most real Mac displays.
    private static func points(forCentimeters cm: CGFloat, on screen: NSScreen) -> CGFloat {
        let fallback = cm * 72 / 2.54
        guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            return fallback
        }
        let physicalMM = CGDisplayScreenSize(displayID)
        guard physicalMM.width > 0 else { return fallback }
        let pointsPerMM = screen.frame.width / physicalMM.width
        return cm * 10 * pointsPerMM
    }
}
