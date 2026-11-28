// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Observation

// MARK: - Snippets

/// Saved text typed from the launcher (or anywhere, with expansion on) by keyword.
/// Placeholders: {date} {time} {clipboard}, and {cursor} for where the cursor ends up.
struct Snippet: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var keyword: String
    var name: String
    var text: String

    /// The text with its placeholders filled in.
    @MainActor
    var expanded: String { expandedWithCursor.text }

    /// The filled-in text, and how many characters follow {cursor} so the cursor can be moved back there.
    @MainActor
    var expandedWithCursor: (text: String, cursorBack: Int) {
        let parts = text.components(separatedBy: "{cursor}")
        let before = Self.fill(parts[0])
        let after = Self.fill(parts.dropFirst().joined())
        return (before + after, parts.count > 1 ? after.count : 0)
    }

    @MainActor
    static func fill(_ text: String, now: Date = Date()) -> String {
        guard text.contains("{") else { return text }
        return text
            .replacingOccurrences(of: "{date}", with: now.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(Format.locale)))
            .replacingOccurrences(of: "{time}", with: now.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Format.locale)))
            .replacingOccurrences(of: "{clipboard}", with: NSPasteboard.general.string(forType: .string) ?? "")
    }
}

/// "gh nabiz" → GitHub search; {query} is replaced with what follows the keyword.
struct Quicklink: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var keyword: String
    var name: String
    var url: String

    /// The address has a place for a search ("{query}"); without one the link just opens.
    var takesQuery: Bool { url.contains("{query}") }

    func url(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: url.replacingOccurrences(of: "{query}", with: encoded))
    }
}

@MainActor
@Observable
final class LauncherStore {
    static let shared = LauncherStore()

    private(set) var snippets: [Snippet] = []
    private(set) var quicklinks: [Quicklink] = []

    static let defaultQuicklinks = [
        Quicklink(keyword: "g", name: "Google", url: "https://www.google.com/search?q={query}"),
        Quicklink(keyword: "gh", name: "GitHub", url: "https://github.com/search?q={query}"),
        Quicklink(keyword: "yt", name: "YouTube", url: "https://www.youtube.com/results?search_query={query}"),
        Quicklink(keyword: "w", name: "Wikipedia", url: "https://wikipedia.org/w/index.php?search={query}"),
        Quicklink(keyword: "hl", name: "Hyperliquid", url: "https://app.hyperliquid.xyz/trade/{query}"),
        Quicklink(keyword: "cl", name: "Claude", url: "https://claude.ai/new?q={query}"),
        Quicklink(keyword: "gpt", name: "ChatGPT", url: "https://chatgpt.com/?q={query}"),
        Quicklink(keyword: "çevir", name: L("Çeviri", "Translate"), url: "https://translate.google.com/?sl=auto&tl=tr&text={query}"),
        Quicklink(keyword: "harita", name: L("Haritalar", "Maps"), url: "maps://?q={query}"),
    ]

    /// Searches the web when nothing else matches: the quicklink picked in Settings, else the first that can search.
    var webSearch: Quicklink? {
        let keyword = Prefs.string(Prefs.launcherSearch)
        return quicklinks.first { $0.keyword == keyword && $0.takesQuery } ?? quicklinks.first(where: \.takesQuery)
    }

    init() {
        let defaults = UserDefaults.standard
        snippets = defaults.data(forKey: "snippets").flatMap { try? JSONDecoder().decode([Snippet].self, from: $0) } ?? [
            Snippet(keyword: "tarih", name: L("Bugünün tarihi", "Today's date"), text: "{date}"),
        ]
        quicklinks = defaults.data(forKey: "quicklinks").flatMap { try? JSONDecoder().decode([Quicklink].self, from: $0) } ?? Self.defaultQuicklinks
    }

    func save(snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) { snippets[index] = snippet } else { snippets.append(snippet) }
        persist()
    }

    func remove(snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        persist()
    }

    func save(quicklink: Quicklink) {
        if let index = quicklinks.firstIndex(where: { $0.id == quicklink.id }) { quicklinks[index] = quicklink } else { quicklinks.append(quicklink) }
        persist()
    }

    func remove(quicklink: Quicklink) {
        quicklinks.removeAll { $0.id == quicklink.id }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(snippets), forKey: "snippets")
        UserDefaults.standard.set(try? JSONEncoder().encode(quicklinks), forKey: "quicklinks")
    }
}

// MARK: - System commands

