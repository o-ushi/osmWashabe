import Flutter
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
    guard let windowScene = scene as? UIWindowScene else { return }

    // Engine は AppDelegate.application ですでに run 済み。
    // Storyboard 経由の Implicit Engine を使わず、明示的に VC を作ることで
    // ProMotion 端末での VSyncClient SIGSEGV を回避する。
    window = UIWindow(windowScene: windowScene)
    window?.rootViewController = FlutterViewController(
      engine: appDelegate.flutterEngine,
      nibName: nil,
      bundle: nil
    )
    window?.makeKeyAndVisible()
  }
}
