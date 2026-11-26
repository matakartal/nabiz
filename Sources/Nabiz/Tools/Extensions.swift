// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import Observation

/// Files by name, through Spotlight's own index (the one Finder searches), newest used first.
@MainActor
@Observable
final class FileSearch {
    static let shared = FileSearch()

    private(set) var results: [URL] = []
    /// What `results` were found for.
    private(set) var term = ""
    private(set) var searching = false
    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pending: Task<Void, Never>?

    /// Folders full of build output and caches nobody wants in results.
    private static let skipped = ["/Library/", "/.", "/node_modules/", "/target/", "/DerivedData/", "/.build/", "/Pods/",
                                  "/build/", "/dist/", "/.Trash/", "/vendor/", "/__pycache__/"]

    /// Searches a moment after typing stops.
    func search(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        pending?.cancel()
        guard text != term else { return }
        guard text.count >= 2 else { stop(); term = text; results = []; return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            self?.start(text)
        }
    }

    func stop() {
        query?.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        query = nil
        searching = false
    }

    private func start(_ text: String) {
        stop()
        term = text
        searching = true
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, text)
        query.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        query.notificationBatchingInterval = 0.1
        let done = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { _ in
            MainActor.assumeIsolated { FileSearch.shared.collect(finished: true) }
        }
        let progress = NotificationCenter.default.addObserver(forName: .NSMetadataQueryGatheringProgress, object: query, queue: .main) { _ in
            MainActor.assumeIsolated { FileSearch.shared.collect(finished: false) }
        }
        observers = [done, progress]
        self.query = query
        query.start()
    }

    private func collect(finished: Bool) {
        guard let query else { return }
        query.disableUpdates()
        var found: [URL] = []
        let count = min(query.resultCount, 400)
        for index in 0..<count {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !path.hasSuffix(".app"), !Self.skipped.contains(where: path.contains) else { continue }
            found.append(URL(fileURLWithPath: path))
            if found.count >= 30 { break }
        }
        query.enableUpdates()
        results = found
        if finished { stop() }
    }
}

/// Shortcuts from the Shortcuts app, and your own scripts, as launcher commands.
@MainActor
@Observable
final class Extensions {
    static let shared = Extensions()

    struct Script: Identifiable, Equatable {
        var id: String { path }
        let path: String
        let title: String
        let icon: String?
    }

    private(set) var shortcuts: [String] = []
    private(set) var scripts: [Script] = []
    @ObservationIgnored private var loadedAt: Date?

    static var scriptsFolder: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nabiz/Scripts")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func refreshIfNeeded(force: Bool = false) {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 60 { return }
        loadedAt = Date()
        scripts = Self.scanScripts()
        guard Prefs.bool(Prefs.launcherShortcuts) else { shortcuts = []; return }
        Task {
            let output = await Toolbox.run("/usr/bin/shortcuts", ["list"]) ?? ""
            shortcuts = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }

    /// Scripts in the folder; "# @nabiz.title" / "# @raycast.title" and ".icon" lines give them a name and an emoji.
    private static func scanScripts() -> [Script] {
        let folder = scriptsFolder
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().compactMap { name in
            let path = folder.appendingPathComponent(name).path
            guard let head = try? String(contentsOfFile: path, encoding: .utf8).prefix(2000) else { return nil }
            var title = (name as NSString).deletingPathExtension.replacingOccurrences(of: "-", with: " ")
            var icon: String?
            for line in head.split(separator: "\n") {
                let text = line.trimmingCharacters(in: .whitespaces)
                for tag in ["@nabiz.title", "@raycast.title"] where text.contains(tag) {
                    title = text.components(separatedBy: tag).last?.trimmingCharacters(in: .whitespaces) ?? title
                }
                for tag in ["@nabiz.icon", "@raycast.icon"] where text.contains(tag) {
                    icon = text.components(separatedBy: tag).last?.trimmingCharacters(in: .whitespaces)
                }
            }
            return Script(path: path, title: title, icon: icon?.count == 1 ? icon : nil)
        }
    }

    func runShortcut(_ name: String) {
        Monitor.panelActions.flash(L("Kestirme: \(name)", "Shortcut: \(name)"))
        Task { _ = await Toolbox.run("/usr/bin/shortcuts", ["run", name]) }
    }

