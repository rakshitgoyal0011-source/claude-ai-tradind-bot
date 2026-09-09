import SwiftUI

@main
struct DriveQuizApp: App {
    var body: some Scene {
        WindowGroup {
            StartView()
                // The driver must never be left in the dark mid-question.
                .persistentSystemOverlays(.hidden)
                .statusBarHidden(false)
        }
    }
}
