// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Observation

/// The recordings kept for the editor (not the videos exported from them): what there is, how much room it
/// takes, and clearing out old ones. Read off the main thread, only while Settings shows it.
@MainActor
@Observable
final class RecLibrary {
    static let shared = RecLibrary()

    struct Entry: Identifiable, Equatable, Sendable {
        let id: UUID
        let created: Date
        let duration: Double
        let bytes: UInt64
    }

    private(set) var entries: [Entry] = []
    private(set) var loaded = false
    var total: UInt64 { entries.reduce(0) { $0 + $1.bytes } }

    /// Reads the folder again (sizes included).
    func refresh() {
        Task {
            entries = await Task.detached(priority: .utility) { Self.scan() }.value
            loaded = true
        }
    }

    private nonisolated static func scan() -> [Entry] {
        RecStore.all().map { meta in
            Entry(id: meta.id, created: meta.created, duration: meta.duration, bytes: size(of: RecStore.folder(for: meta.id)))
        }
    }

    private nonisolated static func size(of folder: URL) -> UInt64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return 0 }
        var total: UInt64 = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            total += UInt64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Recordings made more than `days` days before `now`.
    nonisolated static func older(than days: Int, in entries: [Entry], now: Date = Date()) -> [Entry] {
        let limit = now.addingTimeInterval(-Double(days) * 86_400)
        return entries.filter { $0.created < limit }
    }

    /// Asks, then moves one recording to the Trash.
    func delete(_ entry: Entry) {
        RecEditor.confirmDelete(entry.id)
        refresh()
    }

    /// Asks, then moves every recording older than `days` days to the Trash.
    func deleteOlder(than days: Int) {
        let old = Self.older(than: days, in: entries)
        guard !old.isEmpty else { return }
        let alert = NSAlert()
        let size = Format.bytes(old.reduce(0) { $0 + $1.bytes })
        alert.messageText = L("\(old.count) kayıt silinsin mi?", "Delete \(old.count) recordings?")
        alert.informativeText = L("\(days) günden eski kayıtlar ve düzenlemeleri Çöp Sepeti'ne gider (\(size)). Dışa aktardığın videolar kalır.",
                                  "Recordings older than \(days) days and their edits go to the Trash (\(size)). Videos you exported stay.")
        alert.addButton(withTitle: L("Sil", "Delete"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var failed = 0
        for entry in old {
            _ = RecEditor.closeIfOpen(entry.id)
            if !RecStore.trash(entry.id) { failed += 1 }
        }
        if failed > 0 { Monitor.panelActions.flash(L("\(failed) kayıt silinemedi", "Couldn't delete \(failed) recordings")) }
        refresh()
    }
}
