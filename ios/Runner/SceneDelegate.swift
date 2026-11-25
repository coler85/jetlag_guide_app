import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if let url = connectionOptions.urlContexts.first(where: { $0.url.scheme == "jetlagguide" })?.url {
      ScheduleDeepLinkRelay.shared.stash(url)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    if let url = URLContexts.first(where: { $0.url.scheme == "jetlagguide" })?.url {
      ScheduleDeepLinkRelay.shared.emit(url)
    }
  }
}
