import Foundation

public enum Levenshtein {

    /// Classic two-row edit distance.
    public static func distance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)

        for i in 1...lhs.count {
            current[0] = i
            for j in 1...rhs.count {
                let substitution = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + substitution
                )
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }

    public static func distance(_ lhs: String, _ rhs: String) -> Int {
        distance(Array(lhs), Array(rhs))
    }

    /// Bails out early when the length gap alone exceeds the budget.
    public static func isWithin(_ tolerance: Int, _ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        if tolerance <= 0 { return false }
        if abs(lhs.count - rhs.count) > tolerance { return false }
        return distance(lhs, rhs) <= tolerance
    }
}
