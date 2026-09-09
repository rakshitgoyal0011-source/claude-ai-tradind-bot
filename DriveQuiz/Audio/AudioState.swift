import Foundation

/// Every state the audio stack can be in. Exactly one owner drives this,
/// so a late callback can never start the microphone behind the game's back.
enum AudioState: String, Equatable {
    case idle
    case speaking
    case listening
    /// Driver said "pause". Only resume and stop are heard.
    case paused
    /// A phone call or Siri took the session away from us.
    case interrupted
    case stopped

    var legalNext: Set<AudioState> {
        switch self {
        case .idle:        return [.speaking, .stopped]
        case .speaking:    return [.listening, .speaking, .paused, .interrupted, .stopped]
        case .listening:   return [.speaking, .paused, .interrupted, .stopped]
        case .paused:      return [.speaking, .listening, .interrupted, .stopped]
        case .interrupted: return [.speaking, .stopped, .idle]
        case .stopped:     return [.idle]
        }
    }

    func canTransition(to next: AudioState) -> Bool {
        self == next || legalNext.contains(next)
    }
}
