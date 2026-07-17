import AppKit
import SwiftUI

/// Borderless rounded panel anchored directly under the menu bar icon.
/// No popover arrow. Auto-closes when the user clicks away (like a normal menu-bar item).
///
/// Sizing is EXPLICIT (driven by `syncContentSize`), never `.preferredContentSize`
/// auto-sizing: the note viewer embeds an NSTextView, and pairing that with window
/// auto-sizing caused an infinite AppKit layout recursion (stack overflow crash).
final class StatusPanelController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var statusItem: NSStatusItem?
    private var panel: KeyablePanel?
    private var hostingController: NSHostingController<AnyView>?

    private var resignActiveObserver: NSObjectProtocol?
    private var globalClickMonitor: Any?

    private var anchorTopY: CGFloat = 0
    private var anchorCenterX: CGFloat = 0
    private var isPresented = false
    private var isSyncingSize = false

    private let shadowMargin: CGFloat = 10

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "note.text",
                accessibilityDescription: "NOTR"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "NOTR"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp])
        }
        statusItem = item
        Log.info("status item installed", "controller")
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        Log.info("status item clicked isPresented=\(isPresented)", "controller")
        if isPresented {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let button = statusItem?.button, let buttonWindow = button.window else {
            Log.error("show aborted: no status button/window", "controller")
            return
        }

        if panel == nil {
            buildPanel()
        }
        guard let panel else {
            Log.error("show aborted: no panel", "controller")
            return
        }

        appState.pruneMissingNotes()

        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        anchorTopY = screenRect.minY - 2
        anchorCenterX = screenRect.midX

        syncContentSize()
        pinToAnchor()
        panel.alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        isPresented = true
        installDismissObserver()
        Log.info("panel shown size=\(panel.frame.size) origin=\(panel.frame.origin)", "controller")
    }

    func hide() {
        guard isPresented else { return }
        appState.flushPendingSaveIfNeeded()
        removeDismissObserver()
        panel?.orderOut(nil)
        isPresented = false
        Log.info("panel hidden", "controller")
    }

    /// Explicitly size the panel to the SwiftUI content's fitting size (plus shadow margin).
    func syncContentSize() {
        guard let panel, let hostingController else { return }
        guard !isSyncingSize else { return }
        isSyncingSize = true
        defer { isSyncingSize = false }

        hostingController.view.layoutSubtreeIfNeeded()
        var fit = hostingController.view.fittingSize

        if !fit.width.isFinite || !fit.height.isFinite || fit.width < 40 || fit.height < 40 {
            Log.error("suspicious fittingSize=\(fit); using fallback", "controller")
            fit = NSSize(width: 340, height: 280)
        }
        fit.width = min(max(fit.width, 300), 1000)
        fit.height = min(max(fit.height, 160), 1000)

        if panel.frame.size != fit {
            panel.setContentSize(fit)
            Log.info("panel resized to \(fit)", "controller")
        }
    }

    private func pinToAnchor() {
        guard let panel else { return }
        var origin = NSPoint(
            x: anchorCenterX - panel.frame.width / 2,
            y: anchorTopY - panel.frame.height
        )
        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
            if origin.y < visible.minY + 8 { origin.y = visible.minY + 8 }
        }
        panel.setFrameOrigin(origin)
    }

    // Reposition (origin only) after AppKit resizes the window; never resize here (no loop).
    func windowDidResize(_ notification: Notification) {
        guard isPresented, !isSyncingSize else { return }
        pinToAnchor()
    }

    // Dismiss rules:
    //  1. App deactivation (clicked another app/window): didResignActiveNotification.
    //     The macOS emoji/character viewer is a NON-activating panel, so clicking an
    //     emoji keeps NOTR active and the panel stays open. (A plain global mouse-down
    //     monitor that closed on any outside click would wrongly swallow that emoji click.)
    //  2. Clicking ANOTHER menu-bar item: no resign-active fires for that (the other item
    //     just opens a tracking menu), so NOTR would otherwise linger underneath it. The
    //     global mouse-down monitor closes NOTR for those clicks, but ONLY when the click
    //     lands in the menu-bar strip — never for the emoji viewer, which floats below it.
    // Clicking our own status item keeps the app active and is handled by the toggle action.
    private func installDismissObserver() {
        removeDismissObserver()
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Log.info("app resigned active; dismissing panel", "controller")
            self?.hide()
        }
        // Global only: local monitors race with in-panel clicks.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.dismissIfMenuBarClick()
        }
    }

    private func removeDismissObserver() {
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
        }
        resignActiveObserver = nil
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
        globalClickMonitor = nil
    }

    /// Close when the user clicks a DIFFERENT menu-bar item, so it doesn't open underneath
    /// NOTR. Deliberately ignores non-menu-bar outside clicks so the emoji/character viewer
    /// (a non-activating panel below the menu bar) keeps working.
    private func dismissIfMenuBarClick() {
        guard isPresented, let panel else { return }
        let point = NSEvent.mouseLocation

        if panel.frame.contains(point) { return }

        if let button = statusItem?.button, let buttonWindow = button.window {
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = buttonWindow.convertToScreen(buttonRect).insetBy(dx: -4, dy: -4)
            if screenRect.contains(point) { return }
        }

        if pointIsInMenuBar(point) {
            Log.info("menu-bar click outside NOTR; dismissing panel", "controller")
            hide()
        }
    }

    private func pointIsInMenuBar(_ point: NSPoint) -> Bool {
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
            ?? statusItem?.button?.window?.screen
            ?? NSScreen.main
        guard let screen else { return false }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let effectiveHeight = max(menuBarHeight, NSStatusBar.system.thickness)
        return point.y >= screen.frame.maxY - effectiveHeight
    }

    private func buildPanel() {
        let root = MenuBarView(
            onClose: { [weak self] in
                self?.hide()
            },
            onContentSizeMayHaveChanged: { [weak self] in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.syncContentSize()
                    self.pinToAnchor()
                }
            }
        )
        .environment(appState)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .padding(EdgeInsets(top: 0, leading: shadowMargin, bottom: shadowMargin, trailing: shadowMargin))

        let hosting = NSHostingController(rootView: AnyView(root))
        hostingController = hosting

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 280),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        self.panel = panel
        Log.info("panel built", "controller")
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
