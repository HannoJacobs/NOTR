import Foundation

struct PinnedNote: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var path: String
    var width: Double
    var height: Double

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var displayName: String {
        url.lastPathComponent
    }

    var directoryHint: String {
        url.deletingLastPathComponent().path.replacingOccurrences(
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
