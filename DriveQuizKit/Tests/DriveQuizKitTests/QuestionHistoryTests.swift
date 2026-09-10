import XCTest
@testable import DriveQuizKit

final class QuestionHistoryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 86_400

    func testRecordsAndReadsBack() {
        var history = QuestionHistory.empty
        history.record(["a", "b"], at: now)
        XCTAssertEqual(history.lastAsked(for: "a"), now)
        XCTAssertNil(history.lastAsked(for: "c"))
    }

    func testFreshnessRanks() {
        var history = QuestionHistory.empty
        history.record(["recent"], at: now.addingTimeInterval(-2 * day))
        history.record(["stale"], at: now.addingTimeInterval(-30 * day))
        let cooldown = 14 * day

        XCTAssertEqual(history.freshnessRank(for: "unseen", now: now, cooldown: cooldown), 0)
        XCTAssertEqual(history.freshnessRank(for: "stale", now: now, cooldown: cooldown), 1)
        XCTAssertEqual(history.freshnessRank(for: "recent", now: now, cooldown: cooldown), 2)
    }

    func testPruneDropsOldEntriesOnly() {
        var history = QuestionHistory.empty
        history.record(["old"], at: now.addingTimeInterval(-200 * day))
        history.record(["new"], at: now.addingTimeInterval(-1 * day))
        history.prune(olderThan: 120 * day, now: now)

        XCTAssertNil(history.lastAsked(for: "old"))
        XCTAssertNotNil(history.lastAsked(for: "new"))
    }
}
