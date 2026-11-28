// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Observation

/// Work in focused blocks with short breaks: 25 minutes of work, 5 of rest, a longer rest after every fourth.
/// The countdown shows in the menu bar; each change is announced with a sound and a notification.
@MainActor
@Observable
final class Pomodoro {
    static let shared = Pomodoro()

    enum Phase: String, Codable {
        case work, shortBreak, longBreak

        var title: String {
            switch self {
            case .work: L("Odak", "Focus")
            case .shortBreak: L("Kısa mola", "Short break")
            case .longBreak: L("Uzun mola", "Long break")
            }
        }

        var symbol: String { self == .work ? "brain.head.profile" : "cup.and.saucer" }
    }

    private(set) var phase: Phase = .work
    private(set) var endsAt: Date?
    /// Set while paused: what was left.
    private(set) var pausedLeft: TimeInterval?
    /// Work blocks finished in a row, for the long break.
    private(set) var streak = 0

    /// A block ended with auto-start off: the next one is lined up but has not begun, so it is not "paused".
    private(set) var waitingToStart = false

    var isRunning: Bool { endsAt != nil }
    var isActive: Bool { endsAt != nil || pausedLeft != nil }

    /// What the play/pause button says: "Pause", "Resume", or "Start break" / "Start focus" for a lined-up block.
    var toggleTitle: String {
        if isRunning { return L("Duraklat", "Pause") }
        if waitingToStart { return phase == .work ? L("Odağı başlat", "Start focus") : L("Molayı başlat", "Start break") }
        return L("Devam", "Resume")
    }

    var left: TimeInterval? {
        if let pausedLeft { return pausedLeft }
        return endsAt.map { max($0.timeIntervalSinceNow, 0) }
    }

