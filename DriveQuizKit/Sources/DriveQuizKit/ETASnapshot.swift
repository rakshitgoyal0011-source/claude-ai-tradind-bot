import Foundation

/// A single arrival estimate and the moment it was taken.
///
/// The pure half of the ETA clock. MapKit is rate limited, so the app asks
/// for a fresh estimate every couple of minutes and interpolates in between
/// by simply counting down from the last one.
public struct ETASnapshot: Equatable, Sendable {

    public let seconds: TimeInterval
    public let takenAt: Date

    public init(seconds: TimeInterval, takenAt: Date) {
        self.seconds = max(0, seconds)
        self.takenAt = takenAt
    }

    public func remaining(at moment: Date) -> TimeInterval {
        max(0, seconds - moment.timeIntervalSince(takenAt))
    }

    /// True once the drive is nearly over and the game should be wrapping up.
    public func shouldWrapUp(at moment: Date, threshold: TimeInterval = PackPlanner.wrapUpThreshold) -> Bool {
        remaining(at: moment) < threshold
    }

    /// Guards against a nonsense estimate replacing a good one. A rerouted
    /// ETA that jumps by more than this is accepted, but a zero or negative
    /// reading from a failed request is not.
    public func replacing(with fresh: ETASnapshot) -> ETASnapshot {
        fresh.seconds > 0 ? fresh : self
    }
}
