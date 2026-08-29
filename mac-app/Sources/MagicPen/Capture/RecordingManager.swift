import AppKit
import ScreenCaptureKit
import AVFoundation

/// Screen recording via ScreenCaptureKit + AVAssetWriter. First use triggers
/// the system Screen Recording permission prompt (System Settings > Privacy
/// & Security > Screen Recording) - that's expected and out of app control.
final class RecordingManager: NSObject, SCStreamOutput, SCStreamDelegate {
    static let shared = RecordingManager()
    private override init() { super.init() }

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var outputURL: URL?
    private var webmURL: URL?
    private var chromeWindowObservers: [NSObjectProtocol] = []

    func toggle() {
        if AnnotatorState.shared.recording { stop() } else { start() }
    }

    /// Every one of our own windows except the per-screen overlay canvases
    /// (those must stay visible - they're where the user's annotations live)
    /// is UI chrome: the toolbar panel and any open flyout popover. Popovers
    /// use an internal system window class we can't name directly, so
    /// "not a CanvasView" is the reliable signal instead.
    @MainActor
    private static func chromeWindowIDs() -> Set<Int> {
        Set(NSApp.windows.compactMap { window in
            (window.contentView is CanvasView) ? nil : window.windowNumber
        })
    }

    private func start() {
        Task {
            do {
                let content = try await SCShareableContent.current
                // content.displays is unordered - .first alone isn't guaranteed
                // to be the Mac's actual main display, so a multi-monitor setup
                // could silently record the wrong screen.
                let mainDisplayID = CGMainDisplayID()
                guard let display = content.displays.first(where: { $0.displayID == mainDisplayID })
                    ?? content.displays.first else { return }
                let screen = NSScreen.screens.first {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
                }
                // Exclude the floating toolbar and any open popover flyout the
                // same way screenshots hide the toolbar (ScreenshotManager.
                // withToolbarHidden) - otherwise they're baked into the corner
                // of every recording.
                let chromeIDs = await Self.chromeWindowIDs()
                let excludedWindows = content.windows.filter { chromeIDs.contains(Int($0.windowID)) }
                let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
                let scale = Int(screen?.backingScaleFactor ?? 2)
                let config = SCStreamConfiguration()
                config.width = display.width * scale
                config.height = display.height * scale
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = true

                let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("MagicPen", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                // ScreenCaptureKit/AVAssetWriter can't write WebM directly -
                // capture to a hidden intermediate .mov, then transcode to the
                // user-facing .webm (and delete the .mov) once recording stops.
                let stamp = Stamp.now()
                let url = dir.appendingPathComponent(".recording-\(stamp).mov")
                webmURL = dir.appendingPathComponent("recording-\(stamp).webm")
                outputURL = url

                let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                let settings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: config.width,
                    AVVideoHeightKey: config.height
                ]
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                input.expectsMediaDataInRealTime = true
                writer.add(input)
                self.writer = writer
                self.input = input

                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "myannotator.capture"))
                try await stream.startCapture()
                self.stream = stream

                await MainActor.run {
                    AnnotatorState.shared.recording = true
                    NotificationCenter.default.post(name: .annotatorStateChanged, object: nil)
                    self.observeChromeWindows()
                }
            } catch {
                NSLog("Recording failed to start: \(error)")
            }
        }
    }

    // Popovers open/close over the course of a recording (Shapes, Timer,
    // Board...) - each one is a fresh window the static filter built at
    // start() never saw, so keep re-excluding as they come and go instead of
    // only excluding whatever chrome happened to exist at the start.
    @MainActor
    private func observeChromeWindows() {
        let center = NotificationCenter.default
        chromeWindowObservers = [
            center.addObserver(forName: NSPopover.didShowNotification, object: nil, queue: .main) { [weak self] _ in
                Task { await self?.refreshExcludedWindows() }
            },
            center.addObserver(forName: NSPopover.didCloseNotification, object: nil, queue: .main) { [weak self] _ in
                Task { await self?.refreshExcludedWindows() }
            }
        ]
    }

    private func refreshExcludedWindows() async {
        guard let stream else { return }
        guard let content = try? await SCShareableContent.current else { return }
        let mainDisplayID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID })
            ?? content.displays.first else { return }
        let chromeIDs = await Self.chromeWindowIDs()
        let excludedWindows = content.windows.filter { chromeIDs.contains(Int($0.windowID)) }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        try? await stream.updateContentFilter(filter)
    }

    private func stop() {
        chromeWindowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        chromeWindowObservers.removeAll()
        Task {
            try? await stream?.stopCapture()
            stream = nil
            input?.markAsFinished()
            await writer?.finishWriting()
            let movURL = outputURL
            let webmURL = self.webmURL
            await MainActor.run {
                AnnotatorState.shared.recording = false
                NotificationCenter.default.post(name: .annotatorStateChanged, object: nil)
            }
            guard let movURL else { return }
            guard let webmURL, let ffmpeg = Self.findFFmpeg() else {
                // No ffmpeg on this machine - fall back to the raw .mov rather
                // than lose the recording; strip the leading dot so it isn't
                // a hidden file.
                NSLog("ffmpeg not found - keeping .mov output (no WebM transcode)")
                let visibleURL = movURL.deletingLastPathComponent()
                    .appendingPathComponent(String(movURL.lastPathComponent.dropFirst()))
                try? FileManager.default.moveItem(at: movURL, to: visibleURL)
                await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([visibleURL]) }
                return
            }
            let status = await Self.runProcess(ffmpeg, args: [
                "-y", "-i", movURL.path,
                "-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-deadline", "good",
                webmURL.path
            ])
            if status == 0 {
                try? FileManager.default.removeItem(at: movURL)
                await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([webmURL]) }
            } else {
                NSLog("ffmpeg transcode to WebM failed (status \(status)) - keeping .mov output")
                let visibleURL = movURL.deletingLastPathComponent()
                    .appendingPathComponent(String(movURL.lastPathComponent.dropFirst()))
                try? FileManager.default.moveItem(at: movURL, to: visibleURL)
                await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([visibleURL]) }
            }
        }
    }

    private static func findFFmpeg() -> String? {
        for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func runProcess(_ executable: String, args: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.terminationHandler = { p in continuation.resume(returning: p.terminationStatus) }
            do {
                try process.run()
            } catch {
                NSLog("Failed to launch \(executable): \(error)")
                continuation.resume(returning: -1)
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let writer, let input else { return }
        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Stream stopped with error: \(error)")
    }
}
