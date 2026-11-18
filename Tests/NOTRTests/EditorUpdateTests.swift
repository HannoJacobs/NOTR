import AppKit
import SwiftUI
import XCTest
@testable import NOTR

final class EditorUpdateTests: XCTestCase {
    @MainActor
    func testUnchangedTextDoesNotRewriteAppKitAttributes() async throws {
        let content = "First paragraph\n\nSecond paragraph\n\nFinal line"
        let editor = PlainTextEditor(text: .constant(content), isLineWrappingEnabled: true,
                                     focusToken: nil)
        let (window, host) = hostEditor(editor)
        defer { window.close() }

        let scrollView = try XCTUnwrap(findScrollView(in: host))
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        let storage = try XCTUnwrap(textView.textStorage)
        var attributeEdits: [NSRange] = []
        let observation = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: .main
        ) { notification in
            let storage = notification.object as! NSTextStorage
            if storage.editedMask.contains(.editedAttributes) {
                attributeEdits.append(storage.editedRange)
            }
        }
        defer { NotificationCenter.default.removeObserver(observation) }

        // A new focus token guarantees a real representable update with identical text.
        var updated = editor
        updated.focusToken = UUID()
        host.rootView = updated
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        host.layoutSubtreeIfNeeded()

        XCTAssertTrue(scrollView === findScrollView(in: host))
        XCTAssertEqual(textView.string, content)
        XCTAssertTrue(attributeEdits.isEmpty, "Reapplied text attributes in ranges \(attributeEdits)")
    }

    @MainActor
    func testReenablingWrapRestoresViewportWidth() throws {
        let editor = PlainTextEditor(text: .constant(String(repeating: "long line ", count: 30)),
                                     isLineWrappingEnabled: false, focusToken: nil)
        let (window, host) = hostEditor(editor)
        defer { window.close() }
        let scrollView = try XCTUnwrap(findScrollView(in: host))
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        let container = try XCTUnwrap(textView.textContainer)
        XCTAssertTrue(scrollView.hasHorizontalScroller)
        XCTAssertGreaterThan(textView.frame.width, scrollView.contentSize.width)

        var wrapped = editor
        wrapped.isLineWrappingEnabled = true
        host.rootView = wrapped
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertEqual(container.size.width, scrollView.contentSize.width, accuracy: 1)

        window.setContentSize(NSSize(width: 220, height: 200))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(container.size.width, 220, accuracy: 1)
    }

    @MainActor
    private func hostEditor(_ editor: PlainTextEditor) -> (NSWindow, NSHostingView<PlainTextEditor>) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: editor)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return (window, host)
    }

    @MainActor
    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
    }
}
