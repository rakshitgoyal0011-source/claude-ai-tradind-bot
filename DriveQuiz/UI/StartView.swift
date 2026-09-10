import SwiftUI
import MapKit
import DriveQuizKit

/// The only interactive screen, and the only moment the display matters.
/// Everything after Start is voice.
struct StartView: View {

    private enum LengthSource: String, CaseIterable {
        case destination = "Destination"
        case minutes = "Minutes"
    }

    @State private var source: LengthSource = .destination
    @State private var minutes: Int = 20
    @State private var query: String = ""
    @State private var results: [DestinationResult] = []
    @State private var chosen: DestinationResult?
    @State private var isSearching = false
    @State private var status: String?

    @State private var engine: GameEngine?
    @State private var audio = AudioSessionController()
    @State private var locations = LocationProvider()
    @State private var store = FileProgressStore()

    private let search = DestinationSearch()
    private let etaProvider = ETAProvider()

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

    // MARK: - Setup

    private var setup: some View {
        VStack(spacing: 20) {
            Text("DriveQuiz")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .padding(.top, 24)

            if FeatureFlags.destinationAndETAEnabled {
                Picker("Session length", selection: $source) {
                    ForEach(LengthSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
            }

            if source == .destination && FeatureFlags.destinationAndETAEnabled {
                destinationPicker
            } else {
                minutesPicker
            }

            if let status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer(minLength: 8)

            Button(action: begin) {
                Text("Start")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 92)
            }
            .buttonStyle(.borderedProminent)
            .disabled(source == .destination && chosen == nil && FeatureFlags.destinationAndETAEnabled)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            if let summary = finishedSummary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
            }
        }
    }

    private var minutesPicker: some View {
        VStack(spacing: 12) {
            Text("How long is your drive?")
                .font(.title3)
                .foregroundStyle(.secondary)

            Stepper(value: $minutes, in: 3...90, step: 1) {
                Text("\(minutes) minutes")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where are you headed?")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            TextField("Search for a place", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { runSearch() }
                .padding(.horizontal, 24)

            if let chosen {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text(chosen.name).font(.headline)
                        if !chosen.subtitle.isEmpty {
                            Text(chosen.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
            }

            if isSearching {
                ProgressView().frame(maxWidth: .infinity)
            }

            List(results) { result in
                Button {
                    chosen = result
                    results = []
                    query = result.name
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name).font(.body)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .frame(maxHeight: results.isEmpty ? 0 : 260)
        }
    }

    private var finishedSummary: String? {
        guard case .finished(let summary)? = engine?.phase else { return nil }
        return summary
    }

    // MARK: - Actions

    private func runSearch() {
        status = nil
        isSearching = true
        Task {
            defer { isSearching = false }
            guard await locations.requestAuthorization() else {
                status = "DriveQuiz needs your location to estimate the drive. "
                    + "Enable it in Settings, or switch to Minutes."
                return
            }
            let here = try? await locations.currentLocation()
            do {
                results = try await search.search(query, near: here?.coordinate)
                if results.isEmpty { status = "No places matched that search." }
            } catch {
                status = "Could not search right now. Try Minutes instead."
            }
        }
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
                let (clock, seconds, mode) = try await makeClock()
                let progress = FeatureFlags.persistenceEnabled ? store.load() : .fresh

                try audio.activate()

                let plan = PackPlanner.plan(
                    packs: [pack],
                    availableSeconds: seconds,
                    mode: mode,
                    // Traffic stretches an ETA. Queue past it and let the
                    // live clock decide when to stop.
                    contingency: mode == .estimatedArrival ? 1.3 : 1.0,
                    // Prefer questions this driver has not heard before.
                    history: progress.history,
                    seed: UInt64(Date().timeIntervalSince1970)
                )

                guard !plan.questions.isEmpty else {
                    status = "That drive is too short for a round. Try five minutes or more."
                    audio.deactivate()
                    return
                }

                let newEngine = GameEngine(
                    audio: audio,
                    clock: clock,
                    plan: plan,
                    store: FeatureFlags.persistenceEnabled ? store : nil,
                    progress: progress
                )
                engine = newEngine
                newEngine.start()
            } catch {
                status = "Could not start: \(error.localizedDescription)"
            }
        }
    }

    /// Returns the clock, the drive length it implies, and which mode we are in.
    private func makeClock() async throws -> (SessionClock, TimeInterval, SessionMode) {
        guard FeatureFlags.destinationAndETAEnabled,
              source == .destination,
              let chosen
        else {
            let seconds = TimeInterval(minutes) * 60
            return (ManualClock(minutes: minutes), seconds, .manualMinutes)
        }

        let here = try await locations.currentLocation()
        let snapshot = try await etaProvider.snapshot(
            from: here.coordinate,
            to: chosen.mapItem
        )
        let clock = ETAClock(
            destination: chosen.mapItem,
            initial: snapshot,
            locations: locations
        )
        return (clock, snapshot.seconds, .estimatedArrival)
    }
}
