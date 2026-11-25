import AppKit
import Observation
import Security

/// The one-tap tools in the panel's grid. Each does its job directly; nothing sends the user to another app to finish.
enum ToolKind: String, CaseIterable, Identifiable {
    case calculator, keepAwake, color, screenshot, displayOff, darkMode, speedTest, ip
    case password, uuid, eject, xcode, hiddenFiles, desktop, clearClipboard, activity

    var id: String { rawValue }

    /// Short enough for a 66 pt tile.
    var title: String {
        switch self {
        case .calculator: L("Hesap", "Calculator")
        case .keepAwake: L("Uyanık kal", "Keep awake")
        case .color: L("Renk al", "Pick color")
        case .screenshot: L("Ekran al", "Screenshot")
        case .displayOff: L("Ekranı kapat", "Display off")
        case .darkMode: L("Karanlık", "Dark mode")
        case .speedTest: L("Hız testi", "Speed test")
        case .ip: "IP"
        case .password: L("Şifre üret", "Password")
        case .uuid: "UUID"
        case .eject: L("Diski çıkar", "Eject")
        case .xcode: L("Xcode temizle", "Clean Xcode")
        case .hiddenFiles: L("Gizli dosya", "Hidden files")
        case .desktop: L("Masaüstü", "Desktop")
        case .clearClipboard: L("Panoyu sil", "Clear clip")
        case .activity: L("Etkinlik", "Activity")
        }
    }

    var symbol: String {
        switch self {
        case .calculator: "plus.forwardslash.minus"
        case .keepAwake: "cup.and.saucer"
        case .color: "eyedropper"
        case .screenshot: "camera.viewfinder"
        case .displayOff: "moon.zzz"
        case .darkMode: "circle.lefthalf.filled"
        case .speedTest: "speedometer"
        case .ip: "network"
        case .password: "key"
        case .uuid: "number"
        case .eject: "eject"
        case .xcode: "hammer"
        case .hiddenFiles: "eye"
        case .desktop: "menubar.dock.rectangle"
        case .clearClipboard: "clipboard"
        case .activity: "waveform.path.ecg"
        }
    }

    /// The tooltip: what one tap does, in one sentence.
    var help: String {
        switch self {
        case .calculator: L("Hesap makinesi, döviz ve birim çevirici (⌃⌥Boşluk).", "Calculator, currency and unit converter (⌃⌥Space).")
        case .keepAwake: L("Mac'in ve ekranın uyumasını bir süre engeller.", "Stops the Mac and display from sleeping for a while.")
        case .color: L("Ekrandan bir renk seç; hex kodu panoya kopyalanır.", "Pick a colour on screen; its hex code is copied.")
        case .screenshot: L("Bir alan seç; görüntüsü panoya kopyalanır.", "Select an area; its picture is copied.")
        case .displayOff: L("Ekranı hemen uyutur; Mac çalışmaya devam eder.", "Puts the display to sleep now; the Mac keeps running.")
        case .darkMode: L("Karanlık ve açık görünüm arasında geçer.", "Switches between dark and light appearance.")
        case .speedTest: L("İnternet hızını ölçer (yaklaşık 15 saniye).", "Measures your internet speed (about 15 seconds).")
        case .ip: L("Yerel IP adresini kopyalar.", "Copies your local IP address.")
        case .password: L("Güçlü bir şifre üretip panoya kopyalar.", "Makes a strong password and copies it.")
        case .uuid: L("Yeni bir UUID üretip panoya kopyalar.", "Makes a new UUID and copies it.")
        case .eject: L("Takılı harici diskleri güvenle çıkarır.", "Safely ejects connected external disks.")
        case .xcode: L("Xcode'un DerivedData önbelleğini siler; Xcode gerekince yeniden oluşturur.",
                       "Deletes Xcode's DerivedData cache; Xcode rebuilds it when needed.")
        case .hiddenFiles: L("Finder'da gizli dosyaları gösterir ya da gizler.", "Shows or hides hidden files in Finder.")
        case .desktop: L("Masaüstü simgelerini gizler (sunum ve ekran paylaşımı için).", "Hides desktop icons (for presenting and screen sharing).")
        case .clearClipboard: L("Panodaki her şeyi siler.", "Empties the clipboard.")
        case .activity: L("Etkinlik İzleyicisi'ni açar.", "Opens Activity Monitor.")
        }
    }
}

