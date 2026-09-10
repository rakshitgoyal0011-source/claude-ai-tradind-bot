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

    func testFitsQuestionsInsideBudgetLeavingRoomForIntroAndWrapUp() {
        // 600s drive, minus 12s intro and the 90s wrap-up threshold, leaves
        // 498s, which is 16 whole 30s questions.
        let plan = PackPlanner.plan(packs: [pack(count: 40, seconds: 30)], availableSeconds: 600)
        XCTAssertEqual(plan.questions.count, 16)
        XCTAssertLessThanOrEqual(
            plan.estimatedContentSeconds,
            600 - PackPlanner.introSeconds - PackPlanner.wrapUpThreshold
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

    func testStopsAskingInsideTheWrapUpThreshold() {
        let question = Question(
            id: "q", prompt: "p", canonicalAnswer: "a",
            factOneLiner: "f", estimatedSeconds: 30
        )
        XCTAssertTrue(PackPlanner.shouldStartNextQuestion(remainingSeconds: 120, question: question))
        // Exactly at the threshold is still fair game.
        XCTAssertTrue(PackPlanner.shouldStartNextQuestion(remainingSeconds: 90, question: question))
        XCTAssertFalse(PackPlanner.shouldStartNextQuestion(remainingSeconds: 89, question: question))
        XCTAssertFalse(PackPlanner.shouldStartNextQuestion(remainingSeconds: 60, question: question))
    }

    func testDoesNotStartALongQuestionThatWouldCutOffTheSummary() {
        let long = Question(
            id: "long", prompt: "p", canonicalAnswer: "a",
            factOneLiner: "f", estimatedSeconds: 80
        )
        // Past the wrap-up threshold, but 100 minus 80 leaves under 25s
        // for the closing summary.
        XCTAssertFalse(PackPlanner.shouldStartNextQuestion(remainingSeconds: 100, question: long))
        XCTAssertTrue(PackPlanner.shouldStartNextQuestion(remainingSeconds: 110, question: long))
    }

    func testModeIsCarriedOntoThePlan() {
        let packs = [pack(count: 20, seconds: 30)]
        XCTAssertEqual(
            PackPlanner.plan(packs: packs, availableSeconds: 600).mode,
            .manualMinutes
        )
        XCTAssertEqual(
            PackPlanner.plan(packs: packs, availableSeconds: 600, mode: .estimatedArrival).mode,
            .estimatedArrival
        )
    }

    func testContingencyQueuesPastTheEstimateWithoutChangingTheDrive() {
        let packs = [pack(count: 40, seconds: 30)]
        let exact = PackPlanner.plan(packs: packs, availableSeconds: 600)
        let padded = PackPlanner.plan(
            packs: packs,
            availableSeconds: 600,
            mode: .estimatedArrival,
            contingency: 1.3
        )
        // 498s base budget gives 16 questions, 647s padded gives 21.
        XCTAssertEqual(exact.questions.count, 16)
        XCTAssertEqual(padded.questions.count, 21)
        // The drive itself is unchanged. Only the queue grew.
        XCTAssertEqual(padded.plannedDuration, 600)
    }

    func testContingencyBelowOneIsIgnored() {
        let packs = [pack(count: 40, seconds: 30)]
        let plan = PackPlanner.plan(packs: packs, availableSeconds: 600, contingency: 0.5)
        XCTAssertEqual(plan.questions.count, 16)
    }

    func testRanOutIsMeasuredAgainstTheRealDriveNotThePaddedQueue() {
        // Ten 30s questions, padded queue, against an hour of driving.
        let plan = PackPlanner.plan(
            packs: [pack(count: 10, seconds: 30)],
            availableSeconds: 3600,
            mode: .estimatedArrival,
            contingency: 1.3
        )
        XCTAssertEqual(plan.questions.count, 10)
        XCTAssertTrue(plan.ranOutOfQuestions)
    }

    // MARK: - Don't-repeat ordering

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 86_400

    func testUnseenQuestionsComeFirst() {
        let questions = (0..<6).map {
            Question(id: "q\($0)", prompt: "p", canonicalAnswer: "a",
                     factOneLiner: "f", estimatedSeconds: 30)
        }
        var history = QuestionHistory.empty
        history.record(["q0", "q1", "q2"], at: now.addingTimeInterval(-1 * day))

        let ordered = PackPlanner.orderByFreshness(
            questions, history: history, cooldown: 14 * day, now: now
        )
        let firstThree = Set(ordered.prefix(3).map(\.id))
        XCTAssertEqual(firstThree, ["q3", "q4", "q5"])
    }

    func testPreviouslyAskedComeBackOldestFirst() {
        let questions = (0..<3).map {
            Question(id: "q\($0)", prompt: "p", canonicalAnswer: "a",
                     factOneLiner: "f", estimatedSeconds: 30)
        }
        var history = QuestionHistory.empty
        history.record(["q0"], at: now.addingTimeInterval(-1 * day))
        history.record(["q1"], at: now.addingTimeInterval(-40 * day))
        history.record(["q2"], at: now.addingTimeInterval(-20 * day))

        let ordered = PackPlanner.orderByFreshness(
            questions, history: history, cooldown: 14 * day, now: now
        )
        // q1 and q2 are past cooldown, oldest first. q0 is still recent.
        XCTAssertEqual(ordered.map(\.id), ["q1", "q2", "q0"])
    }

    func testAShortDrivePicksOnlyFreshQuestions() {
        let questions = (0..<10).map {
            Question(id: "q\($0)", prompt: "p", canonicalAnswer: "a",
                     factOneLiner: "f", estimatedSeconds: 30)
        }
        var history = QuestionHistory.empty
        history.record((0..<8).map { "q\($0)" }, at: now.addingTimeInterval(-1 * day))

        // 180s drive fits 2 questions, and both should be unseen.
        let plan = PackPlanner.plan(
            packs: [QuestionPack(id: "p", theme: "T", questions: questions)],
            availableSeconds: 180,
            history: history,
            now: now
        )
        XCTAssertEqual(Set(plan.questions.map(\.id)), ["q8", "q9"])
    }

    func testNoHistoryLeavesTheShuffleAlone() {
        let questions = (0..<5).map {
            Question(id: "q\($0)", prompt: "p", canonicalAnswer: "a",
                     factOneLiner: "f", estimatedSeconds: 30)
        }
        let ordered = PackPlanner.orderByFreshness(
            questions, history: .empty, cooldown: 14 * day, now: now
        )
        XCTAssertEqual(ordered.map(\.id), questions.map(\.id))
    }

    // MARK: - Multiple packs

    private func themed(_ id: String, _ theme: String, count: Int) -> QuestionPack {
        QuestionPack(
            id: id,
            theme: theme,
            questions: (0..<count).map {
                Question(id: "\(id)-\($0)", prompt: "p", canonicalAnswer: "a",
                         factOneLiner: "f", estimatedSeconds: 30)
            }
        )
    }

    func testASinglePackKeepsItsTheme() {
        let plan = PackPlanner.plan(
            packs: [themed("a", "Alpha", count: 20)],
            availableSeconds: 600
        )
        XCTAssertEqual(plan.theme, "Alpha")
    }

    func testSeveralPacksAreLabelledMixed() {
        let plan = PackPlanner.plan(
            packs: [themed("a", "Alpha", count: 20), themed("b", "Beta", count: 20)],
            availableSeconds: 600
        )
        XCTAssertEqual(plan.theme, "Mixed")
    }

    func testDrawsFromEveryPack() {
        // A long drive against two packs should reach into both.
        let plan = PackPlanner.plan(
            packs: [themed("a", "Alpha", count: 20), themed("b", "Beta", count: 20)],
            availableSeconds: 1800,
            seed: 99
        )
        let prefixes = Set(plan.questions.map { String($0.id.prefix(1)) })
        XCTAssertEqual(prefixes, ["a", "b"])
    }
}
