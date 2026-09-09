import Foundation

enum FeatureFlags {
    /// CarPlay stays off until the audio entitlement is approved.
    /// Phase 4 builds the scene behind this.
    static let carPlayEnabled = false

    /// Phase 2 replaces ManualClock with a MapKit ETA clock.
    static let destinationAndETAEnabled = false

    /// Phase 3 turns on persistence and the daily streak.
    static let persistenceEnabled = false
}
