import Foundation
import MediaPlayer
import DriveQuizKit

/// Feeds the car screen and the lock screen, and routes their buttons back
/// into the voice loop.
///
/// The car never shows the question. Constraint two says no question may be
/// answerable from a screen, and a prompt on the dash would be exactly that.
/// Only the session name, the score and the day count go out.
@MainActor
final class NowPlayingController {

    static let shared = NowPlayingController()

    private var ticker: Task<Void, Never>?
    private var lastPublished: GameEngine.NowPlayingSnapshot?
    private var commandsRegistered = false

    private init() {}

    // MARK: - Lifecycle

    func activate() {
        guard FeatureFlags.carPlayEnabled else { return }
        registerCommands()
        startTicking()
    }

    func deactivate() {
        ticker?.cancel()
        ticker = nil
        lastPublished = nil
        setCommandsEnabled(false)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// One second is enough for a progress bar and cheap enough to leave
    /// running for a whole drive.
    private func startTicking() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.publish()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func publish() {
        guard let engine = GameCoordinator.shared.engine, engine.card.isRunning else {
            // The drive ended, by arrival or by the stop button. Clear the
            // car screen and stop ticking; the next game calls activate again.
            deactivate()
            return
        }

        let snapshot = engine.nowPlayingSnapshot
        guard snapshot != lastPublished else { return }
        if lastPublished == nil { setCommandsEnabled(true) }
        lastPublished = snapshot

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyArtist: snapshot.scoreLine,
            MPMediaItemPropertyPlaybackDuration: snapshot.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: false
        ]
        if let dayLine = snapshot.dayLine {
            info[MPMediaItemPropertyAlbumTitle] = dayLine
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote commands

    /// Transport controls map onto the voice vocabulary, so a button and a
    /// spoken word take exactly the same path through the game.
    ///
    /// These handlers are not guaranteed to run on the main actor, so each
    /// one hops before touching any game state and reports success without
    /// waiting. Whether a control does anything is expressed by enabling and
    /// disabling the commands in `publish`, not by the return value.
    private func registerCommands() {
        guard !commandsRegistered else { return }
        commandsRegistered = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { _ in Self.deliver(.resume) }
        center.pauseCommand.addTarget { _ in Self.deliver(.pause) }
        center.togglePlayPauseCommand.addTarget { _ in Self.deliverToggle() }
        center.nextTrackCommand.addTarget { _ in Self.deliver(.skip) }
        // Going back means hearing the question again, not replaying audio.
        center.previousTrackCommand.addTarget { _ in Self.deliver(.repeatQuestion) }
        center.stopCommand.addTarget { _ in Self.deliver(.stop) }

        [center.seekForwardCommand, center.seekBackwardCommand,
         center.changePlaybackPositionCommand, center.skipForwardCommand,
         center.skipBackwardCommand].forEach { $0.isEnabled = false }

        setCommandsEnabled(false)
    }

    private nonisolated static func deliver(
        _ command: VoiceCommand
    ) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor in
            GameCoordinator.shared.engine?.handleRemoteCommand(command)
        }
        return .success
    }

    private nonisolated static func deliverToggle() -> MPRemoteCommandHandlerStatus {
        Task { @MainActor in
            guard let engine = GameCoordinator.shared.engine else { return }
            engine.handleRemoteCommand(engine.card.isPaused ? .resume : .pause)
        }
        return .success
    }

    private func setCommandsEnabled(_ enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
         center.nextTrackCommand, center.previousTrackCommand,
         center.stopCommand].forEach { $0.isEnabled = enabled }
    }
}
