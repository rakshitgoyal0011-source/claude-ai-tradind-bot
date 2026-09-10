import Foundation

/// Everything DriveQuiz remembers between drives. Local only, no accounts.
public struct PlayerProgress: Codable, Equatable, Sendable {

    public var daily: DailyStreak
    public var history: QuestionHistory
    public var totalSessions: Int
    public var totalAsked: Int
    public var totalCorrect: Int

    public init(
        daily: DailyStreak = .fresh,
        history: QuestionHistory = .empty,
        totalSessions: Int = 0,
        totalAsked: Int = 0,
        totalCorrect: Int = 0
    ) {
        self.daily = daily
        self.history = history
        self.totalSessions = totalSessions
        self.totalAsked = totalAsked
        self.totalCorrect = totalCorrect
    }

    public static let fresh = PlayerProgress()

    /// How long a question stays "recently asked".
    public static let defaultCooldown: TimeInterval = 14 * 24 * 60 * 60
    /// History older than this is discarded.
    public static let retentionWindow: TimeInterval = 120 * 24 * 60 * 60

    /// Call once when a drive ends with at least one question asked.
    public mutating func recordSession(
        askedIDs: [String],
        asked: Int,
        correct: Int,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard asked > 0 else { return }
        totalSessions += 1
        totalAsked += asked
        totalCorrect += correct
        history.record(askedIDs, at: date)
        history.prune(olderThan: Self.retentionWindow, now: date)
        daily.record(play: date, calendar: calendar)
    }
}
