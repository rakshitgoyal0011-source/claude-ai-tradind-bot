import XCTest
@testable import DriveQuizKit

final class SessionTests: XCTestCase {

    func testTracksScoreAndStreak() {
        var session = Session(plannedDuration: 1200)
        session.recordCorrect()
        session.recordCorrect()
        session.recordCorrect()
        XCTAssertEqual(session.asked, 3)
        XCTAssertEqual(session.correct, 3)
        XCTAssertEqual(session.streak, 3)
        XCTAssertEqual(session.bestStreak, 3)
    }

    func testWrongAnswerBreaksStreakButKeepsBest() {
        var session = Session(plannedDuration: 1200)
        session.recordCorrect()
        session.recordCorrect()
        session.recordIncorrect()
        XCTAssertEqual(session.asked, 3)
        XCTAssertEqual(session.correct, 2)
        XCTAssertEqual(session.streak, 0)
        XCTAssertEqual(session.bestStreak, 2)
    }

    func testSkipCountsAsAskedAndBreaksStreak() {
        var session = Session(plannedDuration: 1200)
        session.recordCorrect()
        session.recordSkipped()
        XCTAssertEqual(session.asked, 2)
        XCTAssertEqual(session.correct, 1)
        XCTAssertEqual(session.streak, 0)
    }
}
