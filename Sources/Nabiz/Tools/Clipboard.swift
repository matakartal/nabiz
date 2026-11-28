// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import CryptoKit
import Observation

/// One thing that was copied: text, a link, files, or an image.
struct ClipItem: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case text, link, files, image, color }

    var id = UUID()
    var kind: Kind
    var text: String?
    /// The same text with its formatting (from Mail, Pages, a web page), pasted unless plain text is asked for.
    var rtf: Data?
    var html: Data?
    var files: [String]?
    /// Only read from histories saved before 1.8; images now live in their own encrypted files.
    var image: Data?
    /// SHA-256 of an image's PNG, to spot the same picture copied again without keeping it in memory.
    var imageHash: String?
    var date: Date
    /// The app it was copied from.
    var app: String?
    var pinned = false

    /// One line for lists.
    var preview: String {
        switch kind {
        case .text, .link, .color:
            return (text ?? "").replacingOccurrences(of: "\n", with: " ⏎ ").trimmingCharacters(in: .whitespaces)
        case .files:
            let names = (files ?? []).map { ($0 as NSString).lastPathComponent }
            return names.count > 1 ? L("\(names.count) dosya: ", "\(names.count) files: ") + names.joined(separator: ", ") : (names.first ?? "")
        case .image:
            return L("Görsel", "Image")
        }
    }

    var symbol: String {
        switch kind {
        case .text: "doc.plaintext"
        case .link: "link"
        case .files: "doc.on.doc"
        case .image: "photo"
        case .color: "paintpalette"
        }
    }
}

/// Encrypts the clipboard history on disk (AES-GCM) with a key kept in the login Keychain, so a copy of the files
/// alone reveals nothing. Only this Mac's user can read it back.
enum ClipVault {
    private static let service = "app.nabiz.clipboard"
    nonisolated(unsafe) private static var cached: SymmetricKey?

    static var key: SymmetricKey? {
        if let cached { return cached }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: "history-key", kSecReturnData as String: true]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, data.count == 32 {
            cached = SymmetricKey(data: data)
            return cached
        }
        let fresh = SymmetricKey(size: .bits256)
        let data = fresh.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: "history-key", kSecValueData as String: data,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                  kSecAttrLabel as String: "Nabız clipboard history"]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return nil }
        cached = fresh
        return fresh
    }

    static func seal(_ data: Data) -> Data? {
        guard let key else { return nil }
        return try? AES.GCM.seal(data, using: key).combined
    }

    static func open(_ data: Data) -> Data? {
        guard let key, let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }
}

/// Everything copied, newest first. Polls the pasteboard twice a second (macOS has no copy notification).
/// Never records what password managers mark as concealed or transient, nor anything copied in an excluded app.
/// Text stays in memory; pictures are written to encrypted files and read back only when shown or pasted.
@MainActor
@Observable
final class ClipboardHistory {
    static let shared = ClipboardHistory()
    static let maxImageBytes = 3 << 20
    static let maxRichBytes = 512 << 10

