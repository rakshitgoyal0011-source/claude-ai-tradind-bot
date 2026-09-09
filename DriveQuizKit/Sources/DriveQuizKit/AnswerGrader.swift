import Foundation

public enum Verdict: Equatable, Sendable {
    /// Matched an accepted answer. Carries the accepted form that hit.
    case correct(matched: String)
    case incorrect
    /// Nothing usable came back from the recognizer.
    case noSpeech
}

public enum AnswerGrader {

    /// Edit budget scales with answer length. Short answers get zero slack,
    /// because one edit turns "Rome" into "dome".
    public static func maxEditDistance(forNormalizedAnswer answer: String) -> Int {
        switch answer.count {
        case 0...4: return 0
        case 5...7: return 1
        case 8...11: return 2
        default: return 3
        }
    }

    /// Grades every recognizer candidate against every accepted answer.
    /// Pass the full alternatives list, not just the best transcript: the
    /// right answer is often the second candidate.
    public static func grade(candidates: [String], question: Question) -> Verdict {
        let usable = candidates
            .map { TextNormalizer.normalizeTokens($0) }
            .filter { !$0.isEmpty }

        guard !usable.isEmpty else { return .noSpeech }

        for accepted in question.acceptedAnswers {
            let acceptedTokens = TextNormalizer.normalizeTokens(accepted)
            guard !acceptedTokens.isEmpty else { continue }

            let tolerance = question.editTolerance
                ?? maxEditDistance(forNormalizedAnswer: acceptedTokens.joined(separator: " "))

            for candidateTokens in usable {
                if matches(
                    transcript: candidateTokens,
                    accepted: acceptedTokens,
                    tolerance: tolerance
                ) {
                    return .correct(matched: accepted)
                }
            }
        }
        return .incorrect
    }

    /// Slides a window the width of the accepted answer across the transcript,
    /// so extra words on either side do not block a match.
    static func matches(transcript: [String], accepted: [String], tolerance: Int) -> Bool {
        let acceptedText = accepted.joined(separator: " ")
        let width = accepted.count

        guard transcript.count >= width else {
            return Levenshtein.isWithin(
                tolerance,
                transcript.joined(separator: " "),
                acceptedText
            )
        }

        for start in 0...(transcript.count - width) {
            let window = transcript[start..<(start + width)].joined(separator: " ")
            if Levenshtein.isWithin(tolerance, window, acceptedText) { return true }
        }
        return false
    }
}
