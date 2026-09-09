import CoreLocation
import MapKit
import DriveQuizKit

enum ETAError: Error {
    case noRoute
}

/// Wraps MKDirections. Kept deliberately thin so ETAClock can be reasoned
/// about without MapKit in the picture.
struct ETAProvider {

    func snapshot(
        from source: CLLocationCoordinate2D,
        to destination: MKMapItem,
        now: Date = Date()
    ) async throws -> ETASnapshot {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = destination
        request.transportType = .automobile
        // Traffic-aware, which is the whole point of resizing to the drive.
        request.departureDate = now

        let response = try await MKDirections(request: request).calculateETA()
        guard response.expectedTravelTime > 0 else { throw ETAError.noRoute }
        return ETASnapshot(seconds: response.expectedTravelTime, takenAt: now)
    }
}
