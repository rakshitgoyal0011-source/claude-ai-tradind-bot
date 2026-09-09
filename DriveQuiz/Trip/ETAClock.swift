import Foundation
import MapKit
import DriveQuizKit

/// SessionClock backed by a live MapKit arrival estimate.
///
/// The important difference from ManualClock: pausing the GAME does not pause
/// the DRIVE. A driver who says "pause" for two minutes still arrives at the
/// same moment, so the countdown keeps running and they simply get fewer
/// questions. Pausing the countdown here would hand out questions after the
/// car has already stopped.
@MainActor
final class ETAClock: SessionClock {

    private let destination: MKMapItem
    private let locations: LocationProvider
    private let provider: ETAProvider
    private let refreshInterval: TimeInterval

    private var snapshot: ETASnapshot
    private let startedAt: Date
    private var refreshTask: Task<Void, Never>?

    /// Set when a refresh fails so the UI can say the estimate is stale.
    private(set) var lastRefreshFailed = false

    init(
        destination: MKMapItem,
        initial: ETASnapshot,
        locations: LocationProvider,
        provider: ETAProvider = ETAProvider(),
        refreshInterval: TimeInterval = 120
    ) {
        self.destination = destination
        self.snapshot = initial
        self.locations = locations
        self.provider = provider
        self.refreshInterval = refreshInterval
        self.startedAt = initial.takenAt
    }

    var remainingSeconds: TimeInterval { snapshot.remaining(at: Date()) }

    var elapsedSeconds: TimeInterval { Date().timeIntervalSince(startedAt) }

    func start() {
        guard refreshTask == nil else { return }
        // MapKit throttles directions requests, so this is deliberately slow.
        // Between refreshes the last estimate simply counts down.
        let interval = refreshInterval
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
            }
        }
    }

    /// Intentionally a no-op on the countdown. See the type comment.
    func pause() {}
    func resume() {}

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refresh() async {
        do {
            let here = try await locations.currentLocation()
            let fresh = try await provider.snapshot(
                from: here.coordinate,
                to: destination
            )
            // A zero or failed reading must never replace a good estimate.
            snapshot = snapshot.replacing(with: fresh)
            lastRefreshFailed = false
        } catch {
            // Keep counting down from the last good estimate.
            lastRefreshFailed = true
        }
    }
}
