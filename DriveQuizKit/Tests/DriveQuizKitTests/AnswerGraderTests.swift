import XCTest
@testable import DriveQuizKit

final class AnswerGraderTests: XCTestCase {

    private let napoleon = Question(
        id: "q-napoleon",
        prompt: "Which French general crowned himself emperor in 1804?",
        canonicalAnswer: "Napoleon",
        alternates: ["Napoleon Bonaparte", "Bonaparte"],
        factOneLiner: "He crowned himself rather than let the pope do it.",
        estimatedSeconds: 30
    )

    private func assertCorrect(_ said: String, _ question: Question, line: UInt = #line) {
        guard case .correct = AnswerGrader.grade(candidates: [said], question: question) else {
            return XCTFail("expected correct for \"\(said)\"", line: line)
        }
    }

    private func assertIncorrect(_ said: String, _ question: Question, line: UInt = #line) {
        XCTAssertEqual(
            AnswerGrader.grade(candidates: [said], question: question),
            .incorrect,
            "expected incorrect for \"\(said)\"",
            line: line
        )
    }

    func testBriefExample() {
        assertCorrect("Uh, is it Napoleon?", napoleon)
    }

    func testFillerAndLeadInVariations() {
        assertCorrect("Napoleon", napoleon)
        assertCorrect("um I think it's Napoleon", napoleon)
        assertCorrect("the answer is Napoleon Bonaparte", napoleon)
        assertCorrect("well, maybe Bonaparte", napoleon)
        assertCorrect("NAPOLEON!", napoleon)
        assertCorrect("napoleon bonaparte i think", napoleon)
    }

    func testRecognizerMisspellingWithinTolerance() {
        // "napolean" is one edit from "napoleon" and the answer is long
        // enough to earn a budget of two.
        assertCorrect("napolean", napoleon)
    }

    func testRejectsWrongAnswers() {
        assertIncorrect("Churchill", napoleon)
        assertIncorrect("I have no clue, Caesar maybe", napoleon)
    }

    func testShortAnswersGetNoEditSlack() {
        let rome = Question(
            id: "q-rome",
            prompt: "What city is the capital of Italy?",
            canonicalAnswer: "Rome",
            factOneLiner: "It has been a capital for well over two thousand years.",
            estimatedSeconds: 28
        )
        assertCorrect("Rome", rome)
        assertCorrect("uh, is it Rome?", rome)
        // One edit away, and must not pass.
        assertIncorrect("dome", rome)
        assertIncorrect("Rope", rome)
    }

    func testSpokenNumbersMatchDigits() {
        let planets = Question(
            id: "q-planets",
            prompt: "How many planets are in the solar system?",
            canonicalAnswer: "8",
            alternates: ["eight"],
            factOneLiner: "Pluto was reclassified as a dwarf planet in 2006.",
            estimatedSeconds: 26
        )
        assertCorrect("eight", planets)
        assertCorrect("I think it's eight", planets)
        assertCorrect("8", planets)
        assertIncorrect("nine", planets)
    }

    func testAccentsAndPunctuationAreFolded() {
        let question = Question(
            id: "q-beyonce",
            prompt: "Which singer released the album Lemonade?",
            canonicalAnswer: "Beyonce",
            alternates: ["Beyoncé"],
            factOneLiner: "It arrived as a surprise visual album in 2016.",
            estimatedSeconds: 30
        )
        assertCorrect("Beyoncé", question)
        assertCorrect("beyonce!", question)
    }

    func testUsesRecognizerAlternatives() {
        let verdict = AnswerGrader.grade(
            candidates: ["nap-oh-lee-on", "Napoleon"],
            question: napoleon
        )
        XCTAssertEqual(verdict, .correct(matched: "Napoleon"))
    }

    func testEmptyTranscriptIsNoSpeech() {
        XCTAssertEqual(AnswerGrader.grade(candidates: [], question: napoleon), .noSpeech)
        XCTAssertEqual(AnswerGrader.grade(candidates: ["", "   "], question: napoleon), .noSpeech)
    }

    func testMultiWordAnswerToleratesSurroundingWords() {
        let question = Question(
            id: "q-ww2",
            prompt: "In which year did the Second World War end?",
            canonicalAnswer: "1945",
            factOneLiner: "The war in the Pacific ended months after the war in Europe.",
            estimatedSeconds: 26
        )
        assertCorrect("I want to say 1945", question)
        assertIncorrect("1944", question)
    }
}
