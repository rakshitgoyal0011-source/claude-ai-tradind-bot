import Foundation

/// How much drive is left. Phase 1 counts down a number the driver typed.
/// Phase 2 swaps in a MapKit ETA behind the same protocol without the game
/// loop changing at all.
protocol SessionClock: AnyObject {
    var remainingSeconds: TimeInterval { get }
    var elapsedSeconds: TimeInterval { get }
    func start()
    func pause()
    func resume()
    /// Release anything the clock is polling. Called once the game ends.
    func stop()
}

final class ManualClock: SessionClock {

    private let total: TimeInterval
    private var startedAt: Date?
    private var accumulated: TimeInterval = 0
    private var isPaused = true

    init(minutes: Int) {
        self.total = TimeInterval(minutes) * 60
    }

    var elapsedSeconds: TimeInterval {
        guard let startedAt, !isPaused else { return accumulated }
        return accumulated + Date().timeIntervalSince(startedAt)
    }

    var remainingSeconds: TimeInterval {
        max(0, total - elapsedSeconds)
    }

    func start() {
        startedAt = Date()
        isPaused = false
    }

    /// Pausing must stop the clock. A driver who takes a call should not
    /// lose the rest of their game to it.
    func pause() {
        guard !isPaused, let startedAt else { return }
        accumulated += Date().timeIntervalSince(startedAt)
        self.startedAt = nil
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        startedAt = Date()
        isPaused = false
    }

    func stop() { pause() }
}
