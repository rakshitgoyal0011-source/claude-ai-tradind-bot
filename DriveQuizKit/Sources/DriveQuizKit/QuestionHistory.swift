import Foundation

/// When each question was last asked, so the planner can prefer fresh ones.
public struct QuestionHistory: Codable, Equatable, Sendable {

    public private(set) var lastAsked: [String: Date]

    public init(lastAsked: [String: Date] = [:]) {
        self.lastAsked = lastAsked
    }

    public static let empty = QuestionHistory()

    public func lastAsked(for id: String) -> Date? { lastAsked[id] }

    public mutating func record(_ ids: [String], at date: Date) {
        for id in ids { lastAsked[id] = date }
    }

    /// Keeps the file from growing without bound. Anything older than the
    /// window is as good as unseen anyway.
    public mutating func prune(olderThan window: TimeInterval, now: Date = Date()) {
        lastAsked = lastAsked.filter { now.timeIntervalSince($0.value) < window }
    }

    /// 0 never asked, 1 asked but past its cooldown, 2 asked recently.
    public func freshnessRank(
        for id: String,
        now: Date,
        cooldown: TimeInterval
    ) -> Int {
        guard let seen = lastAsked[id] else { return 0 }
        return now.timeIntervalSince(seen) >= cooldown ? 1 : 2
    }
}
