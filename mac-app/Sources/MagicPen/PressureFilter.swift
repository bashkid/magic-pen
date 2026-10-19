import Foundation
import CoreGraphics

/// Exponential moving-average (EMA) low-pass filter for pen input,
/// matching the algorithm reverse-engineered from ScreenBrush's ISSWLowpassFilter.
///
/// ScreenBrush uses:
///   α_prev = 6/7 ≈ 0.857142857  (weight of the previous smoothed value)
///   α_curr = 1/7 ≈ 0.142857142  (weight of the new raw sample)
///   timer interval = 16,666,666 ns  (60 fps GCD dispatch_source_timer)
///
/// This implementation extends the same algorithm to smooth both the pen
/// pressure AND the xy position, eliminating mouse/tablet jitter before the
/// Catmull-Rom spline renderer runs.
///
/// Usage:
///   1. Call `start(onSample:)` when a stroke begins (mouseDown).
///   2. Call `push(_:pressure:)` each time a raw input event arrives.
///   3. The `onSample` closure is called on the main queue at ~60 fps with the
///      smoothed (point, pressure) pair whenever new raw input is pending.
///   4. Call `stop()` on mouseUp; it flushes one final sample if needed.
final class PressureFilter {

    // MARK: - ScreenBrush constants (extracted from binary literal pool)
    private static let alphaPrev: CGFloat = 6.0 / 7.0   // 0.857142857...
    private static let alphaCurr: CGFloat = 1.0 / 7.0   // 0.142857142...
    private static let timerIntervalNs: Int = 16_666_666 // 60 fps

    // MARK: - State
    private var smoothedPoint: CGPoint = .zero
    private var smoothedPressure: CGFloat = 1.0

    /// Raw input accumulated since the last tick. nil means no new input.
    private var pendingPoint: CGPoint?
    private var pendingPressure: CGFloat = 1.0

    private var isFirstSample = true
    private var timer: DispatchSourceTimer?
    private var onSample: ((CGPoint, CGFloat) -> Void)?

    // MARK: - Lifecycle

    /// Start the 60 fps filter timer. `onSample` is called on the **main queue**.
    func start(onSample: @escaping (CGPoint, CGFloat) -> Void) {
        stop()
        self.onSample = onSample
        isFirstSample = true

        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(
            deadline: .now(),
            repeating: .nanoseconds(Self.timerIntervalNs),
            leeway: .milliseconds(100)   // same leeway ScreenBrush uses
        )
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    /// Feed a raw input sample. Thread-safe — may be called from any queue,
    /// but in practice always called from the main queue via NSEvent.
    func push(_ point: CGPoint, pressure: CGFloat) {
        pendingPoint = point
        pendingPressure = pressure
    }

    /// Stop the timer. Flushes one final smoothed sample if raw input is pending.
    func stop() {
        timer?.cancel()
        timer = nil

        // Flush any input that arrived after the last tick
        if let pending = pendingPoint {
            applyEMA(to: pending, pressure: pendingPressure)
            onSample?(smoothedPoint, smoothedPressure)
            pendingPoint = nil
        }
        onSample = nil
    }

    // MARK: - Private

    private func tick() {
        guard let pending = pendingPoint else { return }
        pendingPoint = nil
        applyEMA(to: pending, pressure: pendingPressure)
        onSample?(smoothedPoint, smoothedPressure)
    }

    private func applyEMA(to raw: CGPoint, pressure rawPressure: CGFloat) {
        if isFirstSample {
            // Seed with the first real value so the filter starts without lag
            smoothedPoint = raw
            smoothedPressure = rawPressure
            isFirstSample = false
            return
        }
        // EMA — identical formula to ScreenBrush's filterTick:
        //   smoothed = raw * (1/7) + previous * (6/7)
        smoothedPoint = CGPoint(
            x: raw.x * Self.alphaCurr + smoothedPoint.x * Self.alphaPrev,
            y: raw.y * Self.alphaCurr + smoothedPoint.y * Self.alphaPrev
        )
        smoothedPressure = rawPressure * Self.alphaCurr + smoothedPressure * Self.alphaPrev
    }
}