enum SystemCommand: String, CaseIterable, Identifiable {
    case lock, sleep, displayOff, hideOthers, quitAll, emptyTrash, restart, shutDown, logOut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lock: L("Ekranı kilitle", "Lock screen")
        case .sleep: L("Mac'i uyut", "Sleep")
        case .displayOff: L("Ekranı kapat", "Turn display off")
        case .hideOthers: L("Diğer uygulamaları gizle", "Hide other apps")
        case .quitAll: L("Tüm uygulamalardan çık", "Quit all apps")
        case .emptyTrash: L("Çöp Sepeti'ni boşalt", "Empty Trash")
        case .restart: L("Yeniden başlat", "Restart")
        case .shutDown: L("Kapat", "Shut down")
        case .logOut: L("Oturumu kapat", "Log out")
        }
    }

    var symbol: String {
        switch self {
        case .lock: "lock"
        case .sleep: "powersleep"
        case .displayOff: "moon.zzz"
        case .hideOthers: "eye.slash"
        case .quitAll: "xmark.square"
        case .emptyTrash: "trash"
        case .restart: "restart"
        case .shutDown: "power"
        case .logOut: "rectangle.portrait.and.arrow.right"
        }
    }

    /// Commands that end work or delete things ask first.
    var confirmation: String? {
        switch self {
        case .quitAll: L("Finder, Claude ve Nabız dışındaki tüm uygulamalar kapatılsın mı? Kaydedilmemiş belgeler için uygulamalar soracaktır.",
                         "Quit every app except Finder, Claude and Nabız? Apps will ask about unsaved documents.")
        case .emptyTrash: L("Çöp Sepeti'ndeki her şey kalıcı olarak silinecek. Bu geri alınamaz.", "Everything in the Trash is deleted for good. This can't be undone.")
        case .restart: L("Mac yeniden başlatılsın mı?", "Restart the Mac?")
        case .shutDown: L("Mac kapatılsın mı?", "Shut down the Mac?")
        case .logOut: L("Oturum kapatılsın mı?", "Log out?")
        default: nil
        }
    }

    @MainActor
    func run() {
        if let confirmation {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = confirmation
            alert.addButton(withTitle: title)
            alert.addButton(withTitle: L("Vazgeç", "Cancel"))
            alert.buttons.first?.hasDestructiveAction = true
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        switch self {
        case .lock: Self.lockScreen()
        case .sleep: Task { _ = await Toolbox.run("/usr/bin/pmset", ["sleepnow"]) }
        case .displayOff: Task { _ = await Toolbox.run("/usr/bin/pmset", ["displaysleepnow"]) }
        case .hideOthers:
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != front
                && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                app.hide()
            }
        case .quitAll:
            let keep: Set<String> = ["com.apple.finder", "com.anthropic.claudefordesktop", Bundle.main.bundleIdentifier ?? ""]
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !keep.contains(app.bundleIdentifier ?? "") {
                app.terminate()
            }
        case .emptyTrash: Self.appleScript("tell application \"Finder\" to empty trash")
        case .restart: Self.appleScript("tell application \"System Events\" to restart")
        case .shutDown: Self.appleScript("tell application \"System Events\" to shut down")
        case .logOut: Self.appleScript("tell application \"System Events\" to log out")
        }
    }

    private static func appleScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil { NSSound.beep() }
    }

    /// The same lock as Control Center's "Lock Screen" (login.framework), falling back to display sleep.
    private static func lockScreen() {
        typealias Lock = @convention(c) () -> Void
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            unsafeBitCast(symbol, to: Lock.self)()
        } else {
            Task { _ = await Toolbox.run("/usr/bin/pmset", ["displaysleepnow"]) }
        }
    }
}

// MARK: - Window management

