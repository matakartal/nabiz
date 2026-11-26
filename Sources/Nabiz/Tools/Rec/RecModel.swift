import AppKit

/// Where the pointer was during a recording, and where it clicked. Positions are in the recorded area's pixels,
/// origin top-left; times are seconds from the first frame. Kept apart from the video so the pointer can be redrawn
/// smooth and larger, and so clicks can drive the automatic zoom.
struct RecTrack: Codable, Sendable {
    struct Point: Codable, Sendable {
        var t: Double
        var x: Double
        var y: Double
    }

    /// The pointer's look changing: an index into the recording's cursor images.
    struct Shape: Codable, Sendable {
        var t: Double
        var index: Int
    }

    var moves: [Point] = []
    var clicks: [Point] = []
    var shapes: [Shape] = []
}

/// One pointer image seen during the recording (arrow, I-beam, hand…), in points, with its hot spot.
struct RecCursor: Codable, Sendable {
    var file: String
    var width: Double
    var height: Double
    var hotX: Double
    var hotY: Double
}

/// One recording on disk: a folder with `video.mov` and `recording.json`.
struct RecMeta: Codable, Sendable {
    var id: UUID
    var created: Date
    var duration: Double
    /// The video's size in pixels.
    var width: Int
    var height: Int
    /// Pixels per point of the screen it came from.
    var scale: Double
    var track: RecTrack
    var edit: RecEdit
    var cursors: [RecCursor] = []
}

/// The look of a recording: frame, pointer, zoom. Saved with it and remembered for the next one.
struct RecStyle: Codable, Sendable, Equatable {
    var background = 0
    /// Room around the video, as a share of its width.
    var padding = 0.07
    /// Corner radius, as a share of the video's width.
    var radius = 0.012
    var shadow = true
    var cursorSize = 1.6
    var smoothCursor = true
    var clickRings = true
    var autoZoom = true
    var zoomLevel = 2.0

    static var saved: RecStyle {
        guard let data = UserDefaults.standard.data(forKey: "rec.style"),
              let style = try? JSONDecoder().decode(RecStyle.self, from: data) else { return RecStyle() }
        return style
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "rec.style") }
    }
}

/// A stretch of the recording shown closer, following the pointer.
struct RecZoom: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var start: Double
    var end: Double
    var scale: Double
}

/// Everything changed in the editor; the video itself is never touched.
struct RecEdit: Codable, Sendable, Equatable {
    var style = RecStyle.saved
    var zooms: [RecZoom] = []
    /// Kept part, in seconds; `trimEnd` 0 means the end.
    var trimStart = 0.0
    var trimEnd = 0.0
    /// Set once the zooms were made from the clicks, so a user's deletions stay deleted.
    var zoomsMade = false

    /// Zooms around bursts of clicks: from a moment before the first click to a little after the last.
    static func autoZooms(from clicks: [RecTrack.Point], duration: Double, scale: Double) -> [RecZoom] {
        var groups: [[RecTrack.Point]] = []
        // Clicks in the last second are usually the one that stops the recording.
        for click in clicks.sorted(by: { $0.t < $1.t }) where click.t < duration - 1 {
            if let last = groups.last?.last, click.t - last.t < 2.5 { groups[groups.count - 1].append(click) } else { groups.append([click]) }
        }
        var zooms: [RecZoom] = []
        for group in groups {
            guard let first = group.first, let last = group.last else { continue }
            var start = max(0, first.t - 0.3), end = min(duration - 0.3, last.t + 2.5)
            if end - start < 1.6 { end = min(duration, start + 1.6) }
            if let previous = zooms.last, start - previous.end < 0.8 {
                zooms[zooms.count - 1].end = end
                continue
            }
            start = max(start, zooms.last?.end ?? 0)
            if end > start + 0.3 { zooms.append(RecZoom(start: start, end: end, scale: scale)) }
        }
        return zooms
    }
}

enum RecStore {
    /// ~/Library/Application Support/Nabiz/Recordings
    static var folder: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nabiz/Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func folder(for id: UUID) -> URL { folder.appendingPathComponent(id.uuidString, isDirectory: true) }
    static func video(for id: UUID) -> URL { folder(for: id).appendingPathComponent("video.mov") }

    static func save(_ meta: RecMeta) {
        let url = folder(for: meta.id).appendingPathComponent("recording.json")
        if let data = try? JSONEncoder().encode(meta) { try? data.write(to: url, options: .atomic) }
    }

    static func load(_ id: UUID) -> RecMeta? {
        let url = folder(for: id).appendingPathComponent("recording.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RecMeta.self, from: data)
    }

    /// Recordings, newest first.
    static func all() -> [RecMeta] {
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return ids.compactMap(UUID.init(uuidString:)).compactMap(load).sorted { $0.created > $1.created }
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(for: id))
    }
}
