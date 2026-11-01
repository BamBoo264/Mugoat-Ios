import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // The Lite build (PGLiteMode in Info.plist, build_ipa.sh --lite): the engine and renderer read PG_LITE.
        if Theme.isLite && getenv("PG_LITE") == nil { setenv("PG_LITE", "1", 1) }
        UserDefaults.standard.register(defaults: ["cameraTouchMode": 2, "gtaPortAppLanguage": "vi", "NovaVietnameseEnabled": true])
        if Theme.isLite {
            UserDefaults.standard.set(GraphicsPreset.performance.rawValue,forKey:"graphicsPreset")
            UserDefaults.standard.set(540,forKey:"renderHeight")
            UserDefaults.standard.set([String:String](),forKey:"graphicsOverrides")
            UserDefaults.standard.set(60,forKey:"frameRateCap")
            UserDefaults.standard.register(defaults:["NovaUpscaler":1])
            setenv("PG_LITE_DENSITY","0.30",1);setenv("PG_LITE_LOD","0.55",1)
        }
        NovaMemorySettings.apply()
        GameSettings.applyExperimentalSwitches()
        ModInstaller.applyPending()
        #if targetEnvironment(simulator)
        // Test: --import-save <file> runs Settings › Import a Story save on that file at launch.
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "--import-save"), i + 1 < arguments.count {
            switch SaveImport.importSave(from: URL(fileURLWithPath: arguments[i + 1])) {
            case let .imported(title, slot): NSLog("[native-port] TEST: save imported: \(title) into slot \(slot)")
            case let .failed(message): NSLog("[native-port] TEST: save import failed: \(message)")
            }
        }
        #endif
        // Nova does not send telemetry to the upstream author service.
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = NativePortViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
