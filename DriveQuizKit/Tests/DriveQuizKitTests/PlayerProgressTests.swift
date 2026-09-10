import XCTest
@testable import DriveQuizKit

final class PlayerProgressTests: XCTestCase {

    private var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let day1 = Date(timeIntervalSince1970: 1_699_952_400)

    func testRecordingASessionUpdatesEverything() {
        var progress = PlayerProgress.fresh
        progress.recordSession(
            askedIDs: ["q1", "q2"], asked: 2, correct: 1,
            at: day1, calendar: utc
        )

        XCTAssertEqual(progress.totalSessions, 1)
        XCTAssertEqual(progress.totalAsked, 2)
        XCTAssertEqual(progress.totalCorrect, 1)
        XCTAssertEqual(progress.daily.current, 1)
        XCTAssertNotNil(progress.history.lastAsked(for: "q1"))
    }

    func testAnEmptySessionIsNotRecorded() {
        var progress = PlayerProgress.fresh
        progress.recordSession(askedIDs: [], asked: 0, correct: 0, at: day1, calendar: utc)

        XCTAssertEqual(progress.totalSessions, 0)
        XCTAssertEqual(progress.daily.current, 0)
        XCTAssertNil(progress.daily.lastPlayed)
    }

    func testRoundTripsThroughJSON() throws {
        var progress = PlayerProgress.fresh
        progress.recordSession(
            askedIDs: ["q1"], asked: 1, correct: 1,
            at: day1, calendar: utc
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(
            PlayerProgress.self,
            from: try encoder.encode(progress)
        )
        XCTAssertEqual(restored, progress)
    }
}
