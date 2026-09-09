import SwiftUI
import DriveQuizKit

/// The only interactive screen. Everything after Start is voice.
/// Phase 2 adds a destination field here and derives minutes from the ETA.
struct StartView: View {

    @State private var minutes: Int = 20
    @State private var status: String?
    @State private var engine: GameEngine?
    @State private var audio = AudioSessionController()

    var body: some View {
        if let engine, engine.card.isRunning {
            SessionCardView(card: engine.card) {
                engine.stop()
                self.engine = nil
            }
        } else {
            setup
        }
    }

    private var setup: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("DriveQuiz")
                .font(.system(size: 44, weight: .bold, design: .rounded))

            Text("How long is your drive?")
                .font(.title3)
                .foregroundStyle(.secondary)

            Stepper(value: $minutes, in: 3...90, step: 1) {
                Text("\(minutes) minutes")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .padding(.horizontal, 40)

            if let status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button(action: begin) {
                Text("Start")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 92)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)

            if let summary = finishedSummary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private var finishedSummary: String? {
        guard case .finished(let summary)? = engine?.phase else { return nil }
        return summary
    }

    private func begin() {
        status = nil
        Task {
            switch await AudioSessionController.requestPermissions() {
            case .deniedSpeech:
                status = "DriveQuiz needs speech recognition to hear your answers. "
                    + "Enable it in Settings."
                return
            case .deniedMicrophone:
                status = "DriveQuiz needs the microphone to hear your answers. "
                    + "Enable it in Settings."
                return
            case .granted:
                break
            }

            do {
                let pack = try PackLoader.load()
                try audio.activate()

                if !audio.listener.supportsOnDevice {
                    // Not fatal, but worth knowing during Phase 1 testing.
                    print("[DriveQuiz] on-device recognition unavailable, falling back to server")
                }

                let plan = PackPlanner.plan(
                    packs: [pack],
                    availableSeconds: TimeInterval(minutes) * 60,
                    seed: UInt64(Date().timeIntervalSince1970)
                )

                guard !plan.questions.isEmpty else {
                    status = "That drive is too short for a round. Try five minutes or more."
                    audio.deactivate()
                    return
                }

                let newEngine = GameEngine(
                    audio: audio,
                    clock: ManualClock(minutes: minutes),
                    plan: plan
                )
                engine = newEngine
                newEngine.start()
            } catch {
                status = "Could not start audio: \(error.localizedDescription)"
            }
        }
    }
}
