import Foundation

public enum VoiceCommand: String, Sendable, CaseIterable {
    case repeatQuestion
    case skip
    case pause
    case resume
    case howManyLeft
    case stop
}

public enum CommandMatcher {

    /// Order matters. Longer, more specific phrases are checked first so
    /// "how many questions left" does not fall through to a bare match.
    static let phrases: [(VoiceCommand, [[String]])] = [
        (.howManyLeft, [
            ["how", "many", "questions", "left"],
            ["how", "many", "are", "left"],
            ["how", "many", "more"],
            ["how", "many", "left"],
            ["how", "much", "longer"],
            ["how", "much", "time"],
            ["how", "long", "left"],
            ["how", "far", "along"]
        ]),
        (.repeatQuestion, [
            ["can", "you", "repeat", "that"],
            ["can", "you", "repeat"],
            ["say", "that", "again"],
            ["say", "again"],
            ["one", "more", "time"],
            ["what", "was", "that"],
            ["come", "again"],
            ["repeat", "that"],
            ["repeat"]
        ]),
        (.resume, [
            ["keep", "going"],
            ["start", "again"],
            ["carry", "on"],
            ["go", "on"],
            ["im", "back"],
            ["unpause"],
            ["resume"],
            ["continue"]
        ]),
        (.skip, [
            ["next", "question"],
            ["i", "dont", "know"],
            ["no", "idea"],
            ["skip", "this", "one"],
            ["skip", "this"],
            ["skip", "it"],
            ["dunno"],
            ["skip"],
            ["pass"],
            ["next"]
        ]),
        (.pause, [
            ["pause", "the", "game"],
            ["hold", "on"],
            ["hang", "on"],
            ["pause"]
        ]),
        (.stop, [
            ["stop", "the", "game"],
            ["thats", "enough"],
            ["im", "done"],
            ["end", "game"],
            ["stop"],
            ["quit"],
            ["exit"]
        ])
    ]

    /// How many words may trail a command before it stops counting as one.
    ///
    /// A command must lead the utterance, so "the answer is a stop sign" is
    /// graded rather than obeyed. The trailing budget is what stops a command
    /// swallowing an answer that follows it, and it is tightest where being
    /// wrong costs most:
    ///
    /// - stop ends the drive, so it must be said and nothing else.
    /// - skip throws away whatever guess came after it, so "I don't know,
    ///   maybe Napoleon" is graded instead of skipped.
    /// - the rest are recoverable, and a driver saying "hold on a second"
    ///   plainly means it.
    static func trailingBudget(for command: VoiceCommand) -> Int {
        switch command {
        case .stop, .skip: return 0
        case .pause, .repeatQuestion, .howManyLeft, .resume: return 2
        }
    }

    public static func command(in raw: String, allowing allowed: Set<VoiceCommand>? = nil) -> VoiceCommand? {
        let tokens = TextNormalizer.commandTokens(raw)
        guard !tokens.isEmpty else { return nil }

        for (command, variants) in phrases {
            if let allowed, !allowed.contains(command) { continue }
            let budget = trailingBudget(for: command)
            for phrase in variants
            where matches(tokens: tokens, phrase: phrase, trailingBudget: budget) {
                return command
            }
        }
        return nil
    }

    static func matches(tokens: [String], phrase: [String], trailingBudget: Int) -> Bool {
        guard phrase.count <= tokens.count else { return false }
        guard tokens.count - phrase.count <= trailingBudget else { return false }
        return Array(tokens.prefix(phrase.count)) == phrase
    }
}
