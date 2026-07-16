import SwiftUI

@main
struct NOTRApp: App {
    @NSApplicationDelegateAdaptor(NOTRAppDelegate.self) private var appDelegate

    var body: some Scene {
        // Status item + floating panel are owned by the app delegate.
        // Settings scene satisfies SwiftUI App requirements without a dock window.
        Settings {
            EmptyView()
        }
    }
}
