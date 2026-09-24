import Foundation

struct PinnedNote: Identifiable, Codable, Equatable, Hashable {
    /// Enough room for roughly two short words in the monospaced editor.
    static let minimumWidth: Double = 110
    /// Keeps one editable line and the resize handle reachable.
    static let minimumHeight: Double = 48

    var id: UUID
    var path: String
    var width: Double
    var height: Double

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var isUntitledDraft: Bool {
        path.isEmpty
    }

    var displayName: String {
        if isUntitledDraft { return "Untitled" }
        return url.lastPathComponent
    }

    var directoryHint: String {
        if isUntitledDraft { return "Not saved yet" }
        return url.deletingLastPathComponent().path.replacingOccurrences(
            of: NSHomeDirectory(),
            with: "~"
        )
    }

    init(
        id: UUID = UUID(),
        path: String,
        width: Double = 420,
        height: Double = 360
    ) {
        self.id = id
        self.path = path
        self.width = width
        self.height = height
    }
}
