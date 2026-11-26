import AppKit
import Observation
import Security

/// The one-tap tools in the panel's grid. Each does its job directly; nothing sends the user to another app to finish.
enum ToolKind: String, CaseIterable, Identifiable {
    case aiChat, calculator, clipboard, note, pomodoro, focus, keepAwake, timer, sleepTimer, color, screenshot, readText, download, mic
    case displayOff, darkMode, speedTest, ip, password, uuid, eject, xcode, rust, hiddenFiles, desktop, clearClipboard, activity

    var id: String { rawValue }

    /// Short enough for a 66 pt tile.
    /// Shown in the grid straight away; the rest sit behind "More tools".
    static let everyday: Set<ToolKind> = [.aiChat, .calculator, .clipboard, .note, .pomodoro, .focus, .keepAwake, .timer, .screenshot]

    var title: String {
        switch self {
        case .aiChat: L("AI sohbet", "AI chat")
        case .calculator: L("Başlatıcı", "Launcher")
        case .clipboard: L("Pano", "Clipboard")
        case .note: L("Notlar", "Notes")
        case .pomodoro: "Pomodoro"
        case .focus: L("Odak", "Focus")
        case .readText: L("Metin oku", "Read text")
        case .download: L("Video indir", "Download")
        case .mic: L("Mikrofon", "Mic")
        case .sleepTimer: L("Uyku", "Sleep timer")
        case .keepAwake: L("Uyanık kal", "Keep awake")
        case .timer: L("Zamanlayıcı", "Timer")
        case .color: L("Renk al", "Pick color")
        case .screenshot: L("Ekran al", "Screenshot")
        case .displayOff: L("Ekranı kapat", "Display off")
        case .darkMode: L("Karanlık", "Dark mode")
        case .speedTest: L("Hız", "Speed")
        case .ip: "IP"
        case .password: L("Şifre üret", "Password")
        case .uuid: "UUID"
        case .eject: L("Diski çıkar", "Eject")
        case .xcode: "Xcode"
        case .rust: "Rust"
        case .hiddenFiles: L("Gizli dosya", "Hidden files")
        case .desktop: L("Masaüstü", "Desktop")
        case .clearClipboard: L("Panoyu sil", "Clear clip")
        case .activity: L("Etkinlik", "Activity")
        }
    }

    var symbol: String {
        switch self {
        case .aiChat: "sparkles"
        case .calculator: "magnifyingglass"
        case .clipboard: "doc.on.clipboard"
        case .note: "note.text"
        case .pomodoro: "brain.head.profile"
        case .focus: "moon.circle"
        case .readText: "text.viewfinder"
        case .download: "arrow.down.circle"
        case .mic: "mic.slash"
        case .sleepTimer: "powersleep"
        case .keepAwake: "cup.and.saucer"
        case .timer: "timer"
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
        case .rust: "gearshape.2"
        case .hiddenFiles: "eye"
        case .desktop: "menubar.dock.rectangle"
        case .clearClipboard: "clipboard"
        case .activity: "waveform.path.ecg"
        }
    }

