// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import UniformTypeIdentifiers

/// One file with everything you set up: settings, snippets, quicklinks, shortcuts, aliases, window layouts, AI
/// commands, schedules and notes. Save it, move it to another Mac, load it there. Optionally a daily copy goes to
/// iCloud Drive. The clipboard history, caches and sign-ins are never included.
@MainActor
enum Backup {
    static let fileExtension = "nabizbackup"
    private static let lastKey = "lastAutoBackup"
    /// Not worth carrying to another Mac, or private to this one.
    private static let skipped: Set<String> = ["rateCache", "aiAlertLog", "launcherRecents", lastKey, "currentNote", "NSWindow Frame",
                                               "bluetoothAsked", "crashReports"]

    static var lastAutoBackup: Date? { UserDefaults.standard.object(forKey: lastKey) as? Date }

    /// iCloud Drive's own folder, when iCloud Drive is on.
    static var iCloudFolder: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appendingPathComponent(L("Nabız Yedekleri", "Nabiz Backups"))
    }

    static func data() -> Data? {
        guard let domain = Bundle.main.bundleIdentifier,
              let defaults = UserDefaults.standard.persistentDomain(forName: domain) else { return nil }
        let settings = defaults.filter { key, _ in !skipped.contains(key) && !key.hasPrefix("NS") }
        let notes = (try? JSONEncoder().encode(NoteStore.shared.notes)) ?? Data()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let file: [String: Any] = ["format": 1, "app": version, "created": Date(), "settings": settings, "notes": notes]
        return try? PropertyListSerialization.data(fromPropertyList: file, format: .binary, options: 0)
    }

    static var fileName: String {
        "Nabiz-\(Date().formatted(.iso8601.year().month().day())).\(fileExtension)"
    }

    /// Asks where, then saves.
    static func saveAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.allowedContentTypes = [UTType(filenameExtension: fileExtension) ?? .data]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = data(), (try? data.write(to: url, options: .atomic)) != nil else {
            Monitor.panelActions.flash(L("Yedek yazılamadı", "Couldn't write the backup"))
            return
        }
        Monitor.panelActions.flash(L("Yedeklendi", "Backed up"))
    }

    /// Once a day into iCloud Drive, keeping the last ten.
    static func autoBackupIfNeeded() {
        guard Prefs.bool(Prefs.autoBackup) else { return }
        if let last = lastAutoBackup, Date().timeIntervalSince(last) < 20 * 3600 { return }
        UserDefaults.standard.set(Date(), forKey: lastKey)
        guard let folder = iCloudFolder, let data = data() else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
        let old = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == fileExtension }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .dropFirst(10)
        old.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    /// Asks for a file, says what will change, loads it and restarts Nabız so everything reads it.
    static func restore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: fileExtension) ?? .data]
        panel.directoryURL = iCloudFolder
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let file = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let settings = file["settings"] as? [String: Any] else {
            alert(L("Bu bir Nabız yedeği değil.", "This isn't a Nabız backup."), "")
            return
        }
        let notes = (file["notes"] as? Data).flatMap { try? JSONDecoder().decode([Note].self, from: $0) } ?? []
        let created = (file["created"] as? Date)?.formatted(date: .abbreviated, time: .shortened) ?? "?"
        let confirm = NSAlert()
        confirm.messageText = L("Yedek yüklensin mi?", "Load this backup?")
        confirm.informativeText = L("\(created) tarihli yedek. Ayarlar, parçacıklar, bağlantılar, kısayollar ve yerleşimler bu yedektekilerle değişir; \(notes.count) not mevcut notlarına eklenir (aynı notun yenisi kalır). Nabız sonra yeniden açılır.",
                                    "Backup from \(created). Settings, snippets, quicklinks, shortcuts and layouts are replaced by the backup's; its \(notes.count) notes are added to yours (the newer copy of the same note stays). Nabız then restarts.")
        confirm.addButton(withTitle: L("Yükle", "Load"))
        confirm.addButton(withTitle: L("Vazgeç", "Cancel"))
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        for (key, value) in settings where !skipped.contains(key) { UserDefaults.standard.set(value, forKey: key) }
        NoteStore.shared.merge(notes)
        relaunch()
    }

    private static func relaunch() {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
