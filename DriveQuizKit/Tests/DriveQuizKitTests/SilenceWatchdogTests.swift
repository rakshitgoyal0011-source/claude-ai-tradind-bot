import XCTest
@testable import DriveQuizKit

final class SilenceWatchdogTests: XCTestCase {

    func testNormalGapsAreLeftAlone() {
        // A listen window plus a long fact is well inside the threshold.
        XCTAssertEqual(SilenceWatchdog.action(silentFor: 0, isPaused: false, isInterrupted: false), .wait)
        XCTAssertEqual(SilenceWatchdog.action(silentFor: 20, isPaused: false, isInterrupted: false), .wait)
        XCTAssertEqual(SilenceWatchdog.action(silentFor: 29.9, isPaused: false, isInterrupted: false), .wait)
    }

    func testNudgesThenGivesUp() {
        XCTAssertEqual(SilenceWatchdog.action(silentFor: 30, isPaused: false, isInterrupted: false), .nudge)
        XCTAssertEqual(SilenceWatchdog.action(silentFor: 59, isPaused: false, isInterrupted: false), .nudge)
        XCTAssertEqual(SilenceWatchdog.action(silentFor: 60, isPaused: false, isInterrupted: false), .giveUp)
        XCTAssertEqual(SilenceWatchdog.action(silentFor: 600, isPaused: false, isInterrupted: false), .giveUp)
    }

    func testSilenceTheDriverAskedForIsNeverActedOn() {
        // Pausing is a request for quiet. Acting on it would defeat the point.
        XCTAssertEqual(SilenceWatchdog.action(silentFor: 600, isPaused: true, isInterrupted: false), .wait)
    }

    func testSilenceWithAnAudibleCauseIsNeverActedOn() {
        // A call or Siri owns the audio. The driver can hear why we stopped,
        // and we could not speak even if we wanted to.
        XCTAssertEqual(SilenceWatchdog.action(silentFor: 600, isPaused: false, isInterrupted: true), .wait)
    }
}