    /// "24:13", for the menu bar and the tile.
    var remainingText: String? {
        guard let left else { return nil }
        let seconds = Int(left.rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Work blocks finished today, and minutes focused.
    var today: (count: Int, minutes: Int) {
        let key = Self.dayKey(Date())
        let log = UserDefaults.standard.dictionary(forKey: "pomodoroLog") as? [String: [Int]] ?? [:]
        let entry = log[key] ?? [0, 0]
        return (entry.first ?? 0, entry.last ?? 0)
    }

    func minutes(_ phase: Phase) -> Int {
        let key = switch phase {
        case .work: Prefs.pomodoroWork
        case .shortBreak: Prefs.pomodoroShort
        case .longBreak: Prefs.pomodoroLong
        }
        return max(Prefs.int(key), 1)
    }

    func start(_ phase: Phase = .work) {
        self.phase = phase
        pausedLeft = nil
        waitingToStart = false
        endsAt = Date().addingTimeInterval(Double(minutes(phase)) * 60)
        Monitor.panelActions.flash("\(phase.title): \(minutes(phase)) " + L("dk", "min"))
        Notifier.shared.requestPermission(keepSetting: true)
        if Prefs.bool(Prefs.pomodoroFocus) {
            if phase == .work { FocusMode.shared.start(minutes: nil, byPomodoro: true) } else { FocusMode.shared.stop(onlyIfPomodoro: true) }
        }
    }

    func pause() {
        guard let endsAt else { return }
        pausedLeft = max(endsAt.timeIntervalSinceNow, 0)
        self.endsAt = nil
    }

    func resume() {
        // A lined-up block starts properly (with focus mode for a work block), not like a paused one.
        if waitingToStart { return start(phase) }
        guard let pausedLeft else { return }
        endsAt = Date().addingTimeInterval(pausedLeft)
        self.pausedLeft = nil
    }

    func toggle() {
        if isRunning { pause() } else if pausedLeft != nil { resume() } else { start(.work) }
    }

    /// Ends this block now and moves on, as if its time had run out (without counting a skipped work block).
    func skip() {
        guard isActive else { return }
        advance(completed: false)
    }

    func stop() {
        endsAt = nil
        pausedLeft = nil
        waitingToStart = false
        streak = 0
        phase = .work
        FocusMode.shared.stop(onlyIfPomodoro: true)
    }

    /// Called every second by the app.
    func tick() {
        guard let endsAt, endsAt <= Date() else { return }
        advance(completed: true)
    }

    private func advance(completed: Bool) {
        let finished = phase
        if finished == .work && completed {
            streak += 1
            record(minutes: minutes(.work))
        }
        let next: Phase = finished == .work
            ? (streak > 0 && streak % max(Prefs.int(Prefs.pomodoroLongEvery), 2) == 0 ? .longBreak : .shortBreak)
            : .work
        if completed {
            NSSound(named: finished == .work ? "Glass" : "Hero")?.play()
            let (title, body) = finished == .work
                ? (L("Odak bloğu bitti", "Focus block done"),
                   L("\(next.title): \(minutes(next)) dakika. Bugün \(today.count) blok.", "\(next.title): \(minutes(next)) minutes. \(today.count) today."))
                : (L("Mola bitti", "Break's over"), L("Sıradaki odak bloğu: \(minutes(.work)) dakika.", "Next focus block: \(minutes(.work)) minutes."))
            Notifier.shared.post(id: "pomodoro-\(Date().timeIntervalSince1970)", title: title, body: body)
        }
        if Prefs.bool(Prefs.pomodoroAuto) || !completed {
            start(next)
        } else {
            phase = next
            endsAt = nil
            pausedLeft = Double(minutes(next)) * 60
            waitingToStart = true
            if next != .work { FocusMode.shared.stop(onlyIfPomodoro: true) }
        }
    }

    private func record(minutes: Int) {
        var log = UserDefaults.standard.dictionary(forKey: "pomodoroLog") as? [String: [Int]] ?? [:]
        let key = Self.dayKey(Date())
        let entry = log[key] ?? [0, 0]
        log[key] = [entry[0] + 1, entry[1] + minutes]
        // Keep the last 60 days.
        if log.count > 60 { log.keys.sorted().prefix(log.count - 60).forEach { log.removeValue(forKey: $0) } }
        UserDefaults.standard.set(log, forKey: "pomodoroLog")
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Fewer distractions for a while: chat and social apps are hidden (and hidden again if they come forward),
/// other windows step aside, desktop icons go away, and macOS Focus turns on through Shortcuts if you set it up.
@MainActor
@Observable
final class FocusMode {
    static let shared = FocusMode()

    private(set) var isOn = false
    private(set) var until: Date?
    /// Started by a Pomodoro work block, so a break ends it.
    private(set) var byPomodoro = false
    /// Apps it kept in the background this session, for the summary.
    private(set) var blockedCount = 0
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var hidDesktop = false

    static let defaultBlocked = [
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "ru.keepcoder.Telegram", "org.telegram.desktop", "net.whatsapp.WhatsApp",
        "desktop.WhatsApp", "com.apple.MobileSMS", "com.facebook.archon", "com.microsoft.teams2", "com.apple.mail",
    ]

    var blocked: Set<String> {
        let saved = Prefs.string(Prefs.focusBlocked)
        return saved.isEmpty ? Set(Self.defaultBlocked) : Set(saved.split(separator: ",").map(String.init))
    }

    var remainingText: String? {
        guard let until, until > Date() else { return nil }
        let seconds = Int(until.timeIntervalSinceNow.rounded(.up))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    func start(minutes: Int?, byPomodoro: Bool = false) {
        if isOn {
            // A manual session outlasts Pomodoro breaks; just update the end.
            if !byPomodoro { self.byPomodoro = false; until = minutes.map { Date().addingTimeInterval(Double($0) * 60) } }
            return
        }
        isOn = true
        self.byPomodoro = byPomodoro
        blockedCount = 0
        until = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        let blocked = blocked
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Never Nabız itself (it is a regular app while it shows in the Dock): its notes and chats stay.
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != front && app.processIdentifier != me {
            if blocked.contains(app.bundleIdentifier ?? "") || Prefs.bool(Prefs.focusHideOthers) {
                app.hide()
                if blocked.contains(app.bundleIdentifier ?? "") { blockedCount += 1 }
            }
        }
        if Prefs.bool(Prefs.focusHideDesktop) && !Toolbox.shared.desktopHidden {
            Toolbox.shared.setDesktopIcons(visible: false)
            hidDesktop = true
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                     object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundle = app?.bundleIdentifier ?? ""
            let name = app?.localizedName ?? ""
            MainActor.assumeIsolated {
                guard FocusMode.shared.isOn, FocusMode.shared.blocked.contains(bundle) else { return }
                app?.hide()
                FocusMode.shared.blockedCount += 1
                Monitor.panelActions.flash(L("Odak: \(name) bekliyor", "Focus: \(name) can wait"))
            }
        }
        runShortcut(Prefs.string(Prefs.focusShortcutOn))
        if !byPomodoro {
            Monitor.panelActions.flash(blockedCount > 0 ? L("Odak açık · \(blockedCount) uygulama gizlendi", "Focus on · \(blockedCount) apps hidden")
                                                        : L("Odak modu açık", "Focus mode on"))
        }
    }

    func stop(onlyIfPomodoro: Bool = false) {
        guard isOn, !onlyIfPomodoro || byPomodoro else { return }
        isOn = false
        until = nil
        byPomodoro = false
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        if hidDesktop {
            Toolbox.shared.setDesktopIcons(visible: true)
            hidDesktop = false
        }
        runShortcut(Prefs.string(Prefs.focusShortcutOff))
        Monitor.panelActions.flash(L("Odak modu kapalı", "Focus mode off"))
    }

    func toggle(minutes: Int? = nil) {
        if isOn { stop() } else { start(minutes: minutes) }
    }

    /// Called every second by the app.
    func tick() {
        if isOn && Prefs.bool(Prefs.focusBlockSites) { SiteBlocker.shared.check() }
        guard isOn, let until, until <= Date() else { return }
        stop()
        NSSound(named: "Glass")?.play()
        Notifier.shared.post(id: "focus-\(Date().timeIntervalSince1970)", title: L("Odak süresi bitti", "Focus time is over"),
                             body: L("Gizlenen uygulamalar yeniden açılabilir.", "Hidden apps can come back."))
    }

    /// macOS has no public switch for its own Focus; a Shortcut the user made ("Set Focus") does it.
    private func runShortcut(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task.detached(priority: .utility) {
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/shortcuts"), arguments: ["run", name])
        }
    }
}

/// Keeps chosen websites away during focus, with no browser extension: it reads the address of the tab in front of
/// Safari or a Chromium browser (Chrome, Arc, Brave, Edge, Vivaldi) and swaps a blocked one for a short note.
/// macOS asks once per browser for permission to control it.
@MainActor
final class SiteBlocker {
    static let shared = SiteBlocker()

    static let defaultSites = ["youtube.com", "x.com", "twitter.com", "instagram.com", "facebook.com", "tiktok.com", "reddit.com"]

    /// Browser bundle id → how its scripting names the tab in front.
    private static let browsers: [String: String] = [
        "com.apple.Safari": "current tab", "com.apple.SafariTechnologyPreview": "current tab",
        "com.google.Chrome": "active tab", "com.google.Chrome.beta": "active tab", "company.thebrowser.Browser": "active tab",
        "com.brave.Browser": "active tab", "com.microsoft.edgemac": "active tab", "com.vivaldi.Vivaldi": "active tab",
        "org.chromium.Chromium": "active tab",
    ]

    private var busy = false
    private var lastCheck = Date.distantPast
    private var warnedDenied: Set<String> = []

    var sites: [String] {
        let saved = Prefs.string(Prefs.focusSites)
        return saved.isEmpty ? Self.defaultSites : saved.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty && $0 != "-" }
    }

    nonisolated static func isBlocked(host: String, in sites: [String]) -> Bool {
        let host = host.lowercased()
        return sites.contains { site in
            let site = site.hasPrefix("www.") ? String(site.dropFirst(4)) : site
            return host == site || host.hasSuffix("." + site)
        }
    }

    /// "https://www.youtube.com/watch…" → "www.youtube.com", also for a pasted domain without a scheme.
    nonisolated static func host(of address: String) -> String? {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host = URL(string: address)?.host(), !host.isEmpty { return host }
        return URL(string: "https://" + address)?.host()
    }

    /// Called every second while focus mode is on; looks at most every two seconds, only when a browser is in front.
    func check() {
        guard !busy, Date().timeIntervalSince(lastCheck) >= 2,
              let app = NSWorkspace.shared.frontmostApplication, let bundle = app.bundleIdentifier,
              let tab = Self.browsers[bundle] else { return }
        lastCheck = Date()
        busy = true
        let sites = sites, page = Self.page.absoluteString, name = app.localizedName ?? bundle
        Task {
            let (blockedHost, denied) = await Task.detached(priority: .utility) {
                Self.inspect(bundle: bundle, tab: tab, sites: sites, page: page)
            }.value
            busy = false
            if let blockedHost {
                Monitor.panelActions.flash(L("Odak: \(blockedHost) bekleyebilir", "Focus: \(blockedHost) can wait"))
            } else if denied && !warnedDenied.contains(bundle) {
                warnedDenied.insert(bundle)
                Monitor.panelActions.flash(L("Siteleri engellemek için \(name) iznini aç (Ayarlar → Gizlilik → Otomasyon)",
                                             "To block sites, allow \(name) in Settings → Privacy → Automation"))
            }
        }
    }

    /// Reads the front tab's address and, when it is blocked, swaps it for the focus page.
    nonisolated private static func inspect(bundle: String, tab: String, sites: [String], page: String) -> (String?, Bool) {
        var error: NSDictionary?
        let read = NSAppleScript(source: "tell application id \"\(bundle)\" to get URL of \(tab) of front window")?
            .executeAndReturnError(&error).stringValue
        let denied = (error?[NSAppleScript.errorNumber] as? Int) == -1743
        guard let read, let host = host(of: read), isBlocked(host: host, in: sites) else { return (nil, denied) }
        var setError: NSDictionary?
        let target = (page + "#" + host).replacingOccurrences(of: "\"", with: "")
        NSAppleScript(source: "tell application id \"\(bundle)\" to set URL of \(tab) of front window to \"\(target)\"")?
            .executeAndReturnError(&setError)
        return (host, false)
    }

    /// A small local page that says why the site went away.
    private static var page: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nabiz")
        let file = folder.appendingPathComponent("focus.html")
        let title = L("Odaktasın", "You're focusing")
        let body = L("Bu site odak bitince açılır.", "This site opens again when focus ends.")
        let html = """
        <!doctype html><html lang="\(L("tr", "en"))"><meta charset="utf-8"><title>\(title)</title>
        <meta name="color-scheme" content="light dark">
        <body style="font:15px -apple-system,system-ui;display:grid;place-items:center;height:90vh;margin:0;color:#888">
        <div style="text-align:center"><div style="font-size:40px">🌙</div><h1 style="font-weight:600;color:CanvasText;margin:.4em 0">\(title)</h1>
        <p id="site"></p><p>\(body)</p></div>
        <script>document.getElementById('site').textContent = decodeURIComponent(location.hash.slice(1))</script>
        """
        if (try? String(contentsOf: file, encoding: .utf8)) != html {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? html.write(to: file, atomically: true, encoding: .utf8)
        }
        return file
    }
}
