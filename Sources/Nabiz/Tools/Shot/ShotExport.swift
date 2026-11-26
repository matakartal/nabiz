// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import UniformTypeIdentifiers

/// Getting a finished screenshot out: the clipboard, the screenshots folder, a file of your choosing, a drag.
@MainActor
enum ShotExport {
    /// Puts the image on the clipboard as PNG and TIFF, so every app can paste it.
    @discardableResult
    static func copy(_ doc: ShotDocument) -> Bool {
        guard let image = ShotRenderer.export(doc) else { return false }
        return copy(image, scale: doc.scale)
    }

    @discardableResult
    static func copy(_ image: CGImage, scale: CGFloat) -> Bool {
        guard let png = ShotRenderer.encode(image, type: "png", scale: scale) else { return false }
        let ns = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
        let board = NSPasteboard.general
        board.clearContents()
        board.declareTypes([.png, .tiff], owner: nil)
        board.setData(png, forType: .png)
        if let tiff = ns.tiffRepresentation { board.setData(tiff, forType: .tiff) }
        return true
    }

    /// The file type the system saves screenshots in; PDF and GIF become PNG.
    static var fileType: String {
        let type = Capture.type
        return ["png", "jpg", "jpeg", "heic", "tiff"].contains(type) ? type : "png"
    }

    /// Saves into the screenshots folder. A capture saved to a file a moment ago is replaced by the marked-up one.
    static func save(_ doc: ShotDocument) -> URL? {
        guard let image = ShotRenderer.export(doc) else { return nil }
        let url: URL
        if doc.replacesSource, let source = doc.source {
            url = source
        } else {
            let fresh = Capture.newFile()
            url = fresh.deletingPathExtension().appendingPathExtension(fileType == "jpeg" ? "jpg" : fileType)
        }
        let type = url.pathExtension.lowercased()
        guard let data = ShotRenderer.encode(image, type: type, scale: doc.scale), (try? data.write(to: url, options: .atomic)) != nil else {
            Monitor.panelActions.flash(L("Kaydedilemedi", "Couldn't save"))
            return nil
        }
        return url
    }

    static func saveAs(_ doc: ShotDocument, in window: NSWindow, done: @escaping (URL) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.directoryURL = Capture.folder
        panel.nameFieldStringValue = Capture.newFile().deletingPathExtension().lastPathComponent + ".png"
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url, let image = ShotRenderer.export(doc),
                      let data = ShotRenderer.encode(image, type: url.pathExtension.lowercased(), scale: doc.scale),
                      (try? data.write(to: url, options: .atomic)) != nil else { return }
                done(url)
            }
        }
    }

    /// A PNG in the caches folder, named like a screenshot, for dragging out and sharing.
    static func temporaryFile(_ doc: ShotDocument) -> URL? {
        guard let image = ShotRenderer.export(doc) else { return nil }
        return temporaryFile(image, scale: doc.scale)
    }

    static func temporaryFile(_ image: CGImage, scale: CGFloat) -> URL? {
        let folder = cacheFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(Capture.newFile().deletingPathExtension().lastPathComponent).appendingPathExtension("png")
        guard let data = ShotRenderer.encode(image, type: "png", scale: scale), (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    /// Captures waiting in the thumbnail, drag files and the like; emptied at launch and once a day.
    static var cacheFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nabiz/Shots", isDirectory: true)
    }

    /// Removes cached captures older than a day.
    static func cleanCache() {
        let folder = cacheFolder
        Task.detached(priority: .background) {
            let manager = FileManager.default
            guard let entries = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
            let limit = Date().addingTimeInterval(-86_400)
            for entry in entries {
                let date = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if date < limit { try? manager.removeItem(at: entry) }
            }
        }
    }

    /// Text (or a QR code) in the finished image.
    static func readText(_ doc: ShotDocument) async -> Recognizer.Found? {
        guard let url = temporaryFile(doc) else { return nil }
        let path = url.path
        let found = await Task.detached(priority: .userInitiated) { Recognizer.read(path) }.value
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        return found
    }
}
