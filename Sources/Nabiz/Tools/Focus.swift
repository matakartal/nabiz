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

    var isRunning: Bool { endsAt != nil }
    var isActive: Bool { endsAt != nil || pausedLeft != nil }

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
        endsAt = Date().addingTimeInterval(Double(minutes(phase)) * 60)
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
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != front {
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
    }

    func toggle(minutes: Int? = nil) {
        if isOn { stop() } else { start(minutes: minutes) }
    }

    /// Called every second by the app.
    func tick() {
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
