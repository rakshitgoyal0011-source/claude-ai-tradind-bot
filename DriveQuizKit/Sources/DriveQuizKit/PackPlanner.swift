import Foundation

/// Where the session length came from. Changes the spoken intro, because
/// an ETA-backed drive cannot honestly promise a question count.
public enum SessionMode: String, Sendable, Equatable {
    case manualMinutes
    case estimatedArrival
}

public struct SessionPlan: Sendable, Equatable {
    public let theme: String
    public let mode: SessionMode
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
    /// - Parameter contingency: multiplies the question budget without
    ///   changing the drive length. An ETA can stretch in traffic, so plan
    ///   past it and let the live clock decide when to stop. The plan is a
    ///   queue, not a promise.
    /// - Parameter history: what this driver has already been asked. Fresh
    ///   questions are always preferred; previously asked ones come back only
    ///   once the unseen pool is exhausted, oldest first.
    public static func plan(
        packs: [QuestionPack],
        availableSeconds: TimeInterval,
        mode: SessionMode = .manualMinutes,
        contingency: Double = 1.0,
        history: QuestionHistory = .empty,
        cooldown: TimeInterval = PlayerProgress.defaultCooldown,
        now: Date = Date(),
        seed: UInt64 = 0
    ) -> SessionPlan {
        let theme = packs.count == 1 ? (packs.first?.theme ?? "Mixed") : "Mixed"
        // Questions stop at the wrap-up threshold, not at the summary, so
        // anything planned into that last 90 seconds would never be asked.
        let baseBudget = availableSeconds - introSeconds - wrapUpThreshold
        let budget = baseBudget * max(1.0, contingency)

        guard baseBudget > 0 else {
            return SessionPlan(
                theme: theme,
                mode: mode,
                questions: [],
                plannedDuration: availableSeconds,
                estimatedContentSeconds: 0,
                ranOutOfQuestions: false
            )
        }

        var generator = SeededGenerator(seed: seed)
        let pool = orderByFreshness(
            packs.flatMap(\.questions).shuffled(using: &generator),
            history: history,
            cooldown: cooldown,
            now: now
        )

        var chosen: [Question] = []
        var used: TimeInterval = 0

        for question in pool where used + question.estimatedSeconds <= budget {
            chosen.append(question)
            used += question.estimatedSeconds
        }

        // Measured against the real drive, not the padded queue.
        let ranOut = chosen.count == pool.count
            && (baseBudget - min(used, baseBudget)) > 45

        return SessionPlan(
            theme: theme,
            mode: mode,
            questions: chosen,
            plannedDuration: availableSeconds,
            estimatedContentSeconds: used,
            ranOutOfQuestions: ranOut
        )
    }

    /// Unseen questions first in shuffled order, then previously asked ones
    /// oldest first. The incoming order breaks ties, so a caller that shuffled
    /// with a seed still gets a deterministic result.
    static func orderByFreshness(
        _ questions: [Question],
        history: QuestionHistory,
        cooldown: TimeInterval,
        now: Date
    ) -> [Question] {
        questions
            .enumerated()
            .map { index, question -> (rank: Int, seenAt: TimeInterval, tie: Int, question: Question) in
                let rank = history.freshnessRank(for: question.id, now: now, cooldown: cooldown)
                // Unseen questions share a key so the shuffle alone orders them.
                let seenAt = history.lastAsked(for: question.id)?.timeIntervalSince1970 ?? 0
                return (rank, seenAt, index, question)
            }
            .sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                if $0.seenAt != $1.seenAt { return $0.seenAt < $1.seenAt }
                return $0.tie < $1.tie
            }
            .map(\.question)
    }

    /// Gate checked before every question, using the live clock rather than
    /// the plan, so a slow round does not push us past the destination.
    ///
    /// Two conditions. Stop asking once the drive is inside the wrap-up
    /// threshold, and never start a question so long that the closing
    /// summary would be cut off.
    public static func shouldStartNextQuestion(
        remainingSeconds: TimeInterval,
        question: Question
    ) -> Bool {
        remainingSeconds >= wrapUpThreshold
            && remainingSeconds - question.estimatedSeconds >= closingSeconds
    }
}
