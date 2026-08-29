import AppKit

/// Shells out to /usr/sbin/screencapture rather than reimplementing region
/// selection or compositing: it already draws the native crosshair selector,
/// and since annotation strokes live in real on-screen windows (not an
/// invisible canvas the way the browser extension's was), a plain screen
/// capture picks them up automatically - no manual compositing step needed.
final class ScreenshotManager {
    static let shared = ScreenshotManager()
    private init() {}

    func captureRegion() {
        withToolbarHidden { self.run(["-i", self.outputPath()]) }
    }
    func captureFullScreen() {
        withToolbarHidden { self.run([self.outputPath()]) }
    }
    func copyFullScreenToClipboard() {
        withToolbarHidden { self.run(["-c"]) }
    }

    private func withToolbarHidden(_ body: @escaping () -> Void) {
        let panel = AppController.shared.toolbarPanel
        panel?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            body()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                panel?.orderFrontRegardless()
            }
        }
    }

    private func outputPath() -> String {
        let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MagicPen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("screenshot-\(Stamp.now()).png").path
    }

    private func run(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = args
        try? p.run()
    }
}

enum Stamp {
    static func now() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return f.string(from: Date())
    }
}
