import AppKit

final class NOTRAppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var panelController: StatusPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installCrashLogging()
        NSApp.setActivationPolicy(.accessory)
        Log.info("applicationDidFinishLaunching \(Log.runtimeSummary)", "app")

        let controller = StatusPanelController(appState: appState)
        controller.install()
        panelController = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("applicationWillTerminate \(Log.runtimeSummary)", "app")
    }

    private func installCrashLogging() {
        NSSetUncaughtExceptionHandler { exception in
            Log.error(
                "uncaught exception: \(exception.name.rawValue) reason=\(exception.reason ?? "nil") stack=\(exception.callStackSymbols.joined(separator: " | "))",
                "crash"
            )
        }
        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            signal(sig) { received in
                Log.error("fatal signal \(received)", "crash")
                signal(received, SIG_DFL)
                raise(received)
            }
        }
    }
}
