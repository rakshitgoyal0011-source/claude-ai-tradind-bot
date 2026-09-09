import AVFoundation
import Observation
import Speech

/// The single owner of AVAudioSession. Nothing else in the app touches it.
///
/// Speaking and listening are strictly serialised in Phase 1. There is no
/// barge-in, because the microphone would otherwise pick up our own speech
/// coming back through the car stereo.
@MainActor
@Observable
final class AudioSessionController {

    private(set) var state: AudioState = .idle

    let speaker = Speaker()
    let listener = Listener()

    /// Fires when a call or Siri takes the session. Bool is true when the
    /// system says we may resume.
    var onInterruption: ((_ ended: Bool, _ mayResume: Bool) -> Void)?

    private var observers: [NSObjectProtocol] = []

    // MARK: - Permissions

    enum PermissionResult { case granted, deniedMicrophone, deniedSpeech }

    static func requestPermissions() async -> PermissionResult {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return .deniedSpeech }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        return micGranted ? .granted : .deniedMicrophone
    }

    // MARK: - Session lifecycle

    /// Configured once and held for the whole drive. Switching category per
    /// turn causes audible route changes in the car.
    func activate() throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playAndRecord,
            // Designed for apps that speak prompts via text to speech.
            mode: .voicePrompt,
            options: [
                // Lower music and podcasts while we talk.
                .duckOthers,
                // Phone in a cradle with no car connection.
                .defaultToSpeaker,
                // Output over the car stereo at full quality. Deliberately
                // NOT .allowBluetooth: requesting a Bluetooth microphone
                // drops the head unit into the hands-free profile, which
                // makes everything, including our own voice, sound worse.
                .allowBluetoothA2DP
            ]
        )
        try session.setActive(true)
        observeInterruptions()
        transition(to: .idle)
    }

    func deactivate() {
        speaker.stop()
        listener.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        // Let music come back cleanly instead of staying ducked.
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
        transition(to: .stopped)
    }

    // MARK: - Serialised speak and listen

    func say(_ text: String) async {
        guard state != .stopped, state != .interrupted else { return }
        transition(to: .speaking)
        await speaker.speak(text)
    }

    func hear(timeout: TimeInterval = 8, hints: [String] = []) async -> Transcript {
        guard state != .stopped, state != .interrupted else { return .empty }
        transition(to: .listening)

        // Let the output route settle so the tail of our own speech does not
        // land in the first buffer of the recording.
        try? await Task.sleep(for: .milliseconds(250))

        do {
            return try await listener.listen(timeout: timeout, hints: hints)
        } catch {
            return .empty
        }
    }

    func enterPause() { transition(to: .paused) }

    // MARK: - Interruptions

    private func observeInterruptions() {
        guard observers.isEmpty else { return }

        let observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleInterruption(note) }
        }
        observers.append(observer)
    }

    private func handleInterruption(_ note: Notification) {
        guard
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            // The system has already taken the session. Tear down and stop
            // the clock so the driver does not lose game time to a call.
            speaker.stop()
            listener.cancel()
            transition(to: .interrupted)
            onInterruption?(false, false)

        case .ended:
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let mayResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                .contains(.shouldResume)
            if mayResume {
                try? AVAudioSession.sharedInstance().setActive(true)
                transition(to: .idle)
            }
            onInterruption?(true, mayResume)

        @unknown default:
            break
        }
    }

    // MARK: - State

    private func transition(to next: AudioState) {
        guard state.canTransition(to: next) else {
            assertionFailure("illegal audio transition \(state.rawValue) -> \(next.rawValue)")
            return
        }
        state = next
    }
}
