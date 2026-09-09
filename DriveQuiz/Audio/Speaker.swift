import AVFoundation

/// Async wrapper over AVSpeechSynthesizer. `speak` returns only once the
/// utterance has actually finished, which is what lets the game guarantee
/// that the microphone never opens while we are still talking.
@MainActor
final class Speaker: NSObject {

    private let synthesizer = AVSpeechSynthesizer()
    private var pending: CheckedContinuation<Void, Never>?

    /// Slightly slower than default. Road noise eats consonants.
    var rate: Float = 0.50
    var voiceLanguage = "en-US"

    override init() {
        super.init()
        synthesizer.delegate = self
        // Honour the session we configured rather than a private one.
        synthesizer.usesApplicationAudioSession = true
    }

    func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        resumePending()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pending = continuation
            let utterance = AVSpeechUtterance(string: trimmed)
            utterance.rate = rate
            utterance.postUtteranceDelay = 0.1
            utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        resumePending()
    }

    /// Resuming twice traps, so every path funnels through here.
    private func resumePending() {
        guard let continuation = pending else { return }
        pending = nil
        continuation.resume()
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.resumePending() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.resumePending() }
    }
}
