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
    /// nil means draw from every pack.
    @State private var selectedPackID: String?
    @State private var packs: [QuestionPack] = []
    @State private var query: String = ""
    @State private var results: [DestinationResult] = []
    @State private var chosen: DestinationResult?
    @State private var isSearching = false
    @State private var isStarting = false
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
                NowPlayingController.shared.deactivate()
                GameCoordinator.shared.detach()
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

            themePicker

            if let status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer(minLength: 8)

            Button(action: begin) {
                Group {
                    if isStarting {
                        // A GPS fix plus a route lookup takes real seconds.
                        // Without this the button looks dead and gets tapped
                        // again, which would start a second voice loop.
                        ProgressView().tint(.white)
                    } else {
                        Text("Start")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 92)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isStarting || (source == .destination && chosen == nil && FeatureFlags.destinationAndETAEnabled))
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

    private var themePicker: some View {
        Menu {
            Button("Mixed") { selectedPackID = nil }
            ForEach(packs, id: \.id) { pack in
                Button(pack.theme) { selectedPackID = pack.id }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedThemeName)
                Image(systemName: "chevron.down").font(.caption)
            }
            .font(.title3)
        }
        .task {
            guard packs.isEmpty else { return }
            packs = (try? PackLoader.loadAll()) ?? []
        }
    }

    private var selectedThemeName: String {
        guard let selectedPackID,
              let pack = packs.first(where: { $0.id == selectedPackID })
        else { return "Mixed" }
        return pack.theme
    }

    private var chosenPacks: [QuestionPack] {
        guard let selectedPackID,
              let pack = packs.first(where: { $0.id == selectedPackID })
        else { return packs }
        return [pack]
    }

    private var finishedSummary: String? {
        guard case .finished(let summary)? = engine?.phase else { return nil }
        return summary
    }

    // MARK: - Actions

    private func runSearch() {
        guard !isSearching else { return }
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
        // Belt as well as braces: the button is disabled while starting, but
        // two engines sharing one audio session would talk over each other.
        guard !isStarting, engine?.card.isRunning != true else { return }
        isStarting = true
        status = nil

        Task {
            defer { isStarting = false }

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
                if packs.isEmpty { packs = try PackLoader.loadAll() }
                let selection = chosenPacks
                let (clock, seconds, mode) = try await makeClock()
                let progress = FeatureFlags.persistenceEnabled ? store.load() : .fresh

                try audio.activate()

                let plan = PackPlanner.plan(
                    packs: selection,
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
                // Publish before starting, so the car screen and the lock
                // screen have something to show from the first utterance.
                GameCoordinator.shared.attach(newEngine)
                NowPlayingController.shared.activate()
                newEngine.start()
            } catch {
                // activate() may have succeeded before a later step failed.
                audio.deactivate()
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
