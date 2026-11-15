import Flutter
import UIKit

/// シーン設定名。NSUserActivity の種別にも使われるので、逆引き DNS にする。
/// "flutter" のようにピリオドが無いと iOS 27 が例外で止める。
enum SceneConfiguration {
  static let name = "com.osamushikubo.osmWashabe.scene"
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if scene.userActivity == nil {
      scene.userActivity = NSUserActivity(activityType: SceneConfiguration.name)
    }
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

  func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
    // 以前の起動で残った設定名が "flutter" のとき、それを種別に使うと落ちる。
    if scene.userActivity == nil {
      let name = scene.session.configuration.name ?? ""
      if !name.contains(".") {
        return nil
      }
    }
    return scene.userActivity
  }
}
