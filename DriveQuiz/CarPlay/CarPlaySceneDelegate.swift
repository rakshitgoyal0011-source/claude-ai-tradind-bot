import CarPlay
import UIKit

/// Root of the CarPlay scene.
///
/// This class is only ever instantiated when the Info.plist scene manifest
/// names it AND the `com.apple.developer.carplay-audio` entitlement is on the
/// build. Until the entitlement is approved, nothing here runs, which is why
/// Phase 4 sits behind FeatureFlags.carPlayEnabled as well: the flag keeps
/// Now Playing and the remote commands dormant so the phone build behaves
/// exactly as it did in Phase 3.
///
/// The template is CPNowPlayingTemplate and nothing else. A list of questions
/// or a browsable pack would be a screen the driver reads, which the brief
/// rules out.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let template = CPNowPlayingTemplate.shared

        // "Repeat" is the one control worth a dedicated button, because it is
        // the answer to a navigation prompt talking over a question. The
        // handler is not main-actor isolated, so it hops before touching the
        // game.
        template.updateNowPlayingButtons([
            CPNowPlayingRepeatButton { _ in
                Task { @MainActor in
                    GameCoordinator.shared.engine?.handleRemoteCommand(.repeatQuestion)
                }
            }
        ])
        template.isUpNextButtonEnabled = false
        template.isAlbumArtistButtonEnabled = false

        interfaceController.setRootTemplate(template, animated: true, completion: nil)
        NowPlayingController.shared.activate()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        // The game keeps running on the phone. Only the car screen went away.
    }
}
