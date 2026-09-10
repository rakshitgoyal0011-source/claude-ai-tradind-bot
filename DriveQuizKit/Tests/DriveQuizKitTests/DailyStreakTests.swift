import XCTest
@testable import DriveQuizKit

final class DailyStreakTests: XCTestCase {

    /// Fixed UTC calendar so these never depend on where the test runs.
    private var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2023-11-14 09:00:00 UTC. Anchored mid-morning so an eight hour
    /// offset stays inside the same calendar day.
    private let day1 = Date(timeIntervalSince1970: 1_699_952_400)
    private func days(_ count: Int, from date: Date) -> Date {
        date.addingTimeInterval(TimeInterval(count) * 86_400)
    }

    func testFirstPlayStartsAtOne() {
        var streak = DailyStreak.fresh
        streak.record(play: day1, calendar: utc)
        XCTAssertEqual(streak.current, 1)
        XCTAssertEqual(streak.best, 1)
    }

    func testConsecutiveDaysBuild() {
        var streak = DailyStreak.fresh
        streak.record(play: day1, calendar: utc)
        streak.record(play: days(1, from: day1), calendar: utc)
        streak.record(play: days(2, from: day1), calendar: utc)
        XCTAssertEqual(streak.current, 3)
        XCTAssertEqual(streak.best, 3)
    }

    func testSecondDriveSameDayChangesNothing() {
        var streak = DailyStreak.fresh
        streak.record(play: day1, calendar: utc)
        // Same calendar day, eight hours later.
        streak.record(play: day1.addingTimeInterval(8 * 3600), calendar: utc)
        XCTAssertEqual(streak.current, 1)
    }

    func testMissedDayResetsButKeepsBest() {
        var streak = DailyStreak.fresh
        streak.record(play: day1, calendar: utc)
        streak.record(play: days(1, from: day1), calendar: utc)
        streak.record(play: days(2, from: day1), calendar: utc)
        // Skipped a day.
        streak.record(play: days(4, from: day1), calendar: utc)
        XCTAssertEqual(streak.current, 1)
        XCTAssertEqual(streak.best, 3)
    }

    func testClockMovingBackwardsDoesNotCorruptTheStreak() {
        var streak = DailyStreak.fresh
        streak.record(play: days(3, from: day1), calendar: utc)
        streak.record(play: day1, calendar: utc)
        XCTAssertEqual(streak.current, 1)
        XCTAssertEqual(streak.lastPlayed, utc.startOfDay(for: days(3, from: day1)))
    }

    func testProjectedCurrent() {
        var streak = DailyStreak.fresh
        XCTAssertEqual(streak.projectedCurrent(on: day1, calendar: utc), 1)

        streak.record(play: day1, calendar: utc)
        // Same day again: no change.
        XCTAssertEqual(streak.projectedCurrent(on: day1, calendar: utc), 1)
        // Tomorrow would make it two.
        XCTAssertEqual(streak.projectedCurrent(on: days(1, from: day1), calendar: utc), 2)
        // A gap resets to one.
        XCTAssertEqual(streak.projectedCurrent(on: days(5, from: day1), calendar: utc), 1)
    }

    func testIsAtRisk() {
        var streak = DailyStreak.fresh
        streak.record(play: day1, calendar: utc)
        XCTAssertFalse(streak.isAtRisk(on: day1, calendar: utc))
        XCTAssertTrue(streak.isAtRisk(on: days(1, from: day1), calendar: utc))
        // Already broken, not merely at risk.
        XCTAssertFalse(streak.isAtRisk(on: days(3, from: day1), calendar: utc))
    }
}
