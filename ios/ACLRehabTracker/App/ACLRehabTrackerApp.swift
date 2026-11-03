import SwiftUI
import FirebaseCore

// AppDelegate for orientation control
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}

@main
struct ACLRehabTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        #if ACL_MODEL_TEST
        guard let path = Bundle.main.path(forResource: "GoogleService-Test", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else {
            fatalError("Download the test app Firebase configuration. See docs/model-testing.md.")
        }
        FirebaseApp.configure(options: options)
        #else
        FirebaseApp.configure()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
            .preferredColorScheme(.dark)
        }
    }
}
