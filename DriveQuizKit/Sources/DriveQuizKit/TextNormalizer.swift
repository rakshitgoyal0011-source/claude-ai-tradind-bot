import Foundation

/// Turns messy speech-to-text output into a comparable token list.
///
/// Both sides of a comparison must go through this, so "Uh, is it Napoleon?"
/// and "Napoleon" collapse onto the same tokens.
public enum TextNormalizer {

    /// Dropped anywhere in the utterance.
    public static let fillerWords: Set<String> = [
        "uh", "uhh", "um", "umm", "erm", "er", "ah", "ahh", "aah",
        "hmm", "hm", "mm", "mmm", "like", "well", "so", "okay", "ok",
        "yeah", "yep", "eh", "oh"
    ]

    /// Dropped anywhere, after lead-ins are removed.
    public static let articles: Set<String> = ["a", "an", "the"]

    /// Dropped only from the front, longest first.
    static let leadInPhrases: [[String]] = [
        ["i", "think", "the", "answer", "is"],
        ["i", "think", "it", "is"],
        ["i", "think", "its"],
        ["i", "am", "going", "to", "say"],
        ["im", "going", "to", "say"],
        ["i", "would", "say"],
        ["i", "wanna", "say"],
        ["i", "want", "to", "say"],
        ["let", "me", "think"],
        ["my", "guess", "is"],
        ["the", "answer", "is"],
        ["answer", "is"],
        ["i", "think"],
        ["i", "guess"],
        ["id", "say"],
        ["is", "it"],
        ["was", "it"],
        ["it", "is"],
        ["its"],
        ["that", "is"],
        ["thats"],
        ["maybe"],
        ["probably"],
        ["definitely"],
        ["obviously"]
    ]

    /// Spoken numbers become digits so "eight" and "8" compare equal.
    static let numberWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
        "ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13",
        "fourteen": "14", "fifteen": "15", "sixteen": "16",
        "seventeen": "17", "eighteen": "18", "nineteen": "19",
        "twenty": "20", "thirty": "30", "forty": "40", "fifty": "50",
        "sixty": "60", "seventy": "70", "eighty": "80", "ninety": "90"
    ]

    /// Lowercase, fold accents, drop apostrophes, split on anything that is
    /// not a letter or digit. Spoken numbers are left alone here.
    public static func tokenize(_ raw: String) -> [String] {
        let folded = raw
            .lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: "'", with: "")

        let cleaned = String(folded.map { $0.isLetter || $0.isNumber ? $0 : " " })

        return cleaned
            .split(separator: " ")
            .map { String($0) }
    }

    /// Tokens for command detection: fillers removed, but lead-ins, articles
    /// and spoken numbers left intact.
    ///
    /// Command matching must NOT strip lead-ins. Stripping "the answer is"
    /// from "the answer is a stop sign" leaves "stop" leading the utterance,
    /// and the game would quit instead of grading the answer.
    public static func commandTokens(_ raw: String) -> [String] {
        let base = tokenize(raw)
        guard !base.isEmpty else { return [] }
        let filtered = base.filter { !fillerWords.contains($0) }
        return filtered.isEmpty ? base : filtered
    }

    /// Full normalization. Never returns an empty list for non-empty input,
    /// so a one-word answer like "the" or "so" survives its own filters.
    public static func normalizeTokens(_ raw: String) -> [String] {
        let base = tokenize(raw).map { numberWords[$0] ?? $0 }
        guard !base.isEmpty else { return [] }

        var tokens = base.filter { !fillerWords.contains($0) }
        if tokens.isEmpty { tokens = base }

        let deLed = stripLeadIns(tokens)
        tokens = deLed.isEmpty ? tokens : deLed

        let deArticled = tokens.filter { !articles.contains($0) }
        return deArticled.isEmpty ? tokens : deArticled
    }

    public static func normalize(_ raw: String) -> String {
        normalizeTokens(raw).joined(separator: " ")
    }

    /// Repeatedly removes the longest matching lead-in from the front.
    static func stripLeadIns(_ tokens: [String]) -> [String] {
        var current = tokens
        var changed = true

        while changed && !current.isEmpty {
            changed = false
            for phrase in leadInPhrases where phrase.count < current.count {
                if Array(current.prefix(phrase.count)) == phrase {
                    current = Array(current.dropFirst(phrase.count))
                    changed = true
                    break
                }
            }
        }
        return current
    }
}
