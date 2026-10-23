import AppKit
import SwiftUI
import XCTest
@testable import NOTR

final class EditorFocusTests: XCTestCase {
    @MainActor
    func testQueuedFocusCannotShowAHiddenWindow() async {
        let (window, scrollView, textView, coordinator) = makeEditor()
        defer { window.close() }

        coordinator.focusIfNeeded(scrollView: scrollView, textView: textView, token: UUID())
        await drainFocusQueue()

        XCTAssertFalse(window.isVisible, "A focus callback must not present a hidden panel")
        withExtendedLifetime(coordinator) {}
    }

    @MainActor
    func testDismissalWinsOverAlreadyQueuedFocus() async {
        let (window, scrollView, textView, coordinator) = makeEditor()
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.isVisible)

        coordinator.focusIfNeeded(scrollView: scrollView, textView: textView, token: UUID())
        window.orderOut(nil)
        await drainFocusQueue()

        XCTAssertFalse(window.isVisible, "Clicking away must win over deferred editor focus")
        withExtendedLifetime(coordinator) {}
    }

    @MainActor
    private func makeEditor() -> (NSWindow, NSScrollView, NSTextView, PlainTextEditor.Coordinator) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scrollView = NSTextView.scrollableTextView()
        window.contentView = scrollView
        let textView = scrollView.documentView as! NSTextView
        let editor = PlainTextEditor(text: .constant(""), isLineWrappingEnabled: true,
                                     onTextChange: { _ in }, focusToken: nil)
        return (window, scrollView, textView, editor.makeCoordinator())
    }

    private func drainFocusQueue() async {
        // Suspend the test so GCD actually runs the queued callback. A nested
        // RunLoop inside a MainActor block does not drain the main dispatch queue.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
