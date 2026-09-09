import XCTest
@testable import DriveQuizKit

final class PackPlannerTests: XCTestCase {

    private func pack(count: Int, seconds: TimeInterval) -> QuestionPack {
        QuestionPack(
            id: "test",
            theme: "Test",
            questions: (0..<count).map {
                Question(
                    id: "q\($0)",
                    prompt: "Prompt \($0)",
                    canonicalAnswer: "Answer \($0)",
                    factOneLiner: "Fact \($0)",
                    estimatedSeconds: seconds
                )
            }
        )
    }

    func testFitsQuestionsInsideBudgetLeavingRoomForIntroAndClosing() {
        // 600s drive, minus 12s intro and 25s closing, leaves 563s.
        let plan = PackPlanner.plan(packs: [pack(count: 40, seconds: 30)], availableSeconds: 600)
        XCTAssertEqual(plan.questions.count, 18)
        XCTAssertLessThanOrEqual(
            plan.estimatedContentSeconds,
            600 - PackPlanner.introSeconds - PackPlanner.closingSeconds
        )
    }

    func testShortDriveStillPlansSomething() {
        let plan = PackPlanner.plan(packs: [pack(count: 20, seconds: 30)], availableSeconds: 180)
        XCTAssertFalse(plan.questions.isEmpty)
    }

    func testDriveTooShortForAnyQuestionPlansNone() {
        let plan = PackPlanner.plan(packs: [pack(count: 20, seconds: 30)], availableSeconds: 30)
        XCTAssertTrue(plan.questions.isEmpty)
    }

    func testFlagsRunningOutOfQuestions() {
        // One 30s question against an hour of driving.
        let plan = PackPlanner.plan(packs: [pack(count: 1, seconds: 30)], availableSeconds: 3600)
        XCTAssertTrue(plan.ranOutOfQuestions)
        XCTAssertEqual(plan.questions.count, 1)
    }

    func testSameSeedPlansSameQuestions() {
        let packs = [pack(count: 30, seconds: 30)]
        let a = PackPlanner.plan(packs: packs, availableSeconds: 600, seed: 42)
        let b = PackPlanner.plan(packs: packs, availableSeconds: 600, seed: 42)
        let c = PackPlanner.plan(packs: packs, availableSeconds: 600, seed: 7)
        XCTAssertEqual(a.questions.map(\.id), b.questions.map(\.id))
        XCTAssertNotEqual(a.questions.map(\.id), c.questions.map(\.id))
    }

    func testDoesNotStartAQuestionItCannotFinish() {
        let question = Question(
            id: "q", prompt: "p", canonicalAnswer: "a",
            factOneLiner: "f", estimatedSeconds: 30
        )
        // 30s question plus 25s closing needs 55s of runway.
        XCTAssertTrue(PackPlanner.shouldStartNextQuestion(remainingSeconds: 60, question: question))
        XCTAssertFalse(PackPlanner.shouldStartNextQuestion(remainingSeconds: 50, question: question))
        XCTAssertFalse(PackPlanner.shouldStartNextQuestion(remainingSeconds: 20, question: question))
    }
}