    /// The tooltip: what one tap does, in one sentence.
    var help: String {
        switch self {
        case .aiChat: L("Claude, Codex, Gemini ya da Apple'ın modeliyle sohbet (⌃⌥I). Hızlı soru için ⌃⌥A.",
                        "Chat with Claude, Codex, Gemini or Apple's model (⌃⌥I). ⌃⌥A for a quick question.")
        case .calculator: L("Uygulama aç, komut çalıştır, hesapla, çevir, web'de ara (⌃⌥Boşluk).",
                            "Open apps, run commands, calculate, convert, search the web (⌃⌥Space).")
        case .clipboard: L("Kopyaladıklarının geçmişi; seç, yapıştır, sabitle (⌃⌥V).", "Everything you copied; pick, paste, pin (⌃⌥V).")
        case .pomodoro: L("25 dk odak, 5 dk mola; dördüncüden sonra uzun mola. Süre menü çubuğunda.",
                          "25 minutes of focus, 5 of rest, a long break after every fourth. The countdown sits in the menu bar.")
        case .focus: L("Sohbet ve sosyal uygulamaları gizler, öne gelirlerse yine gizler.", "Hides chat and social apps, and again if they come forward.")
        case .readText: L("Ekrandan bir alan seç; içindeki metin ya da QR kodu panoya kopyalanır.",
                          "Select an area; its text or QR code is copied.")
        case .download: L("Panodaki YouTube, X, Instagram, TikTok… bağlantısından video ya da ses indirir.",
                          "Saves the video or sound from a YouTube, X, Instagram, TikTok… link you copied.")
        case .mic: L("Mikrofonu kapatır ya da açar.", "Mutes or unmutes the microphone.")
        case .sleepTimer: L("Mac'i 15–90 dakika sonra uyutur; film ya da müzikle uyurken.", "Puts the Mac to sleep in 15–90 minutes, for falling asleep to a film or music.")
        case .note: L("Her uygulamanın üstünde duran notlar; listeler ve yapılacaklar (⌃⌥M).", "Notes that float over every app, with lists and checklists (⌃⌥M).")
        case .keepAwake: L("Mac'in ve ekranın uyumasını bir süre engeller.", "Stops the Mac and display from sleeping for a while.")
        case .timer: L("Geri sayım; bitince ses ve bildirim. Kalan süre menü çubuğunda görünür.",
                       "A countdown with a sound and a notification at the end. The time left shows in the menu bar.")
        case .color: L("Ekrandan bir renk seç; hex kodu panoya kopyalanır.", "Pick a colour on screen; its hex code is copied.")
        case .screenshot: L("Alan, pencere ya da tüm ekran; sonra ok, kutu, yazı, numara, bulanıklaştırma ve çerçeveyle düzenle (⌃⌥S).",
                            "Area, window or whole screen; then mark it up with arrows, boxes, text, steps, blur and a frame (⌃⌥S).")
        case .displayOff: L("Ekranı hemen uyutur; Mac çalışmaya devam eder.", "Puts the display to sleep now; the Mac keeps running.")
        case .darkMode: L("Karanlık ve açık görünüm arasında geçer.", "Switches between dark and light appearance.")
        case .speedTest: L("İnternet hızını ölçer (yaklaşık 15 saniye).", "Measures your internet speed (about 15 seconds).")
        case .ip: L("Yerel IP adresini kopyalar.", "Copies your local IP address.")
        case .password: L("Güçlü bir şifre üretip panoya kopyalar.", "Makes a strong password and copies it.")
        case .uuid: L("Yeni bir UUID üretip panoya kopyalar.", "Makes a new UUID and copies it.")
        case .eject: L("Takılı harici diskleri güvenle çıkarır.", "Safely ejects connected external disks.")
        case .xcode: L("Xcode'un DerivedData önbelleğini temizler; Xcode gerekince yeniden oluşturur.",
                       "Deletes Xcode's DerivedData cache; Xcode rebuilds it when needed.")
        case .rust: L("Rust projelerinin target/ derleme önbelleklerini temizler; cargo gerekince yeniden oluşturur.",
                      "Deletes Rust projects' target/ build caches; cargo rebuilds them when needed.")
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
    /// Rust build caches found in the usual project folders, biggest first.
    private(set) var rustCaches: [RustCache] = []
    private(set) var rustScanning = false
    @ObservationIgnored private var rustScannedAt: Date?

    var rustSize: UInt64 { rustCaches.reduce(0) { $0 + $1.size } }
    private(set) var cleaning = false
    private(set) var ejectable: [URL] = []
    private(set) var hiddenFilesShown = false
    private(set) var desktopHidden = false
    private(set) var darkMode = false
    private(set) var micMuted = false
    @ObservationIgnored private var scannedAt: Date?

    private static var derivedData: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData")
    }

    /// Cheap reads every time the panel opens; the DerivedData size at most every 10 minutes.
    func refresh() {
        hiddenFilesShown = Self.finderFlag("AppleShowAllFiles", default: false)
        desktopHidden = !Self.finderFlag("CreateDesktop", default: true)
        darkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        micMuted = Microphone.isMuted
        ejectable = Self.externalVolumes()
        if let scannedAt, Date().timeIntervalSince(scannedAt) < 600 { return }
        scannedAt = Date()
        let path = Self.derivedData.path
        Task {
            derivedDataSize = await Task.detached(priority: .utility) { Self.folderSize(path) }.value
        }
        scanRust()
    }

    /// Finds Rust caches at most every 30 minutes (it walks the project folders and sizes each cache),
    /// then applies the automatic clean-up when it is on.
    func scanRust(force: Bool = false) {
        guard !rustScanning else { return }
        if !force, let rustScannedAt, Date().timeIntervalSince(rustScannedAt) < 1800 { return }
        rustScannedAt = Date()
        rustScanning = true
        Task {
            rustCaches = await Task.detached(priority: .utility) { DevCaches.findRust() }.value
            rustScanning = false
            autoCleanRust()
        }
    }

    /// With the setting on: deletes caches not built for `rustAutoCleanDays` days. Never one built in the last 10 minutes.
    private func autoCleanRust() {
        guard Prefs.bool(Prefs.rustAutoClean) else { return }
        let days = max(Prefs.int(Prefs.rustAutoCleanDays), 1)
        let stale = rustCaches.filter { !$0.isActive && Date().timeIntervalSince($0.lastBuilt) > Double(days) * 86_400 }
        guard !stale.isEmpty else { return }
        deleteRust(stale) { freed, count in
            Notifier.shared.post(id: "rust-auto-\(Date().timeIntervalSince1970)",
                                 title: L("Rust önbelleği temizlendi", "Rust caches cleaned"),
                                 body: L("\(count) proje, \(Format.bytes(freed)) boşaldı (\(days) gündür derlenmemişti).",
                                         "\(count) projects, \(Format.bytes(freed)) freed (not built for \(days) days)."))
        }
    }

    private func deleteRust(_ caches: [RustCache], done: @escaping @MainActor (UInt64, Int) -> Void) {
        cleaningRust = true
        Task {
            let deleted = await Task.detached(priority: .userInitiated) { caches.filter { !$0.isActive && DevCaches.delete($0) } }.value
            cleaningRust = false
            rustCaches.removeAll { cache in deleted.contains { $0.path == cache.path } }
            done(deleted.reduce(0) { $0 + $1.size }, deleted.count)
        }
    }

    private(set) var cleaningRust = false

    /// Asks first, listing each project and its size, then deletes every cache not being built right now.
    func cleanRust(actions: PanelActions) {
        let caches = rustCaches.filter { !$0.isActive }
        guard !caches.isEmpty else { return }
        actions.close()
        let total = caches.reduce(0) { $0 + $1.size }
        let alert = NSAlert()
        alert.messageText = L("Rust önbellekleri silinsin mi?", "Delete the Rust build caches?")
        let list = caches.prefix(8).map { "• \($0.project): \(Format.bytes($0.size))" }.joined(separator: "\n")
        alert.informativeText = L("\(list)\n\nToplam \(Format.bytes(total)) boşalır. Bu projeler bir sonraki cargo build'de baştan derlenir; kod ve ayarlara dokunulmaz.",
                                  "\(list)\n\n\(Format.bytes(total)) is freed. These projects build from scratch next time; code and settings are untouched.")
        alert.addButton(withTitle: L("Sil", "Delete"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        deleteRust(caches) { freed, _ in actions.flash(L("\(Format.bytes(freed)) boşaldı", "\(Format.bytes(freed)) freed")) }
    }

    func detail(_ kind: ToolKind) -> String? {
        switch kind {
        case .keepAwake:
            let awake = KeepAwake.shared
            guard awake.isOn else { return nil }
            return awake.until.map { Format.countdown(until: $0) } ?? "∞"
        case .timer: return CountdownTimer.shared.remainingText
        case .pomodoro:
            let pomodoro = Pomodoro.shared
            if let left = pomodoro.remainingText { return (pomodoro.isRunning ? "" : "⏸ ") + left }
            return pomodoro.today.count > 0 ? "\(pomodoro.today.count)" : nil
        case .sleepTimer:
            return SleepTimer.shared.at.map { $0.formatted(date: .omitted, time: .shortened) }
        case .focus:
            return FocusMode.shared.isOn ? (FocusMode.shared.remainingText ?? L("açık", "on")) : nil
        case .download:
            let downloader = Downloader.shared
            if downloader.installing { return L("kuruluyor", "installing") }
            return downloader.running.map { job in job.progress.map { Format.percent($0) } ?? "…" }
        case .note:
            let count = NoteStore.shared.notes.filter { !$0.isEmpty }.count
            return count > 0 ? "\(count)" : nil
        case .clipboard:
            let count = ClipboardHistory.shared.items.count
            return Prefs.bool(Prefs.clipboardEnabled) && count > 0 ? "\(count)" : nil
        case .speedTest: return speedRunning ? L("ölçülüyor", "testing") : speedResult
        case .ip: return LocalIP.address() ?? L("yok", "offline")
        case .eject: return ejectable.isEmpty ? L("disk yok", "none") : L("\(ejectable.count) disk", "\(ejectable.count) disk")
        case .xcode: return cleaning ? L("siliniyor", "cleaning") : derivedDataSize.map(Format.bytes)
        case .rust: return cleaningRust ? L("siliniyor", "cleaning") : rustScanning && rustCaches.isEmpty ? L("aranıyor", "scanning")
            : rustCaches.isEmpty ? L("yok", "none") : Format.bytes(rustSize)
        default: return nil
        }
    }

    func isActive(_ kind: ToolKind) -> Bool {
        switch kind {
        case .keepAwake: KeepAwake.shared.isOn
        case .timer: CountdownTimer.shared.isRunning
        case .darkMode: darkMode
        case .hiddenFiles: hiddenFilesShown
        case .desktop: desktopHidden
        case .note: NoteWindow.isVisible
        case .pomodoro: Pomodoro.shared.isActive
        case .focus: FocusMode.shared.isOn
        case .mic: micMuted
        case .sleepTimer: SleepTimer.shared.at != nil
        case .download: Downloader.shared.running != nil
        default: false
        }
    }

    func isEnabled(_ kind: ToolKind) -> Bool {
        switch kind {
        case .eject: !ejectable.isEmpty
        case .xcode: !cleaning && (derivedDataSize ?? 0) > 0
        case .rust: !cleaningRust && rustCaches.contains { !$0.isActive }
        case .speedTest: !speedRunning
        case .ip: LocalIP.address() != nil
        default: true
        }
    }

    func isBusy(_ kind: ToolKind) -> Bool {
        (kind == .speedTest && speedRunning) || (kind == .xcode && cleaning) || (kind == .rust && cleaningRust)
    }

    // MARK: - Actions

    func run(_ kind: ToolKind, actions: PanelActions, monitor: Monitor) {
        switch kind {
        case .aiChat:
            actions.close()
            AIChatWindow.show()
        case .calculator:
            actions.close()
            LauncherPanel.shared.show()
        case .clipboard:
            actions.close()
            LauncherPanel.shared.show(.clipboard)
        case .note:
            actions.close()
            NoteWindow.toggle()
        case .keepAwake, .timer, .pomodoro, .focus, .screenshot, .sleepTimer:
            break // the grid opens their chips
        case .readText:
            Capture.run(.text, actions: actions)
        case .download:
            actions.close()
            let copied = NSPasteboard.general.string(forType: .string).flatMap(Downloader.videoURL)
            LauncherPanel.shared.show(text: copied?.absoluteString ?? "")
            if copied == nil { actions.flash(L("Önce bir video bağlantısı kopyala", "Copy a video link first")) }
        case .mic:
            Microphone.toggle()
            refreshMic()
        case .color:
            actions.close()
            NSColorSampler().show { color in
                guard let rgb = color?.usingColorSpace(.sRGB) else { return }
                let hex = String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
                MainActor.assumeIsolated { actions.copy(hex) }
            }
        case .displayOff:
            actions.close()
            Task { _ = await Self.run("/usr/bin/pmset", ["displaysleepnow"]) }
        case .darkMode:
            actions.flash(darkMode ? L("Açık görünüm", "Light mode") : L("Karanlık görünüm", "Dark mode"))
            toggleDarkMode()
        case .speedTest:
            actions.flash(L("Hız ölçülüyor (~15 sn)", "Measuring speed (~15 s)"))
            speedTest()
        case .ip:
            if let ip = LocalIP.address() {
                actions.copy(ip)
                actions.flash(L("IP kopyalandı: \(ip)", "IP copied: \(ip)"))
            }
        case .password:
            actions.copy(Self.password())
            actions.flash(L("Güçlü şifre kopyalandı", "Strong password copied"))
        case .uuid:
            actions.copy(UUID().uuidString)
            actions.flash(L("UUID kopyalandı", "UUID copied"))
        case .eject:
            eject(actions: actions)
        case .xcode:
            cleanDerivedData(actions: actions)
        case .rust:
            cleanRust(actions: actions)
        case .hiddenFiles:
            actions.flash(hiddenFilesShown ? L("Gizli dosyalar gizlendi", "Hidden files hidden") : L("Gizli dosyalar görünüyor", "Hidden files shown"))
            setFinderFlag("AppleShowAllFiles", !hiddenFilesShown)
        case .desktop:
            actions.flash(desktopHidden ? L("Masaüstü simgeleri geri geldi", "Desktop icons are back") : L("Masaüstü simgeleri gizlendi", "Desktop icons hidden"))
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

    /// For schedules: sets the appearance instead of flipping it.
    func setDarkMode(_ on: Bool) {
        let script = NSAppleScript(source: "tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        darkMode = on
    }

    /// For schedules: no dialog. Deletes Rust caches not built for a day (never one being built).
    func cleanRustUnattended() {
        Task {
            rustScannedAt = nil
            rustCaches = await Task.detached(priority: .utility) { DevCaches.findRust() }.value
            let stale = rustCaches.filter { !$0.isActive && Date().timeIntervalSince($0.lastBuilt) > 86_400 }
            guard !stale.isEmpty else { return }
            deleteRust(stale) { _, _ in }
        }
    }

    /// For schedules: no dialog. Xcode rebuilds DerivedData on the next build.
    func cleanDerivedDataUnattended() {
        let path = Self.derivedData.path
        Task {
            await Task.detached(priority: .utility) {
                let fm = FileManager.default
                for item in (try? fm.contentsOfDirectory(atPath: path)) ?? [] {
                    try? fm.removeItem(atPath: (path as NSString).appendingPathComponent(item))
                }
            }.value
            derivedDataSize = await Task.detached(priority: .utility) { Self.folderSize(path) }.value
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
                Monitor.panelActions.flash(L("Hız ölçülemedi", "Speed test failed"))
                return
            }
            speedResult = "↓\(Int((down / 1_000_000).rounded())) ↑\(Int((up / 1_000_000).rounded())) Mbps"
            Monitor.panelActions.flash(L("İnternet: ", "Internet: ") + (speedResult ?? ""))
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
    func refreshMic() { micMuted = Microphone.isMuted }

    /// For focus mode: hides the desktop icons, and brings them back after.
    func setDesktopIcons(visible: Bool) {
        desktopHidden = !visible
        setFinderFlag("CreateDesktop", visible)
    }

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
