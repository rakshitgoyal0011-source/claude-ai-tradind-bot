import Foundation

public enum Difficulty: String, Codable, Sendable, CaseIterable {
    case easy, medium, hard
}

/// A single spoken question. Nothing here may require a screen to answer.
public struct Question: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    /// Spoken aloud verbatim.
    public let prompt: String
    public let canonicalAnswer: String
    /// Other accepted spoken forms, graded with the same fuzzy rules.
    public let alternates: [String]
    /// One sentence spoken after the verdict.
    public let factOneLiner: String
    public let difficulty: Difficulty
    /// Whole-turn budget: prompt, listen window, verdict, fact, and the gaps.
    public let estimatedSeconds: TimeInterval
    /// Optional per-question override of the length-derived edit tolerance.
    public let editTolerance: Int?

    public init(
        id: String,
        prompt: String,
        canonicalAnswer: String,
        alternates: [String] = [],
        factOneLiner: String,
        difficulty: Difficulty = .medium,
        estimatedSeconds: TimeInterval = 30,
        editTolerance: Int? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.canonicalAnswer = canonicalAnswer
        self.alternates = alternates
        self.factOneLiner = factOneLiner
        self.difficulty = difficulty
        self.estimatedSeconds = estimatedSeconds
        self.editTolerance = editTolerance
    }

    private enum CodingKeys: String, CodingKey {
        case id, prompt, canonicalAnswer, alternates, factOneLiner
        case difficulty, estimatedSeconds, editTolerance
    }

    /// Decodes leniently on everything that has a sensible default.
    ///
    /// Packs are hand-authored JSON, and PackLoader skips a pack it cannot
    /// parse. Making `alternates` a required key would let one missing line
    /// silently cost the driver twenty questions.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        prompt = try container.decode(String.self, forKey: .prompt)
        canonicalAnswer = try container.decode(String.self, forKey: .canonicalAnswer)
        factOneLiner = try container.decode(String.self, forKey: .factOneLiner)
        alternates = try container.decodeIfPresent([String].self, forKey: .alternates) ?? []
        difficulty = try container.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .medium
        estimatedSeconds = try container
            .decodeIfPresent(TimeInterval.self, forKey: .estimatedSeconds) ?? 30
        editTolerance = try container.decodeIfPresent(Int.self, forKey: .editTolerance)
    }

    /// Canonical plus alternates, in grading order.
    public var acceptedAnswers: [String] { [canonicalAnswer] + alternates }

    /// Fed to the recognizer as contextual strings to bias proper nouns.
    public var recognitionHints: [String] { acceptedAnswers }
}

public struct QuestionPack: Codable, Identifiable, Sendable {
    public let id: String
    /// Shown on the session card and spoken in the intro.
    public let theme: String
    public let questions: [Question]

    public init(id: String, theme: String, questions: [Question]) {
        self.id = id
        self.theme = theme
        self.questions = questions
    }
}
