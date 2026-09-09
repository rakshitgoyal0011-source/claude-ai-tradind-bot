import XCTest
@testable import DriveQuizKit

final class ETASnapshotTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testCountsDownFromWhenItWasTaken() {
        let snapshot = ETASnapshot(seconds: 600, takenAt: epoch)
        XCTAssertEqual(snapshot.remaining(at: epoch), 600)
        XCTAssertEqual(snapshot.remaining(at: epoch.addingTimeInterval(120)), 480)
    }

    func testNeverGoesNegative() {
        let snapshot = ETASnapshot(seconds: 60, takenAt: epoch)
        XCTAssertEqual(snapshot.remaining(at: epoch.addingTimeInterval(300)), 0)
    }

    func testClampsNegativeInput() {
        XCTAssertEqual(ETASnapshot(seconds: -50, takenAt: epoch).seconds, 0)
    }

    func testWrapUpThreshold() {
        let snapshot = ETASnapshot(seconds: 600, takenAt: epoch)
        XCTAssertFalse(snapshot.shouldWrapUp(at: epoch))
        // 89 seconds left is under the 90 second threshold.
        XCTAssertTrue(snapshot.shouldWrapUp(at: epoch.addingTimeInterval(511)))
    }

    func testAFailedRefreshDoesNotReplaceAGoodEstimate() {
        let good = ETASnapshot(seconds: 600, takenAt: epoch)
        let bad = ETASnapshot(seconds: 0, takenAt: epoch.addingTimeInterval(120))
        XCTAssertEqual(good.replacing(with: bad), good)
    }

    func testARealRefreshDoesReplace() {
        let good = ETASnapshot(seconds: 600, takenAt: epoch)
        // Traffic: the drive got longer, not shorter.
        let fresh = ETASnapshot(seconds: 900, takenAt: epoch.addingTimeInterval(120))
        XCTAssertEqual(good.replacing(with: fresh), fresh)
    }
}
