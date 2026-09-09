import Foundation

enum FeatureFlags {
    /// CarPlay stays off until the audio entitlement is approved.
    /// Phase 4 builds the scene behind this.
    static let carPlayEnabled = false

    /// Phase 2: MapKit destination and ETA. Turn off to force the manual
    /// minutes path, which needs no location permission.
    static let destinationAndETAEnabled = true

    /// Phase 3 turns on persistence and the daily streak.
    static let persistenceEnabled = false
}