    private(set) var items: [ClipItem] = []
    @ObservationIgnored private var changeCount = NSPasteboard.general.changeCount
    @ObservationIgnored private var timer: Timer?
    /// Set when Nabız itself writes the pasteboard, so its own copy isn't recorded again.
    @ObservationIgnored private var ownChange: Int?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// Apps whose copies are never kept.
    static let defaultExcluded = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal", "com.apple.keychainaccess", "com.apple.Passwords", "org.keepassxc.keepassxc",
    ]

    private static var folder: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nabiz")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    private static var file: URL { folder.appendingPathComponent("clipboard.bin") }
    private static var legacyFile: URL { folder.appendingPathComponent("clipboard.json") }
    private static var imageFolder: URL {
        let url = folder.appendingPathComponent("ClipImages")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private static func imageURL(_ id: UUID) -> URL { imageFolder.appendingPathComponent("\(id.uuidString).bin") }

    init() {
        if Prefs.bool(Prefs.clipboardSave) {
            if let sealed = try? Data(contentsOf: Self.file), let data = ClipVault.open(sealed) {
                items = (try? JSONDecoder().decode([ClipItem].self, from: data)) ?? []
            } else if let data = try? Data(contentsOf: Self.legacyFile) {
                // Before 1.8: plain JSON with pictures inside. Move the pictures out, encrypt, delete the old file.
                items = ((try? JSONDecoder().decode([ClipItem].self, from: data)) ?? []).map { item in
                    var item = item
                    if let image = item.image {
                        item.imageHash = Self.hash(image)
                        Self.writeImage(image, id: item.id)
                        item.image = nil
                    }
                    return item
                }
                saveNow()
                try? FileManager.default.removeItem(at: Self.legacyFile)
            }
        } else {
            try? FileManager.default.removeItem(at: Self.imageFolder)
        }
        prune()
    }

    /// Starts or stops watching, following the setting.
    func update() {
        if Prefs.bool(Prefs.clipboardEnabled) {
            guard timer == nil else { return }
            changeCount = NSPasteboard.general.changeCount
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            timer?.tolerance = 0.2
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        if ownChange == changeCount { return }
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        // nspasteboard.org markers: password managers flag secrets as concealed, and apps flag scratch copies.
        let skip = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
                    "com.agilebits.onepassword"]
        if !types.isDisjoint(with: skip) { return }
        let front = NSWorkspace.shared.frontmostApplication
        let excluded = Set(Self.defaultExcluded).union(Prefs.string(Prefs.clipboardExcluded).split(separator: ",").map(String.init))
        if let bundle = front?.bundleIdentifier, excluded.contains(bundle) { return }
        read(pasteboard, app: front?.localizedName)
    }

    private func read(_ pasteboard: NSPasteboard, app: String?) {
        let now = Date()
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            insert(ClipItem(kind: .files, files: urls.map(\.path), date: now, app: app))
            return
        }
        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind: ClipItem.Kind = trimmed.range(of: #"^#(?:[0-9a-fA-F]{3}){1,2}$"#, options: .regularExpression) != nil ? .color
                : (URL(string: trimmed)?.scheme.map { ["http", "https"].contains($0) } ?? false) && !trimmed.contains(" ") ? .link : .text
            // Formatting is kept only for prose, and only while it stays small.
            let rich: (NSPasteboard.PasteboardType) -> Data? = { type in
                guard kind == .text, let data = pasteboard.data(forType: type), data.count <= Self.maxRichBytes else { return nil }
                return data
            }
            insert(ClipItem(kind: kind, text: text, rtf: rich(.rtf), html: rich(.html), date: now, app: app))
            return
        }
        // Pictures: converting a big TIFF to PNG takes a moment, so it happens off the main thread.
        let png = pasteboard.data(forType: .png)
        let tiff = png == nil ? pasteboard.data(forType: .tiff) : nil
        guard png != nil || tiff != nil else { return }
        Task {
            let data = await Task.detached(priority: .utility) {
                png ?? tiff.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
            }.value
            guard let data, data.count <= Self.maxImageBytes else { return }
            let hash = Self.hash(data)
            if let index = items.firstIndex(where: { $0.imageHash == hash }) {
                var existing = items.remove(at: index)
                existing.date = now
                items.insert(existing, at: 0)
            } else {
                let item = ClipItem(kind: .image, imageHash: hash, date: now, app: app)
                Self.writeImage(data, id: item.id)
                items.insert(item, at: 0)
                prune()
            }
            scheduleSave()
        }
    }

    private func insert(_ item: ClipItem) {
        // The same text again moves to the top instead of repeating.
        if let index = items.firstIndex(where: { $0.kind == item.kind && $0.text == item.text && $0.files == item.files }) {
            var existing = items.remove(at: index)
            existing.date = item.date
            existing.app = item.app
            existing.rtf = item.rtf
            existing.html = item.html
            items.insert(existing, at: 0)
        } else {
            items.insert(item, at: 0)
        }
        prune()
        scheduleSave()
    }

    /// Keeps the newest `clipboardLimit` items and drops ones older than `clipboardDays`; pinned items always stay.
    private func prune() {
        let limit = max(Prefs.int(Prefs.clipboardLimit), 10)
        let days = Prefs.int(Prefs.clipboardDays)
        var kept = 0
        var dropped: [ClipItem] = []
        items = items.filter { item in
            if item.pinned { return true }
            if days > 0, Date().timeIntervalSince(item.date) > Double(days) * 86_400 { dropped.append(item); return false }
            kept += 1
            if kept > limit { dropped.append(item); return false }
            return true
        }
        dropped.filter { $0.kind == .image }.forEach { try? FileManager.default.removeItem(at: Self.imageURL($0.id)) }
    }

    // MARK: Storage

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func writeImage(_ data: Data, id: UUID) {
        guard let sealed = ClipVault.seal(data) else { return }
        try? sealed.write(to: imageURL(id), options: .atomic)
    }

    /// The picture of an image item, read and decrypted from its file.
    func imageData(_ item: ClipItem) -> Data? {
        if let image = item.image { return image }
        guard let sealed = try? Data(contentsOf: Self.imageURL(item.id)) else { return nil }
        return ClipVault.open(sealed)
    }

    /// Writes a moment after the last change, so a burst of copies is one write.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func save() { scheduleSave() }

    func saveNow() {
        saveTask?.cancel()
        guard Prefs.bool(Prefs.clipboardSave) else {
            try? FileManager.default.removeItem(at: Self.file)
            return
        }
        guard let data = try? JSONEncoder().encode(items), let sealed = ClipVault.seal(data) else { return }
        try? sealed.write(to: Self.file, options: .atomic)
    }

    // MARK: Actions

    /// Text Nabız puts on the clipboard itself (a result, a script's output, something to paste): not kept in the
    /// history, since the user didn't copy it.
    func writeOwn(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        markOwn()
    }

    /// What is on the pasteboard now was written by Nabız.
    func markOwn() {
        ownChange = NSPasteboard.general.changeCount
    }

    /// Puts the item back on the pasteboard (and moves it to the top); with its formatting unless `plain`.
    func copy(_ item: ClipItem, plain: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .files:
            pasteboard.writeObjects((item.files ?? []).map { URL(fileURLWithPath: $0) as NSURL })
        case .image:
            if let image = imageData(item) { pasteboard.setData(image, forType: .png) }
        case .text, .link, .color:
            pasteboard.setString(item.text ?? "", forType: .string)
            if !plain {
                if let rtf = item.rtf { pasteboard.setData(rtf, forType: .rtf) }
                if let html = item.html { pasteboard.setData(html, forType: .html) }
            }
        }
        ownChange = pasteboard.changeCount
        changeCount = pasteboard.changeCount
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var moved = items.remove(at: index)
            moved.date = Date()
            items.insert(moved, at: 0)
            scheduleSave()
        }
    }

    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
        scheduleSave()
    }

    func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        if item.kind == .image { try? FileManager.default.removeItem(at: Self.imageURL(item.id)) }
        scheduleSave()
    }

    /// Everything but pinned items.
    func clear() {
        let removed = items.filter { !$0.pinned }
        items.removeAll { !$0.pinned }
        removed.filter { $0.kind == .image }.forEach { try? FileManager.default.removeItem(at: Self.imageURL($0.id)) }
        saveNow()
    }
}

