import Foundation

/// What the single static card is allowed to show. Deliberately tiny:
/// anything richer would invite a glance.
struct CardState: Equatable {
    var sessionName: String = "DriveQuiz"
    var score: Int = 0
    var asked: Int = 0
    var isRunning: Bool = false
    var isPaused: Bool = false

    var scoreLine: String { "\(score) of \(asked)" }
}

enum GamePhase: Equatable {
    case notStarted
    case running
    case paused
    case finished(summary: String)
}
