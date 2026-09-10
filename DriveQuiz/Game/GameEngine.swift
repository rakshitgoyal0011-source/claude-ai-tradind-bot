import Foundation
import Observation
import DriveQuizKit

/// The voice loop. Speaks, listens, grades, repeats, and wraps up before the
/// driver arrives. Owns no audio APIs directly, only the controller.
@MainActor
@Observable
final class GameEngine {

    private(set) var card = CardState()
    private(set) var phase: GamePhase = .notStarted

    private let audio: AudioSessionController
    private let clock: SessionClock
    private var session: Session
    private let plan: SessionPlan
    private let store: ProgressStoring?
    private var progress: PlayerProgress
    /// Recorded so these questions are not asked again on the next drive.
    private var askedIDs: [String] = []
    private var progressWritten = false

    private var loopTask: Task<Void, Never>?
    private var stopRequested = false
    /// Set by a control outside the voice loop, such as a CarPlay button.
    private var externalCommand: VoiceCommand?

    /// Watchdog state. See SilenceWatchdog for why this exists.
    private var lastSpokeAt = Date()
    private var watchdogTask: Task<Void, Never>?
    private var warnedAboutHearing = false

    /// Commands the driver may use while a question is on the table.
    private let inGameCommands: Set<VoiceCommand> =
        [.repeatQuestion, .skip, .pause, .howManyLeft, .stop]
    /// While paused we deliberately hear almost nothing.
    private let pausedCommands: Set<VoiceCommand> = [.resume, .stop]

    init(
        audio: AudioSessionController,
        clock: SessionClock,
        plan: SessionPlan,
        store: ProgressStoring? = nil,
        progress: PlayerProgress = .fresh
    ) {
        self.audio = audio
        self.clock = clock
        self.plan = plan
        self.store = store
        self.progress = progress
        self.session = Session(plannedDuration: plan.plannedDuration)
        self.card.sessionName = plan.theme
        self.card.dailyStreak = progress.daily.current
    }

    /// Writes the drive to disk. Idempotent, because both the natural ending
    /// and the stop button route through it.
    private func persistProgress() {
        guard !progressWritten, session.asked > 0 else { return }
        progressWritten = true
        progress.recordSession(
            askedIDs: askedIDs,
            asked: session.asked,
            correct: session.correct
        )
        card.dailyStreak = progress.daily.current
        store?.save(progress)
    }

    // MARK: - Lifecycle

    func start() {
        guard loopTask == nil else { return }
        phase = .running
        card.isRunning = true
        clock.start()

        audio.onInterruption = { [weak self] ended, mayResume in
            guard let self else { return }
            guard ended else {
                self.clock.pause()
                return
            }
            if mayResume {
                self.clock.resume()
            } else {
                // The system says another app has the audio for good. There
                // is no way to speak, so ending here beats spinning through
                // the rest of the pack in silence.
                self.stop()
            }
        }

        lastSpokeAt = Date()
        loopTask = Task { await self.run() }
        startWatchdog()
    }

    /// Speaking funnel. Nothing else in the engine may call audio.say, or the
    /// watchdog would think the game had gone quiet while it was talking.
    /// Silence held before a new question, so a verdict, a fact and the next
    /// prompt do not run together into one wall of speech.
    private static let breathBeforeQuestion: TimeInterval = 2.0

    private func speak(_ text: String, pauseBefore: TimeInterval = 0) async {
        await audio.say(text, pauseBefore: pauseBefore)
        lastSpokeAt = Date()
    }

