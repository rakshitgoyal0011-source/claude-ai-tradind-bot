import Foundation

/// Consecutive calendar days with at least one completed drive.
///
/// Day arithmetic goes through Calendar rather than dividing seconds, so
/// daylight saving changes and month boundaries cannot break a streak.
public struct DailyStreak: Codable, Equatable, Sendable {

    public private(set) var current: Int
    public private(set) var best: Int
    /// Start of the last day played, or nil if never played.
    public private(set) var lastPlayed: Date?

    public init(current: Int = 0, best: Int = 0, lastPlayed: Date? = nil) {
        self.current = current
        self.best = best
        self.lastPlayed = lastPlayed
    }

    public static let fresh = DailyStreak()

    /// Call once per completed drive. Playing twice in a day changes nothing.
    public mutating func record(play date: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: date)

        guard let last = lastPlayed else {
            current = 1
            best = max(best, 1)
            lastPlayed = today
            return
        }

        let gap = calendar.dateComponents([.day], from: last, to: today).day ?? 0

        switch gap {
        case 0:
            // Already counted today.
            return
        case 1:
            current += 1
        case let days where days > 1:
            // Missed at least one day. Back to the start.
            current = 1
        default:
            // Negative gap means the clock moved backwards, usually a
            // timezone change. Leave the streak alone rather than corrupt it.
            return
        }

        lastPlayed = today
        best = max(best, current)
    }

    /// What `current` will become if a drive is completed on this date.
    /// Lets the intro name the day the driver is about to earn without
    /// overstating it on a second drive the same day.
    public func projectedCurrent(on date: Date, calendar: Calendar = .current) -> Int {
        guard let last = lastPlayed, current > 0 else { return 1 }
        let today = calendar.startOfDay(for: date)

        switch calendar.dateComponents([.day], from: last, to: today).day ?? 0 {
        case 0: return current
        case 1: return current + 1
        case let gap where gap > 1: return 1
        default: return current
        }
    }

    /// True when the streak survives only if they play today.
    public func isAtRisk(on date: Date, calendar: Calendar = .current) -> Bool {
        guard let last = lastPlayed, current > 0 else { return false }
        let today = calendar.startOfDay(for: date)
        return (calendar.dateComponents([.day], from: last, to: today).day ?? 0) == 1
    }
}
