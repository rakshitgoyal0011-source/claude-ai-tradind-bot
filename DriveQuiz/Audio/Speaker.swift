import AVFoundation

/// Async wrapper over AVSpeechSynthesizer. `speak` returns only once the
/// utterance has actually finished, which is what lets the game guarantee
/// that the microphone never opens while we are still talking.
@MainActor
final class Speaker: NSObject {

    private let synthesizer = AVSpeechSynthesizer()
    private var pending: CheckedContinuation<Void, Never>?
    /// Which utterance the pending continuation belongs to. A delegate
    /// callback for anything else is stale and must be ignored, or it would
    /// resume a later utterance that has not finished speaking.
    private var pendingUtterance: AVSpeechUtterance?

    /// Below AVSpeechUtteranceDefaultSpeechRate, which is 0.5.
    /// Road noise eats consonants.
    var rate: Float = 0.46
    var voiceLanguage = "en-US"

    override init() {
        super.init()
        synthesizer.delegate = self
        // Honour the session we configured rather than a private one.
        synthesizer.usesApplicationAudioSession = true
    }

    /// - Parameter pauseBefore: silence held before the utterance starts.
    ///   Running a verdict, a fact and the next question together with no gap
    ///   turns the game into an interrogation. This is what the "gaps" in
    ///   Question.estimatedSeconds actually pay for.
    func speak(_ text: String, pauseBefore: TimeInterval = 0) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        resumePending()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = rate
        utterance.preUtteranceDelay = pauseBefore
        utterance.postUtteranceDelay = 0.1
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pending = continuation
            pendingUtterance = utterance
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
        pendingUtterance = nil
        continuation.resume()
    }

    private func finished(_ utterance: AVSpeechUtterance) {
        guard pendingUtterance === utterance else { return }
        resumePending()
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.finished(utterance) }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.finished(utterance) }
    }
}
