import SwiftUI

@main
struct DictaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(state)
        } label: {
            Image(nsImage: state.menuBarImage)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let file = SelfTest.requestedFile {
            Task { await SelfTest.run(file: file) }
            return
        }
        AppState.shared.bootstrap()
    }
}
