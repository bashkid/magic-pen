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

    func toggle() {
        if AnnotatorState.shared.recording { stop() } else { start() }
    }

    private func start() {
        Task {
            do {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first else { return }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let scale = Int(NSScreen.main?.backingScaleFactor ?? 2)
                let config = SCStreamConfiguration()
                config.width = display.width * scale
                config.height = display.height * scale
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = true

                let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("MagicPen", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent("recording-\(Stamp.now()).mov")
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
                }
            } catch {
                NSLog("Recording failed to start: \(error)")
            }
        }
    }

    private func stop() {
        Task {
            try? await stream?.stopCapture()
            stream = nil
            input?.markAsFinished()
            await writer?.finishWriting()
            let url = outputURL
            await MainActor.run {
                AnnotatorState.shared.recording = false
                NotificationCenter.default.post(name: .annotatorStateChanged, object: nil)
                if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
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