    /// Runs a script with your login shell's PATH; whatever it prints is copied and shown.
    func run(_ script: Script) {
        let path = script.path
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (Int32, String) in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", "exec \"$0\"", path]
                if !FileManager.default.isExecutableFile(atPath: path) { process.arguments = ["-l", path] }
                process.currentDirectoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                guard (try? process.run()) != nil else { return (-1, "") }
                let data = pipe.fileHandleForReading.readDataToEndOfFile().prefix(65_536)
                process.waitUntilExit()
                return (process.terminationStatus, String(decoding: data, as: UTF8.self))
            }.value
            let output = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.0 != 0 {
                Monitor.panelActions.flash(L("Betik hata verdi", "Script failed") + (output.isEmpty ? "" : ": " + String(output.prefix(50))))
            } else if output.isEmpty {
                Monitor.panelActions.flash(L("\(script.title) çalıştı", "\(script.title) ran"))
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(output, forType: .string)
                Monitor.panelActions.flash(String(output.split(separator: "\n").first?.prefix(60) ?? ""))
            }
        }
    }

    /// A ready-made script that shows the format.
    func createSample() {
        let url = Self.scriptsFolder.appendingPathComponent("merhaba.sh")
        let text = """
        #!/bin/zsh
        # @nabiz.title \(L("Merhaba de", "Say hello"))
        # @nabiz.icon 👋
        # \(L("Yazdığı her şey panoya kopyalanır ve menü çubuğunda görünür.", "Whatever it prints is copied and shown in the menu bar."))
        echo "\(L("Merhaba", "Hello")) $(id -F), $(date +%H:%M)"

        """
        if !FileManager.default.fileExists(atPath: url.path) {
            try? text.write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        refreshIfNeeded(force: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// Every emoji with its Unicode name, searchable in English and common Turkish words (":kalp", ":heart").
@MainActor
enum EmojiIndex {
    struct Emoji: Sendable {
        let character: String
        let name: String
    }

    static let all: [Emoji] = {
        let ranges: [ClosedRange<UInt32>] = [0x1F300...0x1F5FF, 0x1F600...0x1F64F, 0x1F680...0x1F6FF, 0x1F900...0x1F9FF,
                                             0x1FA70...0x1FAFF, 0x2600...0x26FF, 0x2700...0x27BF]
        var list: [Emoji] = []
        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value), let name = scalar.properties.name else { continue }
                if scalar.properties.isEmojiPresentation {
                    list.append(Emoji(character: String(scalar), name: name.lowercased()))
                } else if scalar.properties.isEmoji, value >= 0x2600 {
                    // ❤ ☀ ✈ and friends draw as emoji with the variation selector.
                    list.append(Emoji(character: String(scalar) + "\u{FE0F}", name: name.lowercased()))
                }
            }
        }
        return list
    }()

    private static let turkish: [String: String] = [
        "kalp": "heart", "ask": "heart", "gul": "grinning", "gulen": "smiling", "gulme": "laugh", "kahkaha": "tears of joy",
        "uzgun": "sad", "aglama": "crying", "kizgin": "angry", "ofke": "angry", "ates": "fire", "alev": "fire", "yildiz": "star",
        "tamam": "ok hand", "ok": "ok hand", "basparmak": "thumbs up", "begen": "thumbs up", "alkis": "clapping", "el": "hand",
        "dua": "folded hands", "parti": "party", "kutlama": "party", "hediye": "gift", "pasta": "birthday cake", "kahve": "hot beverage",
        "cay": "teacup", "bira": "beer", "yemek": "fork and knife", "pizza": "pizza", "elma": "apple", "gunes": "sun", "ay": "moon",
        "yagmur": "rain", "kar": "snow", "bulut": "cloud", "simsek": "lightning", "roket": "rocket", "araba": "automobile",
        "ucak": "airplane", "ev": "house", "para": "money", "dolar": "dollar", "kedi": "cat", "kopek": "dog", "kus": "bird",
        "cicek": "flower", "agac": "tree", "kitap": "book", "telefon": "phone", "bilgisayar": "computer", "saat": "clock",
        "zil": "bell", "kilit": "lock", "anahtar": "key", "goz": "eyes", "dusunen": "thinking", "uyku": "sleeping",
        "hasta": "sick", "seytan": "devil", "melek": "angel", "hayalet": "ghost", "kafatasi": "skull", "tik": "check mark",
        "carpi": "cross mark", "uyari": "warning", "soru": "question", "unlem": "exclamation", "bayrak": "flag", "kupa": "trophy",
        "madalya": "medal", "top": "ball", "muzik": "music", "kamera": "camera", "hediye kutusu": "gift", "yuz": "face",
        "sarilma": "hugging", "opucuk": "kiss", "goz kirpma": "winking", "havai fisek": "fireworks", "100": "hundred points",
    ]

    static func search(_ query: String) -> [Emoji] {
        let term = Fuzzy.fold(query).trimmingCharacters(in: .whitespaces)
        let recent = UserDefaults.standard.stringArray(forKey: "emojiRecents") ?? []
        guard !term.isEmpty else {
            let recents = recent.compactMap { char in all.first { $0.character == char } }
            return recents + all.prefix(60).filter { emoji in !recent.contains(emoji.character) }
        }
        let english = turkish[term] ?? turkish.first { $0.key.hasPrefix(term) && term.count >= 3 }?.value ?? term
        let words = english.split(separator: " ").map(String.init)
        let matches = all.filter { emoji in words.allSatisfy { emoji.name.contains($0) } }
        // Whole-word hits and recently used first.
        return matches.sorted { a, b in
            let ar = recent.contains(a.character), br = recent.contains(b.character)
            if ar != br { return ar }
            let aw = a.name.split(separator: " ").contains { $0.hasPrefix(words[0]) }
            let bw = b.name.split(separator: " ").contains { $0.hasPrefix(words[0]) }
            if aw != bw { return aw }
            return a.name.count < b.name.count
        }
    }

    static func used(_ character: String) {
        var list = (UserDefaults.standard.stringArray(forKey: "emojiRecents") ?? []).filter { $0 != character }
        list.insert(character, at: 0)
        UserDefaults.standard.set(Array(list.prefix(16)), forKey: "emojiRecents")
    }
}