/// Moves the front window: halves, thirds, maximize, center, next display. Needs Accessibility permission.
enum WindowAction: String, CaseIterable, Identifiable {
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize, almostMaximize, center, leftThird, centerThird, rightThird, nextDisplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftHalf: L("Sol yarı", "Left half")
        case .rightHalf: L("Sağ yarı", "Right half")
        case .topHalf: L("Üst yarı", "Top half")
        case .bottomHalf: L("Alt yarı", "Bottom half")
        case .maximize: L("Ekranı kapla", "Maximize")
        case .almostMaximize: L("Neredeyse kapla", "Almost maximize")
        case .center: L("Ortala", "Center")
        case .leftThird: L("Sol üçte bir", "Left third")
        case .centerThird: L("Orta üçte bir", "Center third")
        case .rightThird: L("Sağ üçte bir", "Right third")
        case .nextDisplay: L("Sonraki ekrana taşı", "Move to next display")
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .maximize: "rectangle.fill"
        case .almostMaximize: "rectangle.inset.filled"
        case .center: "rectangle.center.inset.filled"
        case .leftThird: "rectangle.leftthird.inset.filled"
        case .centerThird: "rectangle.center.inset.filled"
        case .rightThird: "rectangle.rightthird.inset.filled"
        case .nextDisplay: "rectangle.on.rectangle"
        }
    }

    /// ⌃⌥ + key, when window shortcuts are on.
    var shortcut: String? {
        switch self {
        case .leftHalf: "⌃⌥←"
        case .rightHalf: "⌃⌥→"
        case .topHalf: "⌃⌥↑"
        case .bottomHalf: "⌃⌥↓"
        case .maximize: "⌃⌥↩"
        case .center: "⌃⌥C"
        default: nil
        }
    }

    @MainActor
    func run() {
        guard Paster.isTrusted else {
            Paster.requestTrust()
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value, CFGetTypeID(window) == AXUIElementGetTypeID() else { NSSound.beep(); return }
        let axWindow = window as! AXUIElement
        guard let frame = Self.frame(of: axWindow) else { return }

        // AX uses a top-left origin on the main screen; AppKit a bottom-left one.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitFrame = CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
        let screens = NSScreen.screens
        let current = screens.max { $0.frame.intersection(appKitFrame).area < $1.frame.intersection(appKitFrame).area } ?? NSScreen.main
        guard var screen = current else { return }
        if self == .nextDisplay, let index = screens.firstIndex(of: screen), screens.count > 1 {
            screen = screens[(index + 1) % screens.count]
        }
        let target = target(for: frame.size, in: screen.visibleFrame)
        var origin = CGPoint(x: target.minX, y: mainHeight - target.maxY)
        var size = target.size
        if let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) {
            // Size, then position, then size again: some apps clamp size to the screen the window is still on.
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, dimensions)
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, position)
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, dimensions)
        }
    }

    /// Where the window goes on a screen whose usable area (AppKit coordinates) is `v`.
    func target(for size: CGSize, in v: CGRect) -> CGRect {
        switch self {
        case .leftHalf: CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height)
        case .rightHalf: CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height)
        case .topHalf: CGRect(x: v.minX, y: v.midY, width: v.width, height: v.height / 2)
        case .bottomHalf: CGRect(x: v.minX, y: v.minY, width: v.width, height: v.height / 2)
        case .maximize: v
        case .almostMaximize: v.insetBy(dx: v.width * 0.05, dy: v.height * 0.05)
        case .center: CGRect(x: v.midX - size.width / 2, y: v.midY - size.height / 2, width: size.width, height: size.height)
        case .leftThird: CGRect(x: v.minX, y: v.minY, width: v.width / 3, height: v.height)
        case .centerThird: CGRect(x: v.minX + v.width / 3, y: v.minY, width: v.width / 3, height: v.height)
        case .rightThird: CGRect(x: v.minX + v.width * 2 / 3, y: v.minY, width: v.width / 3, height: v.height)
        case .nextDisplay:
            CGRect(x: v.midX - min(size.width, v.width) / 2, y: v.midY - min(size.height, v.height) / 2,
                   width: min(size.width, v.width), height: min(size.height, v.height))
        }
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

// MARK: - Sleep timer and microphone

/// Puts the Mac to sleep after a while ("sleep in 30 minutes"), for a film or music at night.
@MainActor
@Observable
final class SleepTimer {
    static let shared = SleepTimer()
    private(set) var at: Date?
    @ObservationIgnored private var task: Task<Void, Never>?

    func start(minutes: Int) {
        cancel()
        at = Date().addingTimeInterval(Double(minutes) * 60)
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            guard !Task.isCancelled else { return }
            self?.at = nil
            _ = await Toolbox.run("/usr/bin/pmset", ["sleepnow"])
        }
        Monitor.panelActions.flash(L("\(minutes) dk sonra uyuyacak", "Sleeping in \(minutes) min"))
    }

    func cancel() {
        task?.cancel()
        task = nil
        at = nil
    }
}

/// Mutes and unmutes the microphone (input volume 0 and back), for calls.
@MainActor
enum Microphone {
    static var isMuted: Bool { (volume() ?? 1) == 0 }

    static func toggle() {
        if isMuted {
            let saved = UserDefaults.standard.integer(forKey: "micVolume")
            set(saved > 0 ? saved : 75)
            Monitor.panelActions.flash(L("Mikrofon açık", "Mic on"))
        } else {
            if let current = volume(), current > 0 { UserDefaults.standard.set(current, forKey: "micVolume") }
            set(0)
            Monitor.panelActions.flash(L("Mikrofon kapalı", "Mic muted"))
        }
    }

    private static func volume() -> Int? {
        var error: NSDictionary?
        let result = NSAppleScript(source: "input volume of (get volume settings)")?.executeAndReturnError(&error)
        return error == nil ? result.map { Int($0.int32Value) } : nil
    }

    private static func set(_ value: Int) {
        var error: NSDictionary?
        NSAppleScript(source: "set volume input volume \(value)")?.executeAndReturnError(&error)
    }
}
