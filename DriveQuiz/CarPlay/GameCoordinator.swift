import Foundation

/// Shared handle on the running game.
///
/// CarPlay scenes are created by UIKit, entirely outside the SwiftUI view
/// tree, so the two need a meeting point. This is that meeting point and
/// nothing more: it holds no logic and owns no state of its own.
@MainActor
final class GameCoordinator {

    static let shared = GameCoordinator()

    /// Weak, so a finished game deallocates even if nobody detaches.
    /// Nothing observes this; the Now Playing ticker polls it.
    private(set) weak var engine: GameEngine?

    private init() {}

    func attach(_ engine: GameEngine) {
        self.engine = engine
    }

    func detach() {
        self.engine = nil
    }

    var isRunning: Bool { engine?.card.isRunning ?? false }
}
