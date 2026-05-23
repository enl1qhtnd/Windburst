import SwiftUI
import WindburstShared

@main
struct WindburstApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Settings {
            SettingsView(appState: appDelegate.appState)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await appState.helperClient.shutdown()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }
}