/// Pastes into the app in front by sending ⌘V. Needs Accessibility permission; without it, things are only copied.
@MainActor
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Pasting is on in Settings and macOS allows it.
    static var canPaste: Bool { Prefs.bool(Prefs.autoPaste) && isTrusted }

    /// Shows the system prompt that opens Privacy & Security → Accessibility.
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func paste() {
        // Give the launcher a moment to leave so the keystroke reaches the app that had the cursor.
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            key(0x09, flags: .maskCommand)
        }
    }

    /// Pastes text where the cursor is without it becoming the user's clipboard: what was copied before comes back
    /// once the paste has landed (unless something new was copied meanwhile). `cursorBack` moves the cursor that many
    /// characters left afterwards, for a snippet's {cursor}. Needs `canPaste`.
    static func paste(_ text: String, cursorBack: Int = 0, delay: Duration = .milliseconds(120)) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        ClipboardHistory.shared.writeOwn(text)
        let written = pasteboard.changeCount
        Task {
            try? await Task.sleep(for: delay)
            key(0x09, flags: .maskCommand)
            if cursorBack > 0 {
                try? await Task.sleep(for: .milliseconds(60))
                for _ in 0..<min(cursorBack, 2000) { key(0x7B) }
            }
            // The app reads the pasteboard when it handles ⌘V; give it time before putting the old one back.
            try? await Task.sleep(for: .milliseconds(600))
            guard pasteboard.changeCount == written else { return }
            pasteboard.clearContents()
            if !saved.isEmpty { pasteboard.writeObjects(saved) }
            ClipboardHistory.shared.markOwn()
        }
    }

    /// A copy of everything on the pasteboard, every type of every item.
    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    /// One key press, sent to the app in front.
    static func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
