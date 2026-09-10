import Foundation

/// Decides what to do when the game has gone quiet.
///
/// Every defect found in this app so far has presented the same way: not a
/// crash, not an error, just silence. A driver who cannot look at the screen
/// has no way to tell a thinking pause from a dead app. This is the last line
/// of defence, and it is deliberately dumb: it does not care why the game went
/// quiet, only that it did.
public enum SilenceWatchdog {

    /// Longer than any legitimate gap. The worst honest case is a listen
    /// window plus the settle delay plus a long fact, comfortably under 25s.
    public static let nudgeAfter: TimeInterval = 30
    /// By here the loop is not coming back on its own.
    public static let giveUpAfter: TimeInterval = 60

    public enum Action: Equatable, Sendable {
        /// Normal. Either recently spoken, or legitimately quiet.
        case wait
        /// Try to unstick whatever is blocking, usually an in-flight listen.
        case nudge
        /// Stop pretending. End the drive and say so.
        case giveUp
    }

    /// - Parameters:
    ///   - silentFor: seconds since the game last said anything.
    ///   - isPaused: the driver asked for quiet, so silence is correct.
    ///   - isInterrupted: a call or Siri owns the audio, so we cannot speak.
    public static func action(
        silentFor: TimeInterval,
        isPaused: Bool,
        isInterrupted: Bool
    ) -> Action {
        // Both of these are silence the driver asked for or can hear the
        // reason for. Never act on them.
        guard !isPaused, !isInterrupted else { return .wait }

        if silentFor >= giveUpAfter { return .giveUp }
        if silentFor >= nudgeAfter { return .nudge }
        return .wait
    }
}
