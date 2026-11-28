// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit

/// Nabız opened straight from the disk image, from Downloads, or from the read-only copy macOS makes of a
/// downloaded app: it can't update itself or stay put at login there. Offers once per version to move it to
/// Applications (or ~/Applications when that isn't writable) and reopens it from there.
@MainActor
enum AppMover {
    private static let declinedKey = "appMover.declinedVersion"

    enum Place: Equatable { case translocated, diskImage, downloads }

    /// Where an app at this path is running from, if it is a place it shouldn't stay.
    static func place(of path: String, home: String = NSHomeDirectory()) -> Place? {
        guard path.hasSuffix(".app") else { return nil }
        if path.contains("/AppTranslocation/") { return .translocated }
        if path.hasPrefix("/Volumes/") { return .diskImage }
        if path.hasPrefix(home + "/Downloads/") { return .downloads }
        return nil
    }

    static func offerIfNeeded() {
        let source = Bundle.main.bundleURL
        guard let place = place(of: source.path),
              UserDefaults.standard.string(forKey: declinedKey) != Updater.current else { return }
        let alert = NSAlert()
        alert.messageText = L("Nabız Uygulamalar klasörüne taşınsın mı?", "Move Nabız to Applications?")
        let whereNow = switch place {
        case .diskImage: L("disk görüntüsünden", "the disk image")
        case .downloads, .translocated: L("İndirilenler'den", "Downloads")
        }
        alert.informativeText = L("Nabız şu an \(whereNow) çalışıyor. Uygulamalar'da kendini güncelleyebilir ve Mac açılınca açılabilir.",
                                  "Nabız is running from \(whereNow). In Applications it can update itself and open when the Mac starts.")
        alert.addButton(withTitle: L("Uygulamalar'a taşı", "Move to Applications"))
        alert.addButton(withTitle: L("Şimdi değil", "Not now"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(Updater.current, forKey: declinedKey)
            return
        }
        move(from: source, place: place)
    }

    /// /Applications when Nabız may write there, otherwise the person's own Applications folder.
    static var destinationFolder: URL {
        let shared = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if FileManager.default.isWritableFile(atPath: shared.path) { return shared }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    }

    private static func move(from source: URL, place: Place) {
        let folder = destinationFolder
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        Task {
            let failure: String? = await Task.detached(priority: .userInitiated) {
                let manager = FileManager.default
                do {
                    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                    // An older copy already there goes to the Trash, so it can still be got back.
                    if manager.fileExists(atPath: destination.path) { try manager.trashItem(at: destination, resultingItemURL: nil) }
                    try manager.copyItem(at: source, to: destination)
                } catch {
                    return error.localizedDescription
                }
                // The copy keeps the download's quarantine flag, which would make macOS run it from a read-only
                // copy again; the person already chose to open this app.
                let xattr = Process()
                xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                xattr.arguments = ["-d", "-r", "com.apple.quarantine", destination.path]
                try? xattr.run()
                xattr.waitUntilExit()
                // The original in Downloads isn't needed any more.
                if place == .downloads { try? manager.trashItem(at: source, resultingItemURL: nil) }
                return nil
            }.value
            if let failure {
                let alert = NSAlert()
                alert.messageText = L("Taşınamadı", "Couldn't move Nabız")
                alert.informativeText = L("\(failure)\n\nNabız'ı Finder'da Uygulamalar klasörüne kendin sürükleyebilirsin.",
                                          "\(failure)\n\nYou can drag Nabız into the Applications folder in Finder yourself.")
                alert.runModal()
                return
            }
            relaunch(destination, ejecting: place == .diskImage ? volume(of: source) : nil)
        }
    }

    /// "/Volumes/Nabiz" for an app inside it.
    private static func volume(of url: URL) -> String? {
        let parts = url.pathComponents
        guard parts.count > 2, parts[1] == "Volumes" else { return nil }
        return "/Volumes/" + parts[2]
    }

    /// Opens the moved copy once this one has quit, and ejects the disk image it came from.
    private static func relaunch(_ app: URL, ejecting volume: String?) {
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        /usr/bin/open "$2"
        [ -n "$3" ] && /usr/bin/hdiutil detach "$3" -quiet
        exit 0
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "nabiz-move", String(ProcessInfo.processInfo.processIdentifier), app.path, volume ?? ""]
        try? process.run()
        NSApp.terminate(nil)
    }
}
