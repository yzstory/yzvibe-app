import SwiftUI
import YzVibeKit

@main
struct YzVibeApp: App {
    // 远程推送的系统回调要走 UIApplicationDelegate
    @UIApplicationDelegateAdaptor(YzVibeAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            RootTabView(store: ProcessInfo.processInfo.arguments.contains("--design-preview") ? AppStore() : nil)
            #else
            RootTabView()
            #endif
        }
    }
}
