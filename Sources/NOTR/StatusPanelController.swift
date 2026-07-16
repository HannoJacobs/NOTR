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

    private var globalMonitor: Any?
    private var localMonitor: Any?

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
        installMonitors()
        Log.info("panel shown size=\(panel.frame.size) origin=\(panel.frame.origin)", "controller")
    }

    func hide() {
        guard isPresented else { return }
        appState.flushPendingSaveIfNeeded()
        removeMonitors()
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

    private func installMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.hide()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.window == self.panel { return event }
            if event.window == self.statusItem?.button?.window { return event }
            self.hide()
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
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
