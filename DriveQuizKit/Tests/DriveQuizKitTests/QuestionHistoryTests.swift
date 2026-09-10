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

final class QuestionDecodingTests: XCTestCase {

    /// A pack missing an optional-ish key must still load. PackLoader skips a
    /// pack it cannot parse, so a strict decoder would cost twenty questions
    /// over one omitted line.
    func testDecodesWithOnlyTheEssentialFields() throws {
        let json = """
        {
          "id": "q1",
          "prompt": "What is the capital of France?",
          "canonicalAnswer": "Paris",
          "factOneLiner": "It has been the capital since the tenth century."
        }
        """.data(using: .utf8)!

        let question = try JSONDecoder().decode(Question.self, from: json)
        XCTAssertEqual(question.canonicalAnswer, "Paris")
        XCTAssertEqual(question.alternates, [])
        XCTAssertEqual(question.difficulty, .medium)
        XCTAssertEqual(question.estimatedSeconds, 30)
        XCTAssertNil(question.editTolerance)
    }

    func testStillRequiresTheEssentialFields() {
        let json = #"{"id": "q1", "prompt": "no answer here"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(Question.self, from: json))
    }

    func testRoundTripsWithEveryFieldPresent() throws {
        let original = Question(
            id: "q1", prompt: "p", canonicalAnswer: "a", alternates: ["b"],
            factOneLiner: "f", difficulty: .hard, estimatedSeconds: 42,
            editTolerance: 1
        )
        let restored = try JSONDecoder().decode(
            Question.self, from: try JSONEncoder().encode(original)
        )
        XCTAssertEqual(restored, original)
    }
}
