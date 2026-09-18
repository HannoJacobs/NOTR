import AppKit
import SwiftUI

/// Drag callbacks the panel controller hands down to the SwiftUI chrome.
struct PanelDragActions {
    var began: () -> Void = {}
    /// Screen-space translation since mouse-down (y up, matching `NSWindow` origin).
    var changed: (CGSize) -> Void = { _ in }
    var ended: () -> Void = {}
}

/// Grip that moves the panel, and tears it off the menu bar when dragged far enough.
///
/// AppKit rather than a SwiftUI `DragGesture`: the window must track the cursor 1:1
/// in screen coordinates, with no gesture-recognizer latency and no flipped-coordinate
/// conversion.
struct PanelDragHandle: NSViewRepresentable {
    let onBegan: () -> Void
    let onChanged: (CGSize) -> Void
    let onEnded: () -> Void
    /// Double-click toggles detach/reattach, the way a title bar zooms.
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> PanelDragHandleView {
        let view = PanelDragHandleView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: PanelDragHandleView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: PanelDragHandleView) {
        view.onBegan = onBegan
        view.onChanged = onChanged
        view.onEnded = onEnded
        view.onDoubleClick = onDoubleClick
    }
}

final class PanelDragHandleView: NSView {
    var onBegan: (() -> Void)?
    var onChanged: ((CGSize) -> Void)?
    var onEnded: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    static let handleWidth: CGFloat = 28
    static let handleHeight: CGFloat = 28

    /// Cursor position at mouse-down, in screen space. `nil` when not dragging.
    private var dragAnchor: NSPoint?

    /// NOTR sizes its window from `hostingController.view.fittingSize`, so a view with
    /// no intrinsic size does not merely stretch — it inflates the whole panel to the
    /// clamp ceiling. This must stay definite in BOTH axes.
    override var intrinsicContentSize: NSSize {
        NSSize(width: PanelDragHandleView.handleWidth, height: PanelDragHandleView.handleHeight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            dragAnchor = nil
            onDoubleClick?()
            return
        }
        dragAnchor = NSEvent.mouseLocation
        onBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragAnchor else { return }
        let current = NSEvent.mouseLocation
        onChanged?(
            CGSize(
                width: current.x - dragAnchor.x,
                height: current.y - dragAnchor.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard dragAnchor != nil else { return }
        dragAnchor = nil
        onEnded?()
    }
}
