import Foundation

public struct SessionPlan: Sendable, Equatable {
    public let theme: String
    public let questions: [Question]
    public let plannedDuration: TimeInterval
    /// Sum of estimatedSeconds for the chosen questions.
    public let estimatedContentSeconds: TimeInterval
    /// True when the packs ran dry before the drive time was filled.
    public let ranOutOfQuestions: Bool
}

public enum PackPlanner {

    /// Spoken welcome before the first question.
    public static let introSeconds: TimeInterval = 12
    /// Score, streak, and sign-off at the end.
    public static let closingSeconds: TimeInterval = 25
    /// Wrap up once the drive drops below this, per the brief.
    public static let wrapUpThreshold: TimeInterval = 90

    /// Fills the available time with whole questions. Never starts a question
    /// it cannot finish before the closing summary is due.
    public static func plan(
        packs: [QuestionPack],
        availableSeconds: TimeInterval,
        seed: UInt64 = 0
    ) -> SessionPlan {
        let theme = packs.count == 1 ? (packs.first?.theme ?? "Mixed") : "Mixed"
        let budget = availableSeconds - introSeconds - closingSeconds

        guard budget > 0 else {
            return SessionPlan(
                theme: theme,
                questions: [],
                plannedDuration: availableSeconds,
                estimatedContentSeconds: 0,
                ranOutOfQuestions: false
            )
        }

        var generator = SeededGenerator(seed: seed)
        let pool = packs.flatMap(\.questions).shuffled(using: &generator)

        var chosen: [Question] = []
        var used: TimeInterval = 0

        for question in pool where used + question.estimatedSeconds <= budget {
            chosen.append(question)
            used += question.estimatedSeconds
        }

        // Ran dry when every question was used and real time is still left.
        let ranOut = chosen.count == pool.count && (budget - used) > 45

        return SessionPlan(
            theme: theme,
            questions: chosen,
            plannedDuration: availableSeconds,
            estimatedContentSeconds: used,
            ranOutOfQuestions: ranOut
        )
    }

    /// Gate checked before every question, using the live clock rather than
    /// the plan, so a slow round does not push us past the destination.
    public static func shouldStartNextQuestion(
        remainingSeconds: TimeInterval,
        question: Question
    ) -> Bool {
        remainingSeconds - question.estimatedSeconds >= closingSeconds
    }
}
