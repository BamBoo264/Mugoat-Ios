import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // The Lite build (PGLiteMode in Info.plist, build_ipa.sh --lite): the engine and renderer read PG_LITE.
        if Theme.isLite && getenv("PG_LITE") == nil { setenv("PG_LITE", "1", 1) }
        GameSettings.applyExperimentalSwitches()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = NativePortViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
