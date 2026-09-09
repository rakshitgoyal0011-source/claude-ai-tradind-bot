import AVFoundation
import Speech

struct Transcript: Equatable {
    /// Best transcription first, then the recognizer's alternatives.
    /// Grade against all of them: the right proper noun is often second.
    let candidates: [String]

    var best: String { candidates.first ?? "" }

    var isEmpty: Bool {
        candidates.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static let empty = Transcript(candidates: [])
}

enum ListenerError: Error {
    case recognizerUnavailable
    case engineFailed(Error)
}

/// Collects partial results and decides when the driver has stopped talking.
@MainActor
private final class ListenCollector {
    private var candidates: [String] = []
    private var completed = false
    private var timeoutTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private let silenceCutoff: TimeInterval

    var onComplete: (([String]) -> Void)?

    init(timeout: TimeInterval, silenceCutoff: TimeInterval) {
        self.silenceCutoff = silenceCutoff
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.complete()
        }
    }

    func update(candidates newCandidates: [String], isFinal: Bool) {
        guard !completed else { return }
        if !newCandidates.isEmpty { candidates = newCandidates }

        if isFinal {
            complete()
            return
        }

        // Every partial result restarts the silence window, so a driver who
        // answers in two seconds is not left waiting out the full eight.
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.silenceCutoff))
            guard !Task.isCancelled else { return }
            self.complete()
        }
    }

    func complete() {
        guard !completed else { return }
        completed = true
        timeoutTask?.cancel()
        silenceTask?.cancel()
        onComplete?(candidates)
        onComplete = nil
    }
}

/// Owns the audio engine tap and the recognition task. Never runs while the
/// Speaker is talking: the phone microphone would otherwise transcribe our
/// own voice coming back out of the car speakers.
@MainActor
final class Listener {

    private let recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    init(locale: Locale = Locale(identifier: "en-US")) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// False until the locale's on-device model has downloaded.
    var supportsOnDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }
    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    /// - Parameter hints: the accepted answers for this question. Biasing the
    ///   recognizer toward them is the single largest accuracy win available,
    ///   because trivia answers are mostly proper nouns.
    func listen(
        timeout: TimeInterval = 8,
        silenceCutoff: TimeInterval = 1.4,
        hints: [String] = []
    ) async throws -> Transcript {

        guard let recognizer, recognizer.isAvailable else {
            throw ListenerError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Cars lose signal. Server recognition would fail exactly when the
        // driver is mid-answer, so stay on device whenever we can.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.taskHint = .search
        request.contextualStrings = hints
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()

        do {
            try engine.start()
        } catch {
            teardown()
            throw ListenerError.engineFailed(error)
        }

        let collector = ListenCollector(timeout: timeout, silenceCutoff: silenceCutoff)

        return await withCheckedContinuation { continuation in
            collector.onComplete = { [weak self] candidates in
                self?.teardown()
                continuation.resume(returning: Transcript(candidates: candidates))
            }

            task = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let strings = Self.candidateStrings(from: result)
                    let isFinal = result.isFinal
                    Task { @MainActor in
                        collector.update(candidates: strings, isFinal: isFinal)
                    }
                }
                if error != nil {
                    Task { @MainActor in collector.complete() }
                }
            }
        }
    }

    /// Cancels an in-flight listen. Safe to call from any state.
    func cancel() {
        teardown()
    }

    private func teardown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private static func candidateStrings(from result: SFSpeechRecognitionResult) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for text in [result.bestTranscription.formattedString]
            + result.transcriptions.map(\.formattedString) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }
}
