import XCTest
@testable import DriveQuizKit

final class TextNormalizerTests: XCTestCase {

    func testStripsFillersAndPunctuation() {
        XCTAssertEqual(TextNormalizer.normalize("Uh, is it Napoleon?"), "napoleon")
        XCTAssertEqual(TextNormalizer.normalize("um... well, Paris!"), "paris")
    }

    func testStripsLeadInPhrases() {
        XCTAssertEqual(TextNormalizer.normalize("I think it's the Nile"), "nile")
        XCTAssertEqual(TextNormalizer.normalize("my guess is Jupiter"), "jupiter")
        XCTAssertEqual(TextNormalizer.normalize("I want to say 1945"), "1945")
    }

    func testFoldsAccentsAndCase() {
        XCTAssertEqual(TextNormalizer.normalize("Beyoncé"), "beyonce")
        XCTAssertEqual(TextNormalizer.normalize("ZÜRICH"), "zurich")
    }

    func testMapsSpokenNumbersToDigits() {
        XCTAssertEqual(TextNormalizer.normalize("eight"), "8")
        XCTAssertEqual(TextNormalizer.normalize("I think it's twelve"), "12")
    }

    func testNeverReturnsEmptyForRealInput() {
        // "so" is a filler and "the" an article, but they are all we have.
        XCTAssertEqual(TextNormalizer.normalize("so"), "so")
        XCTAssertEqual(TextNormalizer.normalize("the"), "the")
        XCTAssertEqual(TextNormalizer.normalize(""), "")
    }

    func testCommandTokensKeepLeadInsIntact() {
        // The whole point: command matching must still see "the answer is".
        XCTAssertEqual(
            TextNormalizer.commandTokens("uh, the answer is a stop sign"),
            ["the", "answer", "is", "a", "stop", "sign"]
        )
        XCTAssertEqual(TextNormalizer.commandTokens("one more time"), ["one", "more", "time"])
    }
}
