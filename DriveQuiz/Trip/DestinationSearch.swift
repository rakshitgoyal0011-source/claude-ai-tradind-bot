import CoreLocation
import MapKit

struct DestinationResult: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let subtitle: String
    let mapItem: MKMapItem

    static func == (lhs: DestinationResult, rhs: DestinationResult) -> Bool {
        lhs.id == rhs.id
    }
}

/// Destination is chosen before the drive starts, which is the only moment
/// the screen is allowed to matter.
struct DestinationSearch {

    func search(
        _ query: String,
        near coordinate: CLLocationCoordinate2D?
    ) async throws -> [DestinationResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.pointOfInterest, .address]
        if let coordinate {
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            )
        }

        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(8).map { item in
            DestinationResult(
                name: item.name ?? "Destination",
                subtitle: Self.subtitle(for: item),
                mapItem: item
            )
        }
    }

    private static func subtitle(for item: MKMapItem) -> String {
        let placemark = item.placemark
        return [placemark.thoroughfare, placemark.locality, placemark.administrativeArea]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