/// State and actions behind the tool grid.
@MainActor
@Observable
final class Toolbox {
    static let shared = Toolbox()

    private(set) var speedResult: String?
    private(set) var speedRunning = false
    private(set) var derivedDataSize: UInt64?
    private(set) var cleaning = false
    private(set) var ejectable: [URL] = []
    private(set) var hiddenFilesShown = false
    private(set) var desktopHidden = false
    private(set) var darkMode = false
    @ObservationIgnored private var scannedAt: Date?

    private static var derivedData: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData")
    }

    /// Cheap reads every time the panel opens; the DerivedData size at most every 10 minutes.
    func refresh() {
        hiddenFilesShown = Self.finderFlag("AppleShowAllFiles", default: false)
        desktopHidden = !Self.finderFlag("CreateDesktop", default: true)
        darkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        ejectable = Self.externalVolumes()
        if let scannedAt, Date().timeIntervalSince(scannedAt) < 600 { return }
        scannedAt = Date()
        let path = Self.derivedData.path
        Task {
            derivedDataSize = await Task.detached(priority: .utility) { Self.folderSize(path) }.value
        }
    }

    func detail(_ kind: ToolKind) -> String? {
        switch kind {
        case .keepAwake:
            let awake = KeepAwake.shared
            guard awake.isOn else { return nil }
            return awake.until.map { Format.countdown(until: $0) } ?? "∞"
        case .speedTest: return speedRunning ? L("ölçülüyor", "testing") : speedResult
        case .ip: return LocalIP.address() ?? L("yok", "offline")
        case .eject: return ejectable.isEmpty ? L("disk yok", "none") : L("\(ejectable.count) disk", "\(ejectable.count) disk")
        case .xcode: return cleaning ? L("siliniyor", "cleaning") : derivedDataSize.map(Format.bytes)
        default: return nil
        }
    }

    func isActive(_ kind: ToolKind) -> Bool {
        switch kind {
        case .keepAwake: KeepAwake.shared.isOn
        case .darkMode: darkMode
        case .hiddenFiles: hiddenFilesShown
        case .desktop: desktopHidden
        default: false
        }
    }

    func isEnabled(_ kind: ToolKind) -> Bool {
        switch kind {
        case .eject: !ejectable.isEmpty
        case .xcode: !cleaning && (derivedDataSize ?? 0) > 0
        case .speedTest: !speedRunning
        case .ip: LocalIP.address() != nil
        default: true
        }
    }

    func isBusy(_ kind: ToolKind) -> Bool {
        (kind == .speedTest && speedRunning) || (kind == .xcode && cleaning)
    }

    // MARK: - Actions

    func run(_ kind: ToolKind, actions: PanelActions, monitor: Monitor) {
        switch kind {
        case .calculator:
            actions.close()
            CalculatorPanel.shared.show()
        case .keepAwake:
            break // the grid opens its duration chips
        case .color:
            actions.close()
            NSColorSampler().show { color in
                guard let rgb = color?.usingColorSpace(.sRGB) else { return }
                let hex = String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
                MainActor.assumeIsolated { actions.copy(hex) }
            }
        case .screenshot:
            actions.close()
            let before = NSPasteboard.general.changeCount
            Task {
                // Give the panel a moment to leave the screen before the selection starts.
                try? await Task.sleep(for: .milliseconds(250))
                _ = await Self.run("/usr/sbin/screencapture", ["-i", "-c"])
                if NSPasteboard.general.changeCount != before { actions.flash(L("Kopyalandı", "Copied")) }
            }
        case .displayOff:
            actions.close()
            Task { _ = await Self.run("/usr/bin/pmset", ["displaysleepnow"]) }
        case .darkMode:
            toggleDarkMode()
        case .speedTest:
            speedTest()
        case .ip:
            if let ip = LocalIP.address() { actions.copy(ip) }
        case .password:
            actions.copy(Self.password())
        case .uuid:
            actions.copy(UUID().uuidString)
        case .eject:
            eject(actions: actions)
        case .xcode:
            cleanDerivedData(actions: actions)
        case .hiddenFiles:
            setFinderFlag("AppleShowAllFiles", !hiddenFilesShown)
        case .desktop:
            setFinderFlag("CreateDesktop", desktopHidden)
        case .clearClipboard:
            NSPasteboard.general.clearContents()
            actions.flash(L("Pano silindi", "Clipboard cleared"))
        case .activity:
            actions.close()
            monitor.openActivityMonitor()
        }
    }

    private func toggleDarkMode() {
        let script = NSAppleScript(source: "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if error != nil { NSSound.beep() }
        darkMode.toggle()
        // The system appearance changes a moment later; read it back.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            darkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    private func speedTest() {
        speedRunning = true
        Task {
            let output = await Self.run("/usr/bin/networkQuality", ["-c"])
            speedRunning = false
            guard let data = output?.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let down = (json["dl_throughput"] as? NSNumber)?.doubleValue,
                  let up = (json["ul_throughput"] as? NSNumber)?.doubleValue
            else {
                speedResult = L("ölçülemedi", "failed")
                return
            }
            speedResult = "↓\(Int((down / 1_000_000).rounded())) ↑\(Int((up / 1_000_000).rounded())) Mbps"
        }
    }

    private func eject(actions: PanelActions) {
        let volumes = ejectable.map(\.path)
        Task {
            var failed = false
            for volume in volumes where await Self.run("/usr/sbin/diskutil", ["eject", volume]) == nil { failed = true }
            ejectable = Self.externalVolumes()
            actions.flash(failed ? L("Bir disk kullanımda", "A disk is in use") : L("Diskler çıkarıldı", "Disks ejected"))
        }
    }

    private func cleanDerivedData(actions: PanelActions) {
        guard let size = derivedDataSize else { return }
        actions.close()
        let alert = NSAlert()
        alert.messageText = L("Xcode önbelleği silinsin mi?", "Delete Xcode's cache?")
        alert.informativeText = L("DerivedData klasörü silinir ve \(Format.bytes(size)) boşalır. Projeler bir sonraki derlemede biraz daha yavaş derlenir; başka bir şey kaybolmaz.",
                                  "The DerivedData folder is deleted, freeing \(Format.bytes(size)). Projects build a little slower the next time; nothing else is lost.")
        alert.addButton(withTitle: L("Sil", "Delete"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        cleaning = true
        let path = Self.derivedData.path
        Task {
            await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                for item in (try? fm.contentsOfDirectory(atPath: path)) ?? [] {
                    try? fm.removeItem(atPath: (path as NSString).appendingPathComponent(item))
                }
            }.value
            cleaning = false
            derivedDataSize = await Task.detached(priority: .utility) { Self.folderSize(path) }.value
            actions.flash(L("\(Format.bytes(size)) boşaldı", "\(Format.bytes(size)) freed"))
        }
    }

    /// Finder reads these flags at launch, so it is restarted (its windows come back).
    private func setFinderFlag(_ key: String, _ value: Bool) {
        CFPreferencesSetAppValue(key as CFString, value as CFBoolean, "com.apple.finder" as CFString)
        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        Task {
            _ = await Self.run("/usr/bin/killall", ["Finder"])
            hiddenFilesShown = Self.finderFlag("AppleShowAllFiles", default: false)
            desktopHidden = !Self.finderFlag("CreateDesktop", default: true)
        }
    }

    // MARK: - Helpers

    private static func finderFlag(_ key: String, default value: Bool) -> Bool {
        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        guard let raw = CFPreferencesCopyAppValue(key as CFString, "com.apple.finder" as CFString) else { return value }
        if let flag = raw as? Bool { return flag }
        if let text = raw as? String { return ["1", "true", "yes"].contains(text.lowercased()) }
        return value
    }

    private static func externalVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsInternalKey, .volumeIsRootFileSystemKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return volumes.filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return values.volumeIsEjectable == true && values.volumeIsInternal != true && values.volumeIsRootFileSystem != true
        }
    }

    nonisolated private static func folderSize(_ path: String) -> UInt64? {
        let url = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                                                              options: [], errorHandler: { _, _ in true }) else { return nil }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            total += UInt64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// 20 characters from letters, digits and a few symbols, from the system's secure random source.
    private static func password() -> String {
        // 64 symbols, so every random byte maps evenly (256 is a multiple of 64).
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789-_!@#%+")
        var bytes = [UInt8](repeating: 0, count: 20)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    /// Runs a tool off the main thread; returns its output, or nil when it failed.
    nonisolated static func run(_ path: String, _ arguments: [String]) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
        }.value
    }
}
