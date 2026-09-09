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

    /// A single-word command must lead the utterance, so "the answer is a
    /// stop sign" is graded as an answer rather than obeyed as a command.
    /// Multi-word phrases are distinctive enough to match anywhere.
    public static func command(in raw: String, allowing allowed: Set<VoiceCommand>? = nil) -> VoiceCommand? {
        let tokens = TextNormalizer.commandTokens(raw)
        guard !tokens.isEmpty else { return nil }

        for (command, variants) in phrases {
            if let allowed, !allowed.contains(command) { continue }
            for phrase in variants where matches(tokens: tokens, phrase: phrase) {
                return command
            }
        }
        return nil
    }

    static func matches(tokens: [String], phrase: [String]) -> Bool {
        guard phrase.count <= tokens.count else { return false }

        if Array(tokens.prefix(phrase.count)) == phrase { return true }
        guard phrase.count >= 2 else { return false }

        for start in 0...(tokens.count - phrase.count) {
            if Array(tokens[start..<(start + phrase.count)]) == phrase { return true }
        }
        return false
    }
}
