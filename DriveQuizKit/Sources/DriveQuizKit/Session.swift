import Foundation

/// Running tally for one drive.
public struct Session: Sendable, Equatable {
    public let startedAt: Date
    public let plannedDuration: TimeInterval

    public private(set) var asked: Int = 0
    public private(set) var correct: Int = 0
    public private(set) var streak: Int = 0
    public private(set) var bestStreak: Int = 0

    public init(startedAt: Date = Date(), plannedDuration: TimeInterval) {
        self.startedAt = startedAt
        self.plannedDuration = plannedDuration
    }

    public mutating func recordCorrect() {
        asked += 1
        correct += 1
        streak += 1
        bestStreak = max(bestStreak, streak)
    }

    public mutating func recordIncorrect() {
        asked += 1
        streak = 0
    }

    /// Skips count as asked and break the streak, so skipping is not a
    /// free way to protect a run.
    public mutating func recordSkipped() {
        asked += 1
        streak = 0
    }

    public var remainingStreakIsHot: Bool { streak >= 3 }
}
