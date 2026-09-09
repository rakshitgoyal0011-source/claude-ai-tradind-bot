import XCTest
@testable import DriveQuizKit

final class CommandMatcherTests: XCTestCase {

    func testEachCommandFromTheBrief() {
        XCTAssertEqual(CommandMatcher.command(in: "repeat"), .repeatQuestion)
        XCTAssertEqual(CommandMatcher.command(in: "skip"), .skip)
        XCTAssertEqual(CommandMatcher.command(in: "pause"), .pause)
        XCTAssertEqual(CommandMatcher.command(in: "how many left"), .howManyLeft)
        XCTAssertEqual(CommandMatcher.command(in: "stop"), .stop)
    }

    func testNaturalPhrasings() {
        XCTAssertEqual(CommandMatcher.command(in: "uh, can you repeat that?"), .repeatQuestion)
        XCTAssertEqual(CommandMatcher.command(in: "say that again"), .repeatQuestion)
        XCTAssertEqual(CommandMatcher.command(in: "skip this one"), .skip)
        XCTAssertEqual(CommandMatcher.command(in: "I don't know"), .skip)
        XCTAssertEqual(CommandMatcher.command(in: "how much longer"), .howManyLeft)
        XCTAssertEqual(CommandMatcher.command(in: "hold on"), .pause)
        XCTAssertEqual(CommandMatcher.command(in: "that's enough"), .stop)
    }

    func testAnswersAreNotMistakenForCommands() {
        // A bare command word buried in an answer must not hijack the turn.
        XCTAssertNil(CommandMatcher.command(in: "the answer is a stop sign"))
        XCTAssertNil(CommandMatcher.command(in: "I think it's a mountain pass"))
        XCTAssertNil(CommandMatcher.command(in: "Napoleon"))
        XCTAssertNil(CommandMatcher.command(in: "the Nile"))
    }

    func testAllowListGatesCommandsByState() {
        // While paused only resume and stop are legal.
        let paused: Set<VoiceCommand> = [.resume, .stop]
        XCTAssertEqual(CommandMatcher.command(in: "keep going", allowing: paused), .resume)
        XCTAssertEqual(CommandMatcher.command(in: "stop", allowing: paused), .stop)
        XCTAssertNil(CommandMatcher.command(in: "skip", allowing: paused))
    }

    func testEmptyInput() {
        XCTAssertNil(CommandMatcher.command(in: ""))
        XCTAssertNil(CommandMatcher.command(in: "   "))
    }
}
