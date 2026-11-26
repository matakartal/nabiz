import AppKit
import CoreImage.CIFilterBuiltins
import Vision

/// Screenshots through macOS's own `screencapture` and Screenshot app: the same selection, window picking, sound,
/// save location and file type the system uses (Screenshot app → Options), just one tap or keyword away.
enum CaptureMode: String, CaseIterable, Identifiable {
    case area, window, screen, areaFile, screenFile, timed, toolbar, text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: L("Alan seç → panoya", "Area → clipboard")
        case .window: L("Pencere seç → panoya", "Window → clipboard")
        case .screen: L("Tüm ekran → panoya", "Whole screen → clipboard")
        case .areaFile: L("Alan seç → dosyaya", "Area → file")
        case .screenFile: L("Tüm ekran → dosyaya", "Whole screen → file")
        case .timed: L("5 saniye sonra tüm ekran", "Whole screen in 5 seconds")
        case .toolbar: L("Kayıt ve diğer seçenekler (⇧⌘5)", "Record and more (⇧⌘5)")
        case .text: L("Ekrandan metin ya da QR oku", "Read text or a QR code on screen")
        }
    }

    /// Short, for the panel's chips.
    var chip: String {
        switch self {
        case .area: L("Alan", "Area")
        case .window: L("Pencere", "Window")
        case .screen: L("Ekran", "Screen")
        case .areaFile: L("Alan → dosya", "Area → file")
        case .screenFile: L("Ekran → dosya", "Screen → file")
        case .timed: L("5 sn", "5 s")
        case .toolbar: L("Kayıt", "Record")
        case .text: L("Metin", "Text")
        }
    }

    var symbol: String {
        switch self {
        case .area: "rectangle.dashed"
        case .window: "macwindow"
        case .screen: "display"
        case .areaFile: "rectangle.dashed.badge.record"
        case .screenFile: "photo.on.rectangle"
        case .timed: "timer"
        case .toolbar: "record.circle"
        case .text: "text.viewfinder"
        }
    }
}

@MainActor
enum Capture {
    /// Where the system saves screenshots (Screenshot app → Options → Save to), else the Desktop.
    static var folder: URL {
        if let path = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
           !path.isEmpty {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue { return url }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// png, jpg, heic, pdf or tiff, as set with `defaults write com.apple.screencapture type`.
    static var type: String {
        let saved = (CFPreferencesCopyAppValue("type" as CFString, "com.apple.screencapture" as CFString) as? String)?.lowercased()
        return ["png", "jpg", "jpeg", "heic", "pdf", "tiff", "gif"].contains(saved ?? "") ? saved! : "png"
    }

    /// "Ekran Resmi 2026-11-26 09.41.23.png", the way macOS names them.
    static func newFile() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = L("Ekran Resmi", "Screenshot") + " " + formatter.string(from: Date())
        var url = folder.appendingPathComponent(name).appendingPathExtension(type)
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) \(index)").appendingPathExtension(type)
            index += 1
        }
        return url
    }

    static func run(_ mode: CaptureMode, actions: PanelActions = Monitor.panelActions) {
        actions.close()
        LauncherPanel.shared.close()
        if mode == .toolbar {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
            return
        }
        if mode == .text {
            readScreen(actions: actions)
            return
        }
        let file = newFile()
        let arguments: [String] = switch mode {
        case .area: ["-i", "-c"]
        case .window: ["-i", "-W", "-c"]
        case .screen: ["-m", "-c"]
        case .areaFile: ["-i", "-t", type, file.path]
        case .screenFile: ["-m", "-t", type, file.path]
        case .timed: ["-m", "-T", "5", "-t", type, file.path]
        default: []
        }
        let before = NSPasteboard.general.changeCount
        Task {
            // Let the panel leave the screen before the selection starts.
            try? await Task.sleep(for: .milliseconds(250))
            _ = await Toolbox.run("/usr/sbin/screencapture", arguments)
            if arguments.contains("-c") {
                if NSPasteboard.general.changeCount != before { actions.flash(L("Kopyalandı", "Copied")) }
            } else if FileManager.default.fileExists(atPath: file.path) {
                actions.flash(L("Kaydedildi: \(folder.lastPathComponent)", "Saved to \(folder.lastPathComponent)"))
            }
        }
    }

    /// Select an area; a QR or barcode in it is copied, otherwise its text (Turkish and English, Apple's Vision).
    static func readScreen(actions: PanelActions = Monitor.panelActions) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nabiz-read-\(UUID().uuidString).png")
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            _ = await Toolbox.run("/usr/sbin/screencapture", ["-i", "-x", file.path])
            defer { try? FileManager.default.removeItem(at: file) }
            guard FileManager.default.fileExists(atPath: file.path) else { return }
            let path = file.path
            let found = await Task.detached(priority: .userInitiated) { Recognizer.read(path) }.value
            guard let found, !found.text.isEmpty else {
                actions.flash(L("Metin bulunamadı", "No text found"))
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(found.text, forType: .string)
            actions.flash(found.isCode ? L("QR kopyalandı", "QR copied") : L("Metin kopyalandı", "Text copied"))
        }
    }

    /// A QR code for the text, put on the clipboard as an image.
    @discardableResult
    static func copyQR(_ text: String) -> Bool {
        guard let image = qrImage(text) else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        Monitor.panelActions.flash(L("QR kopyalandı", "QR copied"))
        return true
    }

    static func qrImage(_ text: String, scale: CGFloat = 12) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

/// Text and barcodes in an image, on a background thread.
enum Recognizer {
    struct Found: Sendable {
        let text: String
        let isCode: Bool
    }

    nonisolated static func read(_ path: String) -> Found? {
        guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let handler = VNImageRequestHandler(cgImage: image)
        let codes = VNDetectBarcodesRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        text.recognitionLanguages = ["tr-TR", "en-US"]
        try? handler.perform([codes, text])
        if let payload = codes.results?.compactMap(\.payloadStringValue).first, !payload.isEmpty {
            return Found(text: payload, isCode: true)
        }
        let lines = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return Found(text: lines.joined(separator: "\n"), isCode: false)
    }
}
