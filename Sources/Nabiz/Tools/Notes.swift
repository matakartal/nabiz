// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Observation

/// One note. Its first line is its title; the rest is plain Markdown (headings, lists, checklists, **bold**, `code`).
struct Note: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var text: String
    var created = Date()
    var modified = Date()

    var title: String {
        let line = text.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(String.init) ?? ""
        let cleaned = line.replacingOccurrences(of: #"^\s*(#{1,6}\s+|[-*•]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+|>\s*)"#, with: "",
                                                options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? L("Yeni not", "New note") : String(cleaned.prefix(80))
    }

    /// The lines after the title, on one line.
    var preview: String {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.dropFirst().joined(separator: " ").prefix(140).description
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var words: Int { text.split { $0.isWhitespace || $0.isNewline }.count }

    /// Ticked and all checklist items.
    var checklist: (done: Int, total: Int) {
        var done = 0, total = 0
        for line in text.split(separator: "\n") {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            guard trimmed.count >= 5, "-*•".contains(trimmed.first!) else { continue }
            let box = trimmed.dropFirst(2).prefix(3)
            if box == "[ ]" { total += 1 } else if box == "[x]" || box == "[X]" { total += 1; done += 1 }
        }
        return (done, total)
    }
}

/// Every note, kept in Application Support as JSON and written shortly after each change.
@MainActor
@Observable
final class NoteStore {
    static let shared = NoteStore()

    private(set) var notes: [Note] = []
    private(set) var currentID: UUID? {
        didSet { UserDefaults.standard.set(currentID?.uuidString, forKey: "currentNote") }
    }
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private static var file: URL {
        // Snapshots point this at a sample file so they never touch real notes.
        if let path = ProcessInfo.processInfo.environment["NABIZ_NOTES_FILE"] { return URL(fileURLWithPath: path) }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nabiz")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("notes.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.file), let saved = try? JSONDecoder().decode([Note].self, from: data) {
            notes = saved
        } else if let old = UserDefaults.standard.string(forKey: Prefs.noteText), !old.isEmpty {
            // The single note of 1.5 becomes the first note.
            notes = [Note(text: old)]
            saveNow()
        }
        currentID = UserDefaults.standard.string(forKey: "currentNote").flatMap(UUID.init(uuidString:))
        if current == nil { currentID = sorted.first?.id }
    }

    /// Last edited first.
    var sorted: [Note] { notes.sorted { $0.modified > $1.modified } }

    var current: Note? { notes.first { $0.id == currentID } }

    /// Opens an empty note (reusing a blank one instead of piling them up), optionally with some text.
    @discardableResult
    func create(_ text: String = "") -> UUID {
        if let blank = notes.firstIndex(where: \.isEmpty) {
            notes[blank].text = text
            notes[blank].modified = Date()
            currentID = notes[blank].id
        } else {
            let note = Note(text: text)
            notes.append(note)
            currentID = note.id
        }
        scheduleSave()
        return currentID!
    }

    func update(_ id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        notes[index].text = text
        notes[index].modified = Date()
        scheduleSave()
    }

    /// Switches to a note; an empty note left behind is dropped.
    func select(_ id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        dropEmpty(keeping: id)
        currentID = id
    }

    /// The previous or next note in "last edited" order, wrapping around.
    func step(_ offset: Int) {
        let list = sorted
        guard list.count > 1, let index = list.firstIndex(where: { $0.id == currentID }) else { return }
        select(list[(index + offset + list.count) % list.count].id)
    }

    func delete(_ id: UUID) {
        let list = sorted
        let index = list.firstIndex { $0.id == id }
        notes.removeAll { $0.id == id }
        if currentID == id {
            let rest = sorted
            currentID = index.flatMap { rest.indices.contains($0) ? rest[$0].id : rest.last?.id }
        }
        saveNow()
    }

    func dropEmpty(keeping id: UUID? = nil) {
        let before = notes.count
        notes.removeAll { $0.isEmpty && $0.id != id }
        if notes.count != before {
            if let currentID, !notes.contains(where: { $0.id == currentID }) { self.currentID = sorted.first?.id }
            scheduleSave()
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Notes from a backup: new ones are added; for one that exists on both sides, the newer edit stays.
    func merge(_ incoming: [Note]) {
        for note in incoming where !note.isEmpty {
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                if note.modified > notes[index].modified { notes[index] = note }
            } else {
                notes.append(note)
            }
        }
        saveNow()
    }

    func saveNow() {
        saveTask?.cancel()
        if let data = try? JSONEncoder().encode(notes) { try? data.write(to: Self.file, options: [.atomic, .completeFileProtection]) }
    }
}

/// The small bit of Markdown the note editor understands, as plain functions so they can be tested.
enum NoteMarkdown {
    enum Return: Equatable {
        /// An ordinary new line.
        case plain
        /// An empty list item: Return removes its marker and ends the list.
        case end
        /// Continue the list with this text (a new line and the next marker).
        case next(String)
    }

    enum ListKind { case checklist, bullet }

    // indent, checklist bullet, box, bullet, number, number punctuation, content
    private static let listItem = try! NSRegularExpression(pattern: #"^([ \t]*)(?:([-*•]) \[([ xX])\] |([-*•]) |(\d{1,4})([.)]) )(.*)$"#)
    private static let anyMarker = try! NSRegularExpression(pattern: #"^([ \t]*)((?:[-*•] \[[ xX]\] )|(?:[-*•] )|(?:\d{1,4}[.)] ))?(.*)$"#)

    /// What Return does at the end of `line` (the text from the start of the line to the cursor).
    static func onReturn(_ line: String) -> Return {
        let ns = line as NSString
        guard let match = listItem.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return .plain }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
        let indent = group(1) ?? ""
        if (group(7) ?? "").trimmingCharacters(in: .whitespaces).isEmpty { return .end }
        if let bullet = group(2) { return .next("\n\(indent)\(bullet) [ ] ") }
        if let bullet = group(4) { return .next("\n\(indent)\(bullet) ") }
        if let number = group(5).flatMap(Int.init), let punctuation = group(6) { return .next("\n\(indent)\(number + 1)\(punctuation) ") }
        return .plain
    }

    /// Adds the marker to a line, or takes it off when the line already has that kind.
    static func toggled(_ line: String, _ kind: ListKind) -> String {
        let ns = line as NSString
        guard let match = anyMarker.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return line }
        let indent = ns.substring(with: match.range(at: 1))
        let marker = match.range(at: 2).location == NSNotFound ? "" : ns.substring(with: match.range(at: 2))
        let rest = ns.substring(with: match.range(at: 3))
        let isChecklist = marker.contains("[")
        let isBullet = !marker.isEmpty && !isChecklist && !(marker.first?.isNumber ?? false)
        switch kind {
        case .checklist: return isChecklist ? indent + rest : indent + "- [ ] " + rest
        case .bullet: return isBullet ? indent + rest : indent + "- " + rest
        }
    }

    /// Where "[ ]" or "[x]" sits in a checklist line (UTF-16 offsets), for clicking it.
    static func checkbox(in line: String) -> NSRange? {
        let ns = line as NSString
        guard let match = listItem.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.range(at: 3).location != NSNotFound else { return nil }
        return NSRange(location: match.range(at: 3).location - 1, length: 3)
    }
}

/// Quick changes to copied text, offered in the launcher's actions.
enum TextTransform: String, CaseIterable, Identifiable {
    case upper, lower, capitalized, trimmed, oneLine, json, base64Encode, base64Decode, urlEncode, urlDecode
    case jsonMinify, jwt, unixDate, camel, snake, kebab, sha256

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upper: L("BÜYÜK HARF", "UPPERCASE")
        case .lower: L("küçük harf", "lowercase")
        case .capitalized: L("Baş Harfler Büyük", "Title Case")
        case .trimmed: L("Fazla boşlukları sil", "Tidy spaces")
        case .oneLine: L("Tek satır yap", "Join into one line")
        case .json: L("JSON'u düzenle", "Pretty-print JSON")
        case .base64Encode: L("Base64'e çevir", "Encode Base64")
        case .base64Decode: L("Base64'ten çöz", "Decode Base64")
        case .urlEncode: L("URL için kodla", "URL-encode")
        case .urlDecode: L("URL kodunu çöz", "URL-decode")
        case .jsonMinify: L("JSON'u tek satır yap", "Minify JSON")
        case .jwt: L("JWT'yi çöz", "Decode the JWT")
        case .unixDate: L("Unix zamanını tarihe çevir", "Unix time to date")
        case .camel: "camelCase"
        case .snake: "snake_case"
        case .kebab: "kebab-case"
        case .sha256: "SHA-256"
        }
    }

    var symbol: String {
        switch self {
        case .upper, .lower, .capitalized: "textformat"
        case .trimmed, .oneLine: "text.alignleft"
        case .json: "curlybraces"
        case .base64Encode, .base64Decode: "lock.doc"
        case .urlEncode, .urlDecode: "link"
        case .jsonMinify: "curlybraces"
        case .jwt: "key"
        case .unixDate: "clock"
        case .camel, .snake, .kebab: "textformat"
        case .sha256: "number"
        }
    }

    /// The changed text, or nil when the change doesn't apply (not JSON, not Base64) or changes nothing.
    func apply(_ text: String) -> String? {
        let locale = Prefs.isTurkish ? Locale(identifier: "tr_TR") : Locale.current
        let result: String? = switch self {
        case .upper: text.uppercased(with: locale)
        case .lower: text.lowercased(with: locale)
        case .capitalized: text.capitalized(with: locale)
        case .trimmed:
            text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
                .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        case .oneLine:
            text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                .joined(separator: " ")
        case .json:
            (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]))
                .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) }
                .flatMap { String(data: $0, encoding: .utf8) }
        case .base64Encode: Data(text.utf8).base64EncodedString()
        case .base64Decode:
            Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { String(data: $0, encoding: .utf8) }
        case .urlEncode: text.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))
        case .urlDecode: text.removingPercentEncoding
        case .jsonMinify:
            (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]))
                .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]) }
                .flatMap { String(data: $0, encoding: .utf8) }
        case .jwt: DevUtils.jwt(text).map(\.payload)
        case .unixDate: DevUtils.epoch(text).map(DevUtils.iso8601)
        // Identifier cases only for a short one-line name, not prose.
        case .camel, .snake, .kebab:
            text.count <= 80 && !text.contains("\n") && DevUtils.words(text).count > 1
                ? DevUtils.convert(text, to: self == .camel ? .camel : self == .snake ? .snake : .kebab) : nil
        case .sha256: text.isEmpty ? nil : DevUtils.hash(text, .sha256)
        }
        guard let result, result != text, !result.isEmpty else { return nil }
        return result
    }
}
