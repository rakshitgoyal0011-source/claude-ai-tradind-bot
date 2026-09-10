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
            if ended {
                if mayResume { self.clock.resume() }
            } else {
                self.clock.pause()
            }
        }

        loopTask = Task { await self.run() }
    }

    /// The on-screen stop button and the "stop" command land here.
    func stop() {
        stopRequested = true
        loopTask?.cancel()
        loopTask = nil
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

    private func run() async {
        await audio.say(introText())

        for question in plan.questions {
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
        await audio.say(summary)
        phase = .finished(summary: summary)
        card.isRunning = false
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

            if needsPrompt { await audio.say(question.prompt) }
            needsPrompt = true

            let heard = await audio.hear(timeout: 8, hints: question.recognitionHints)

            if let command = takeCommand(from: heard, allowing: inGameCommands) {
                switch command {
                case .repeatQuestion:
                    continue

                case .skip:
                    session.recordSkipped()
                    refreshCard()
                    await audio.say("Skipping. The answer was \(question.canonicalAnswer).")
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
                    await audio.say(remainingText())
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
            case .noSpeech where !nudged:
                // One nudge, then move on. Repeating forever is worse than
                // losing a question. The prompt is not repeated: they heard
                // it, they just did not answer.
                nudged = true
                needsPrompt = false
                await audio.say("Still there? Take a guess, or say skip.")
                continue

            case .noSpeech:
                session.recordSkipped()
                refreshCard()
                await audio.say("Let us move on. The answer was \(question.canonicalAnswer).")
                return

            case .correct:
                session.recordCorrect()
                refreshCard()
                await audio.say(correctText())
                await audio.say(question.factOneLiner)
                return

            case .incorrect:
                session.recordIncorrect()
                refreshCard()
                await audio.say("Not quite. It was \(question.canonicalAnswer).")
                await audio.say(question.factOneLiner)
                return
            }
        }

        // Attempt budget spent. Never drop a question in silence: that reads
        // as the app having died, which is the worst thing it can do to
        // someone who cannot look at the screen.
        guard !stopRequested, !Task.isCancelled else { return }
        session.recordSkipped()
        refreshCard()
        await audio.say("Let us move on. The answer was \(question.canonicalAnswer).")
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
        await audio.say("Paused. Say resume when you are ready.")

        // Roughly five minutes of listening to nothing.
        let maxIdleRounds = 25
        var idleRounds = 0

        while !stopRequested && !Task.isCancelled {
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
                await audio.say("Back to it.")
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
        await audio.say(summary)
        phase = .finished(summary: summary)
        card.isRunning = false
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

        let opener: String
        switch plan.mode {
        case .manualMinutes:
            opener = "\(plan.theme). I have \(count) questions for your \(minutes) minute drive."
        case .estimatedArrival:
            // The queue is padded past the estimate for traffic, so promising
            // a question count here would be a lie.
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

        let questionPart = left == 1 ? "One question left" : "\(left) questions left"
        return "\(questionPart), \(minutePart) to go."
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
