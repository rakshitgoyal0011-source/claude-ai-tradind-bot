import CoreLocation

enum LocationError: Error {
    case notAuthorized
    case unavailable
}

/// One-shot current location, plus authorization. The game only needs a fix
/// when it refreshes the arrival estimate, so nothing streams continuously.
@MainActor
final class LocationProvider: NSObject {

    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    private var locationWaiters: [CheckedContinuation<Result<CLLocation, Error>, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    func requestAuthorization() async -> Bool {
        let status = manager.authorizationStatus
        if status != .notDetermined {
            return isAuthorized
        }
        let resolved = await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
        return resolved == .authorizedWhenInUse || resolved == .authorizedAlways
    }

    func currentLocation() async throws -> CLLocation {
        guard isAuthorized else { throw LocationError.notAuthorized }

        // A recent cached fix is good enough for an ETA and avoids waiting
        // on the GPS at the start of a drive.
        if let cached = manager.location, cached.timestamp.timeIntervalSinceNow > -30 {
            return cached
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<CLLocation, Error>, Never>) in
            locationWaiters.append(continuation)
            manager.requestLocation()
        }
        return try result.get()
    }

    private func resolveLocation(_ result: Result<CLLocation, Error>) {
        let waiters = locationWaiters
        locationWaiters.removeAll()
        waiters.forEach { $0.resume(returning: result) }
    }
}

extension LocationProvider: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            let waiters = self.authorizationWaiters
            self.authorizationWaiters.removeAll()
            waiters.forEach { $0.resume(returning: status) }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last else { return }
        Task { @MainActor in self.resolveLocation(.success(latest)) }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in self.resolveLocation(.failure(error)) }
    }
}