    private func startWatchdog() {
        guard watchdogTask == nil else { return }
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                self.checkForSilence()
            }
        }
    }

    private func checkForSilence() {
        guard card.isRunning, !stopRequested else { return }

        switch SilenceWatchdog.action(
            silentFor: Date().timeIntervalSince(lastSpokeAt),
            isPaused: card.isPaused,
            isInterrupted: audio.state == .interrupted
        ) {
        case .wait:
            return

        case .nudge:
            // Usually a listen that will not finish. Ending it hands control
            // back to the loop, which speaks next.
            audio.interruptListening()

        case .giveUp:
            // Whatever went wrong is not recovering. An explained ending
            // beats a car that has simply stopped talking.
            card.watchdogEnded = true
            stop()
        }
    }

    /// The on-screen stop button and the "stop" command land here.
    func stop() {
        stopRequested = true
        loopTask?.cancel()
        loopTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        persistProgress()
        clock.stop()
        audio.deactivate()
        card.isRunning = false
        switch phase {
        case .finished: break
        default: phase = .finished(summary: summaryText(interrupted: true))
        }
    }

    // MARK: - Main loop

    /// Holds the loop while a call or Siri owns the audio session.
    ///
    /// Without this the loop keeps running: every say and hear returns
    /// instantly while interrupted, so a two minute call would burn silently
    /// through every remaining question and the drive would end with a score
    /// the driver never had a chance to earn.
    private func awaitInterruptionEnd() async {
        var waited = 0
        while audio.state == .interrupted, !stopRequested, !Task.isCancelled {
            // Ten minutes is longer than any interruption worth waiting out.
            if waited >= 600 {
                stop()
                return
            }
            waited += 1
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func run() async {
        await speak(introText())

        for question in plan.questions {
            if stopRequested || Task.isCancelled { break }
            await awaitInterruptionEnd()
            if stopRequested || Task.isCancelled { break }

            // Use the live clock, not the plan. A slow round must not push
            // us past the destination.
            guard PackPlanner.shouldStartNextQuestion(
                remainingSeconds: clock.remainingSeconds,
                question: question
            ) else { break }

            await ask(question)
        }

        guard !stopRequested else { return }
        await finish()
    }

    private func finish() async {
        persistProgress()
        let summary = summaryText(interrupted: false)
        await speak(summary)
        phase = .finished(summary: summary)
        card.isRunning = false
        watchdogTask?.cancel()
        watchdogTask = nil
        clock.stop()
        audio.deactivate()
    }

    // MARK: - One question

    private func ask(_ question: Question) async {
        guard !stopRequested, !Task.isCancelled else { return }
        // Marked seen from here on, so the next drive does not repeat it.
        askedIDs.append(question.id)

        var nudged = false
        var attempts = 0
        var needsPrompt = true

        // Bounded so a recognizer that keeps failing cannot trap the driver
        // on one question for the rest of the drive. Repeats and status
        // questions spend from the same budget, which is why running out has
        // to end in a spoken outcome rather than silence.
        while attempts < 8 {
            attempts += 1
            if stopRequested || Task.isCancelled { return }

            // A call mid-question must not consume the attempt budget in
            // silence. Wait it out, then repeat the prompt from the top.
            if audio.state == .interrupted {
                await awaitInterruptionEnd()
                if stopRequested || Task.isCancelled { return }
                needsPrompt = true
            }

            if needsPrompt {
                await speak(question.prompt, pauseBefore: Self.breathBeforeQuestion)
            }
            needsPrompt = true

            let heard = await audio.hear(timeout: 8, hints: question.recognitionHints)

            if let command = takeCommand(from: heard, allowing: inGameCommands) {
                switch command {
                case .repeatQuestion:
                    continue

                case .skip:
                    session.recordSkipped()
                    refreshCard()
                    await speak("Skipping. The answer was \(question.canonicalAnswer).")
                    return

                case .pause:
                    await runPause()
                    if stopRequested { return }
                    // A long pause can eat the rest of an ETA drive. Hand
                    // back to the main loop, which will wrap up.
                    guard PackPlanner.shouldStartNextQuestion(
                        remainingSeconds: clock.remainingSeconds,
                        question: question
                    ) else { return }
                    continue

                case .howManyLeft:
                    await speak(remainingText())
                    continue

                case .stop:
                    stopRequested = true
                    await finishEarly()
                    return

                case .resume:
                    continue
                }
            }

            let verdict = AnswerGrader.grade(candidates: heard.candidates, question: question)

            switch verdict {
            case _ where audio.consecutiveListenFailures >= 2 && !warnedAboutHearing:
                // Not the driver being quiet: the recogniser is failing. Say
                // so once rather than silently reading out every answer.
                warnedAboutHearing = true
                await speak("I am having trouble hearing you. "
                    + "I will read out the answers for now.")
                session.recordSkipped()
                refreshCard()
                await speak("This one was \(question.canonicalAnswer).")
                return

            case .noSpeech where !nudged:
                // One nudge, then move on. Repeating forever is worse than
                // losing a question. The prompt is not repeated: they heard
                // it, they just did not answer.
                nudged = true
                needsPrompt = false
                await speak("Still there? Take a guess, or say skip.")
                continue

            case .noSpeech:
                session.recordSkipped()
                refreshCard()
                await speak("Let us move on. The answer was \(question.canonicalAnswer).")
                return

            case .correct:
                session.recordCorrect()
                refreshCard()
                await speak(correctText())
                await speak(question.factOneLiner)
                return

            case .incorrect:
                session.recordIncorrect()
                refreshCard()
                await speak("Not quite. It was \(question.canonicalAnswer).")
                await speak(question.factOneLiner)
                return
            }
        }

        // Attempt budget spent. Never drop a question in silence: that reads
        // as the app having died, which is the worst thing it can do to
        // someone who cannot look at the screen.
        guard !stopRequested, !Task.isCancelled else { return }
        session.recordSkipped()
        refreshCard()
        await speak("Let us move on. The answer was \(question.canonicalAnswer).")
    }

    // MARK: - Pause

    /// Voice-only resume, which is the whole point of the product. The cost
    /// is that the microphone stays live through the pause, listening for
    /// nothing but resume and stop.
    private func runPause() async {
        clock.pause()
        audio.enterPause()
        phase = .paused
        card.isPaused = true
        await speak("Paused. Say resume when you are ready.")

        // Roughly five minutes of listening to nothing.
        let maxIdleRounds = 25
        var idleRounds = 0

        while !stopRequested && !Task.isCancelled {
            // A call during a pause would otherwise spin the idle budget away
            // in a fraction of a second, since hear returns instantly.
            await awaitInterruptionEnd()
            if stopRequested || Task.isCancelled { return }

            // An ETA keeps counting down through a pause, so the drive can end
            // while we are still waiting. Come back rather than listening into
            // an empty car park; the main loop will see the clock and wrap up.
            if clock.remainingSeconds < PackPlanner.wrapUpThreshold {
                clock.resume()
                phase = .running
                card.isPaused = false
                return
            }

            // A manual clock is frozen while paused, so it will never end the
            // pause on its own. Without this cap the driver is stuck.
            if idleRounds >= maxIdleRounds {
                stopRequested = true
                await finishEarly()
                return
            }
            idleRounds += 1

            let heard = await audio.hear(timeout: 12, hints: ["resume", "stop"])
            guard let command = takeCommand(from: heard, allowing: pausedCommands)
            else { continue }

            switch command {
            case .resume:
                clock.resume()
                phase = .running
                card.isPaused = false
                await speak("Back to it.")
                return
            case .stop:
                stopRequested = true
                await finishEarly()
                return
            default:
                continue
            }
        }
    }

    private func finishEarly() async {
        persistProgress()
        let summary = summaryText(interrupted: true)
        await speak(summary)
        phase = .finished(summary: summary)
        card.isRunning = false
        watchdogTask?.cancel()
        watchdogTask = nil
        clock.stop()
        audio.deactivate()
    }

    // MARK: - External controls

    /// Entry point for anything that is not the microphone: a CarPlay
    /// button, a lock screen control, the stop button on the card.
    func handleRemoteCommand(_ command: VoiceCommand) {
        guard card.isRunning else { return }
        if command == .stop {
            stop()
            return
        }
        externalCommand = command
        // Do not make the driver wait out the listen window.
        audio.interruptListening()
    }

    /// An external command wins over the transcript, and is consumed either
    /// way so it cannot fire twice.
    private func takeCommand(
        from heard: Transcript,
        allowing allowed: Set<VoiceCommand>
    ) -> VoiceCommand? {
        if let external = externalCommand {
            externalCommand = nil
            if allowed.contains(external) { return external }
        }
        return CommandMatcher.command(in: heard.best, allowing: allowed)
    }

    // MARK: - Now Playing

    /// What a car screen may show. Deliberately excludes the question text:
    /// no question may be answerable by reading, and a prompt on the dash
    /// would be exactly that.
    struct NowPlayingSnapshot: Equatable {
        let title: String
        let scoreLine: String
        let dayLine: String?
        let elapsed: TimeInterval
        let duration: TimeInterval
        let isPlaying: Bool
    }

    var nowPlayingSnapshot: NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: card.sessionName,
            scoreLine: "Score \(card.scoreLine)",
            dayLine: card.dailyStreak >= 2 ? "Day \(card.dailyStreak)" : nil,
            elapsed: min(clock.elapsedSeconds, plan.plannedDuration),
            duration: plan.plannedDuration,
            isPlaying: card.isRunning && !card.isPaused
        )
    }

    // MARK: - Spoken copy

    private func introText() -> String {
        let count = plan.questions.count
        let minutes = Int((plan.plannedDuration / 60).rounded())
        guard count > 0 else {
            return "That is not quite enough time for a round. Drive safely."
        }

        // No question count. The queue is padded for traffic in ETA mode, and
        // even in minutes mode a repeat or a status question eats into it, so
        // any number quoted here is a promise the drive will not keep. It is
        // also not a number a driver has any use for.
        let opener: String
        switch plan.mode {
        case .manualMinutes:
            opener = "\(plan.theme). \(minutes) minutes on the clock."
        case .estimatedArrival:
            opener = "\(plan.theme). About \(minutes) minutes to your destination. "
                + "I will wrap up as you arrive."
        }
        var line = opener
        let projected = progress.daily.projectedCurrent(on: Date())
        if projected >= 2 {
            line += " Day \(projected) in a row."
        }
        return line + " Say repeat, skip, pause, or stop at any time. Here is the first one."
    }

    private func correctText() -> String {
        switch session.streak {
        case 3: return "Correct. That is three in a row."
        case 5: return "Correct. Five straight."
        case 10: return "Correct. Ten in a row, that is a run."
        default: return ["Correct.", "That is right.", "Got it."].randomElement() ?? "Correct."
        }
    }

    private func remainingText() -> String {
        let minutes = Int((clock.remainingSeconds / 60).rounded())
        let minutePart = minutes <= 1 ? "about a minute" : "about \(minutes) minutes"

        let left: Int
        switch plan.mode {
        case .manualMinutes:
            left = max(0, plan.questions.count - session.asked)
        case .estimatedArrival:
            // The queue is padded for traffic, so count what the remaining
            // drive actually has room for rather than what is queued.
            let usable = max(0, clock.remainingSeconds - PackPlanner.closingSeconds)
            let average = averageQuestionSeconds
            let capacity = average > 0 ? Int(usable / average) : 0
            left = min(capacity, max(0, plan.questions.count - session.asked))
        }

        // Time is what the driver actually wants. A question count only helps
        // once it is small enough to be a countdown rather than a workload.
        guard left <= 5 else { return "\(minutePart) to go." }
        let questionPart = left == 1 ? "one question left" : "\(left) questions left"
        return "\(minutePart) to go, \(questionPart)."
    }

    private var averageQuestionSeconds: TimeInterval {
        let upcoming = plan.questions.dropFirst(session.asked)
        guard !upcoming.isEmpty else { return 0 }
        return upcoming.reduce(0) { $0 + $1.estimatedSeconds } / Double(upcoming.count)
    }

    private func summaryText(interrupted: Bool) -> String {
        guard session.asked > 0 else {
            return interrupted ? "Stopped before we got going. See you tomorrow."
                               : "We ran out of road. See you tomorrow."
        }
        if card.watchdogEnded {
            // Spoken output is what failed, so this exists to be read on the
            // card afterwards rather than heard.
            return "DriveQuiz went quiet and stopped itself. "
                + "You had \(session.correct) out of \(session.asked). "
                + "Sorry about that."
        }
        let opener = interrupted ? "Stopping there." : "That is the drive."
        var parts = ["\(opener) You got \(session.correct) out of \(session.asked)."]
        if session.bestStreak >= 3 {
            parts.append("Your best run was \(session.bestStreak) in a row.")
        }
        if plan.ranOutOfQuestions {
            parts.append("We used every question in the pack.")
        }
        if progress.daily.current >= 2 {
            parts.append("That is \(progress.daily.current) days in a row.")
        }
        parts.append("See you tomorrow.")
        return parts.joined(separator: " ")
    }

    private func refreshCard() {
        card.score = session.correct
        card.asked = session.asked
    }
}
