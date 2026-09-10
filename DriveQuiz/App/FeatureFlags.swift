import Foundation

enum FeatureFlags {
    /// CarPlay stays off until the audio entitlement is approved.
    /// Phase 4 builds the scene behind this.
    static let carPlayEnabled = false

    /// Phase 2: MapKit destination and ETA. Turn off to force the manual
    /// minutes path, which needs no location permission.
    static let destinationAndETAEnabled = true

    /// Phase 3: local progress, daily streak, don't-repeat questions.
    /// Turn off to play from a clean slate every drive.
    static let persistenceEnabled = true
}
