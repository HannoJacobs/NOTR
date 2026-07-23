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
    /// Screen that owns the status-item click; used for edge clamping. Never use
    /// `panel.screen` — it is often stale (previous show / initial (0,0) frame) and
    /// will shove the panel onto the wrong display on multi-monitor setups.
    private var anchorScreen: NSScreen?
    private var isPresented = false
    private var isSyncingSize = false

    private let shadowMargin: CGFloat = 10

    init(appState: AppState) {
        self.appState = appState
        super.init()
        appState.onPanelPinnedChanged = { [weak self] pinned in
            self?.handlePinChanged(pinned)
        }
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
        guard statusItem?.button?.window != nil else {
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
        refreshAnchorFromStatusItem()

        syncContentSize()
        pinToAnchor()
        panel.alphaValue = 1
        panel.level = appState.isPanelPinned ? .floating : .popUpMenu
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        isPresented = true
        installDismissObserver()
        Log.info(
            "panel shown size=\(panel.frame.size) origin=\(panel.frame.origin) anchor=(\(anchorCenterX),\(anchorTopY)) screen=\(anchorScreenDescription()) pinned=\(appState.isPanelPinned)",
            "controller"
        )
    }

    /// Resolve the panel's under-icon anchor from the status item, cross-checked
    /// against the click's screen. On multi-monitor Macs the status-item button
    /// window sometimes still reports the primary display's frame after a click on
    /// a secondary menu bar; trusting the mouse screen keeps the panel on the
    /// display the user actually clicked.
    private func refreshAnchorFromStatusItem() {
        guard let button = statusItem?.button, let buttonWindow = button.window else {
            return
        }

        let buttonRect = button.convert(button.bounds, to: nil)
        let reportedRect = buttonWindow.convertToScreen(buttonRect)
        let mouse = NSEvent.mouseLocation
        let clickScreen = screenContaining(mouse)
        let reportedScreen = screenIntersecting(reportedRect) ?? buttonWindow.screen

        // Prefer the click screen when the status-item frame disagrees with where
        // the user actually clicked (common after menu-bar relocation).
        if let clickScreen, let reportedScreen, clickScreen != reportedScreen {
            anchorScreen = clickScreen
            anchorCenterX = mouse.x
            anchorTopY = clickScreen.visibleFrame.maxY - 2
            Log.info(
                "status-item frame on wrong screen; using click screen frame=\(clickScreen.frame) mouseX=\(mouse.x)",
                "controller"
            )
            return
        }

        anchorScreen = clickScreen ?? reportedScreen ?? NSScreen.main
        anchorCenterX = reportedRect.midX
        anchorTopY = reportedRect.minY - 2
    }

    private func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func screenIntersecting(_ rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) }
    }

    private func anchorScreenDescription() -> String {
        guard let frame = anchorScreen?.frame else { return "nil" }
        return "(\(Int(frame.minX)),\(Int(frame.minY))) \(Int(frame.width))x\(Int(frame.height))"
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
        let size = panel.frame.size
        var origin = NSPoint(
            x: anchorCenterX - size.width / 2,
            y: anchorTopY - size.height
        )
        // Clamp only against the click/status-item screen — never panel.screen or
        // NSScreen.main alone, which pull the window onto the wrong display when
        // monitors are stacked or the panel was last shown elsewhere.
        if let visible = screenForEdgeClamp()?.visibleFrame {
            origin = clampOrigin(origin, size: size, to: visible)
        }
        panel.setFrameOrigin(origin)
    }

    /// Screen used for edge clamping. Prefer the resolved click/status-item
    /// anchor; fall back to the screen containing the anchor point, then the
    /// status-item window's screen. Never `panel.screen` / `NSScreen.main` alone.
    private func screenForEdgeClamp() -> NSScreen? {
        if let anchorScreen { return anchorScreen }
        if let screen = screenContaining(NSPoint(x: anchorCenterX, y: anchorTopY)) {
            return screen
        }
        return statusItem?.button?.window?.screen
    }

    private func clampOrigin(_ origin: NSPoint, size: NSSize, to visible: NSRect) -> NSPoint {
        var origin = origin
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        if origin.y < visible.minY + 8 {
            origin.y = visible.minY + 8
        }
        // Keep the top tucked under the menu bar on this screen when possible.
        let maxTop = visible.maxY - 2
        if origin.y + size.height > maxTop {
            origin.y = maxTop - size.height
        }
        return origin
    }

    // Reposition (origin only) after AppKit resizes the window; never resize here (no loop).
    func windowDidResize(_ notification: Notification) {
        guard isPresented, !isSyncingSize else { return }
        pinToAnchor()
    }

    // Dismiss rules (when NOT pinned):
    //  1. App deactivation (clicked another app/window): didResignActiveNotification.
    //     The macOS emoji/character viewer is a NON-activating panel, so clicking an
    //     emoji keeps NOTR active and the panel stays open. (A plain global mouse-down
    //     monitor that closed on any outside click would wrongly swallow that emoji click.)
    //  2. Clicking ANOTHER menu-bar item: no resign-active fires for that (the other item
    //     just opens a tracking menu), so NOTR would otherwise linger underneath it. The
    //     global mouse-down monitor closes NOTR for those clicks, but ONLY when the click
    //     lands in the menu-bar strip — never for the emoji viewer, which floats below it.
    // When pinned (isPanelPinned): skip both auto-dismiss paths so the panel stays hovering
    // while the user works in other apps. Explicit hide via status-item toggle still works.
    // Clicking our own status item keeps the app active and is handled by the toggle action.
    private func installDismissObserver() {
        removeDismissObserver()
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.appState.isPanelPinned {
                Log.info("app resigned active; staying open (pinned)", "controller")
                return
            }
            Log.info("app resigned active; dismissing panel", "controller")
            self.hide()
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

    private func handlePinChanged(_ pinned: Bool) {
        guard isPresented else { return }
        if pinned {
            // Keep floating above other apps while the user works elsewhere.
            panel?.level = .floating
            panel?.orderFrontRegardless()
            Log.info("panel pinned; auto-dismiss disabled", "controller")
        } else {
            panel?.level = .popUpMenu
            Log.info("panel unpinned; auto-dismiss re-enabled", "controller")
            // If they unpinned after switching away, close like a normal menu-bar item.
            if NSApp.isActive == false {
                hide()
            }
        }
    }

    /// Close when the user clicks a DIFFERENT menu-bar item, so it doesn't open underneath
    /// NOTR. Deliberately ignores non-menu-bar outside clicks so the emoji/character viewer
    /// (a non-activating panel below the menu bar) keeps working.
    private func dismissIfMenuBarClick() {
        guard isPresented, let panel else { return }
        if appState.isPanelPinned { return }

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
        let screen = screenContaining(point)
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
        panel.level = appState.isPanelPinned ? .floating : .popUpMenu
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
