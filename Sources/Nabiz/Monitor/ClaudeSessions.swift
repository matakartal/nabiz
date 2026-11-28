// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Darwin
import Foundation
import Observation
import UserNotifications

/// One running Claude Code session, from the small file Claude Code keeps for it in `<config dir>/sessions/<pid>.json`.
struct ClaudeSession: Identifiable, Equatable, Sendable {
    /// What the session is doing. Ordered by how much it needs the user: waiting first, idle last.
    enum Status: Int, Comparable, Sendable {
        case waiting, busy, idle
        static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
    }

    let pid: Int32
    var sessionID = ""
    /// The account folder the session belongs to ("~/.claude" for the default account).
    var configDir: String
    var cwd: String
    var name: String?
    var status: Status = .idle
    /// What a waiting session waits for ("permission prompt").
    var waitingFor: String?
    /// "claude-desktop", "cli", "sdk-cli"…
    var entrypoint = ""
    var startedAt: Date?
    /// The process's start time as Claude Code wrote it ("Sat Nov 28 17:08:00 2026").
    var procStart: String?
    var statusUpdatedAt: Date?
    var updatedAt: Date?
    /// The parent processes, nearest first, to find the app the session runs in.
    var ancestors: [Int32] = []

    var id: String { configDir + "#\(pid)" }

    /// When it last changed, for "most recent first".
    var lastActivity: Date { statusUpdatedAt ?? updatedAt ?? startedAt ?? .distantPast }

    var waitsForPermission: Bool { waitingFor.map { $0.localizedCaseInsensitiveContains("permission") } ?? true }
}

/// Reading Claude Code's session files, and the rules for showing them. The parsing and rules are pure so they
/// can be tested; `read` touches the disk and the process table and runs off the main thread.
enum ClaudeSessions {
    static let desktopBundleID = "com.anthropic.claudefordesktop"
    static var defaultDir: String { NSHomeDirectory() + "/.claude" }

    // MARK: Parsing

    /// One session file, or nil when it isn't one (broken, cut short, another format).
    static func parse(_ data: Data, configDir: String, filePID: Int32? = nil) -> ClaudeSession? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let pid = (object["pid"] as? NSNumber)?.int32Value ?? filePID ?? 0
        guard pid > 0, let cwd = object["cwd"] as? String, !cwd.isEmpty else { return nil }
        var session = ClaudeSession(pid: pid, configDir: configDir, cwd: cwd)
        session.sessionID = object["sessionId"] as? String ?? ""
        let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        session.name = name?.isEmpty == false ? name : nil
        switch object["status"] as? String {
        case "waiting": session.status = .waiting
        case "busy": session.status = .busy
        default: session.status = .idle
        }
        session.waitingFor = object["waitingFor"] as? String
        session.entrypoint = object["entrypoint"] as? String ?? ""
        session.startedAt = date(object["startedAt"])
        session.procStart = object["procStart"] as? String
        session.statusUpdatedAt = date(object["statusUpdatedAt"])
        session.updatedAt = date(object["updatedAt"])
        return session
    }

    /// Milliseconds since 1970.
    private static func date(_ value: Any?) -> Date? {
        guard let ms = (value as? NSNumber)?.doubleValue, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    /// "Sat Nov 28 17:08:00 2026", read both as UTC (what Claude Code writes) and as local time, in case a version
    /// writes it the way `ps` prints it.
    static func procStartDates(_ text: String) -> [Date] {
        let cleaned = text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return [TimeZone(identifier: "UTC"), TimeZone.current].compactMap { zone in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = zone
            formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
            return formatter.date(from: cleaned)
        }
    }

    /// Whether the live process with the session's pid is still the one that wrote the file, not a newer one that got
    /// the same pid after the session ended (its file stays behind). A reused pid always belongs to a process that
    /// started after the session did.
    static func isSameProcess(started: Date, startedAt: Date?, procStart: String?) -> Bool {
        let written = procStart.map(procStartDates) ?? []
        if written.contains(where: { abs($0.timeIntervalSince(started)) <= 2 }) { return true }
        if let startedAt { return started.timeIntervalSince(startedAt) <= 5 }
        return written.isEmpty
    }

    // MARK: Showing

    /// Waiting first, then working, then idle; the most recent first within each.
    static func sorted(_ sessions: [ClaudeSession]) -> [ClaudeSession] {
        sessions.sorted {
            if $0.status != $1.status { return $0.status < $1.status }
            if $0.lastActivity != $1.lastActivity { return $0.lastActivity > $1.lastActivity }
            return $0.id < $1.id
        }
    }

    /// The closed header: "2 waiting" (needs attention), else "3 working", else "5 idle".
    static func summary(_ sessions: [ClaudeSession]) -> (text: String, attention: Bool) {
        let waiting = sessions.count(where: { $0.status == .waiting })
        if waiting > 0 { return (L("\(waiting) bekliyor", "\(waiting) waiting"), true) }
        let busy = sessions.count(where: { $0.status == .busy })
        if busy > 0 { return (L("\(busy) çalışıyor", "\(busy) working"), false) }
        return (L("\(sessions.count) boşta", "\(sessions.count) idle"), false)
    }

    /// The project a session works in: "nabiz", or "nabiz · feature" for a worktree in `nabiz/.claude/worktrees/feature`.
    /// nil for Claude's own scratch folders, which aren't projects.
    static func project(_ cwd: String) -> String? {
        let path = (cwd as NSString).standardizingPath
        if path.contains("/scratch-workspaces/") { return nil }
        if path == NSHomeDirectory() { return "~" }
        let parts = path.split(separator: "/").map(String.init)
        if let index = parts.lastIndex(of: "worktrees"), index >= 2, parts[index - 1] == ".claude", index + 1 < parts.count {
            return "\(parts[index - 2]) · \(parts[index + 1])"
        }
        return parts.last
    }

    /// The row's title: the session's name, else its folder.
    static func title(_ session: ClaudeSession) -> String {
        session.name ?? project(session.cwd) ?? "Claude Code"
    }

    /// A short name for an account folder that has no nickname: "~/.claude-work" → "work", Synara's folders →
    /// "Synara", Xcode's agent → "Xcode".
    static func folderLabel(_ folder: String) -> String {
        let parts = folder.split(separator: "/").map(String.init)
        if let app = parts.first(where: { $0.hasPrefix(".synara") }) {
            let words = app.dropFirst().split(separator: "-").map(String.init)
            return ([words.first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Synara"] + words.dropFirst())
                .joined(separator: " ")
        }
        if folder.contains("/Xcode/CodingAssistant/") { return "Xcode" }
        let last = parts.last ?? folder
        var name = last.hasPrefix(".") ? String(last.dropFirst()) : last
        for prefix in ["claude-", "claude_"] where name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)) }
        return name.isEmpty ? last : name
    }

    /// The trailing text: "Needs you", "Working", or how long it has been idle.
    static func statusText(_ session: ClaudeSession, now: Date = Date()) -> String {
        switch session.status {
        case .waiting: session.waitsForPermission ? L("İzin bekliyor", "Needs permission") : L("Seni bekliyor", "Needs you")
        case .busy: L("Çalışıyor", "Working")
        case .idle: Format.ago(session.lastActivity, now: now)
        }
    }

    /// "Claude", "Terminal", "Agent SDK": where the session was started, in plain words.
    static func entrypointName(_ entrypoint: String) -> String {
        switch entrypoint {
        case "claude-desktop": "Claude"
        case "cli": "Terminal"
        case let other where other.hasPrefix("sdk"): "Agent SDK"
        case "": "Claude Code"
        default: entrypoint
        }
    }

    /// Sessions that just started waiting: seen before doing something else, waiting now. A session already waiting
    /// the first time it is seen doesn't count, so starting Nabız doesn't announce old waits.
    static func newlyWaiting(before: [String: ClaudeSession.Status], now: [ClaudeSession]) -> [ClaudeSession] {
        now.filter { session in
            guard session.status == .waiting, let old = before[session.id] else { return false }
            return old != .waiting
        }
    }

    /// The app a session runs in: the Claude app for its own sessions, else the nearest parent process that is a
    /// regular app (Terminal, iTerm, Ghostty, VS Code…). nil when there is none (tmux, a background job).
    static func host(entrypoint: String, ancestors: [Int32], apps: Set<Int32>, claudeApp: Int32?) -> Int32? {
        if entrypoint == "claude-desktop", let claudeApp { return claudeApp }
        return ancestors.first { apps.contains($0) }
    }

    // MARK: Reading

    /// The default folder and every other Claude account folder Nabız knows about that has sessions.
    static func configDirs(extra: [String]) -> [String] {
        ([defaultDir] + AIAccounts.candidates(.claude, extra: extra)).filter {
            FileManager.default.fileExists(atPath: $0 + "/sessions")
        }
    }

    /// Every live session in those folders. Files of processes that ended are skipped without being read, and a pid
    /// now used by another process doesn't count. Sessions Nabız started itself (its AI chat) are left out.
    static func read(_ dirs: [String]) -> [ClaudeSession] {
        let own = getpid()
        var result: [ClaudeSession] = []
        for dir in dirs {
            let folder = dir + "/sessions"
            for file in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] where file.hasSuffix(".json") {
                guard let filePID = Int32(file.dropLast(5)), filePID > 0, let info = liveInfo(filePID),
                      let data = FileManager.default.contents(atPath: folder + "/" + file),
                      var session = parse(data, configDir: dir, filePID: filePID), session.pid == filePID,
                      let started = ProcInfo.started(info),
                      isSameProcess(started: started, startedAt: session.startedAt, procStart: session.procStart)
                else { continue }
                session.ancestors = ancestors(of: info)
                if session.ancestors.contains(own) { continue }
                result.append(session)
            }
        }
        return result
    }

    /// The process's facts when it is running (not a zombie waiting to be reaped).
    private static func liveInfo(_ pid: Int32) -> proc_bsdinfo? {
        guard kill(pid, 0) == 0, let info = ProcInfo.bsdInfo(pid), info.pbi_status != UInt32(SZOMB) else { return nil }
        return info
    }

    private static func ancestors(of info: proc_bsdinfo) -> [Int32] {
        var list: [Int32] = []
        var parent = Int32(bitPattern: info.pbi_ppid)
        while parent > 1, list.count < 16, !list.contains(parent) {
            list.append(parent)
            guard let next = ProcInfo.bsdInfo(parent) else { break }
            parent = Int32(bitPattern: next.pbi_ppid)
        }
        return list
    }
}

/// The live sessions, refreshed on the monitor's tick while the panel is open, and in the background only when
/// Nabız should tell you a session started waiting for permission.
@MainActor
@Observable
final class ClaudeSessionStore {
    static let shared = ClaudeSessionStore()
    static let notificationPrefix = "claude-session-"

    /// Sorted: waiting, working, idle.
    private(set) var sessions: [ClaudeSession] = []
    /// The app to bring forward for each session, by session id.
    private(set) var hosts: [String: Int32] = [:]
    @ObservationIgnored private var reading = false
    @ObservationIgnored private var dirs: [String] = []
    @ObservationIgnored private var dirsAt: Date?
    @ObservationIgnored private var dirsFor: [String] = []
    @ObservationIgnored private var lastStatus: [String: ClaudeSession.Status] = [:]
    @ObservationIgnored private var readAt: Date?

    /// Notifications on and this one too: the sessions are read even while the panel is closed.
    static var watchesInBackground: Bool { Prefs.bool(Prefs.notifications) && Prefs.bool(Prefs.claudeSessionNotify) }

    static func shouldRefresh(panelVisible: Bool) -> Bool {
        (panelVisible && Prefs.bool(Prefs.showClaudeSessions)) || watchesInBackground
    }

    func refresh() {
        guard !reading else { return }
        reading = true
        let extra = AILimitsStore.shared.folders[AIProvider.claude.rawValue] ?? []
        // Finding the account folders lists the home folder: once a minute is plenty.
        let known = extra == dirsFor && (dirsAt.map { Date().timeIntervalSince($0) < 60 } ?? false) ? dirs : nil
        Task {
            let (found, list) = await Task.detached(priority: .utility) {
                let found = known ?? ClaudeSessions.configDirs(extra: extra)
                return (found, ClaudeSessions.read(found))
            }.value
            reading = false
            if known == nil {
                dirs = found
                dirsAt = Date()
                dirsFor = extra
            }
            update(ClaudeSessions.sorted(list))
        }
    }

    private func update(_ list: [ClaudeSession]) {
        if list != sessions { sessions = list }
        let apps = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
        let claude = NSRunningApplication.runningApplications(withBundleIdentifier: ClaudeSessions.desktopBundleID).first?.processIdentifier
        var found: [String: Int32] = [:]
        for session in list {
            found[session.id] = ClaudeSessions.host(entrypoint: session.entrypoint, ancestors: session.ancestors, apps: apps, claudeApp: claude)
        }
        if found != hosts { hosts = found }
        notify(list)
    }

    /// One notification each time a session starts waiting, and it goes away once the session moves on. A long gap
    /// since the last reading (polling was off) only sets the baseline, so old waits aren't announced late.
    private func notify(_ list: [ClaudeSession]) {
        let now = Date()
        let continuous = readAt.map { now.timeIntervalSince($0) < 90 } ?? false
        if continuous && Self.watchesInBackground {
            for session in ClaudeSessions.newlyWaiting(before: lastStatus, now: list) { post(session) }
        }
        let ended = lastStatus.filter { $0.value == .waiting }.map(\.key)
            .filter { id in list.first { $0.id == id }?.status != .waiting }
        if !ended.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ended.map { Self.notificationPrefix + $0 })
        }
        lastStatus = Dictionary(list.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
        readAt = now
    }

    private func post(_ session: ClaudeSession) {
        let center = UNUserNotificationCenter.current()
        // Clicking a notification goes through the AI notifications' delegate, which hands ours back here.
        if center.delegate == nil { center.delegate = AINotifications.shared }
        let name = ClaudeSessions.title(session)
        let title = session.waitsForPermission ? L("\(name) izin bekliyor", "\(name) needs your permission")
                                               : L("\(name) seni bekliyor", "\(name) is waiting for you")
        Notifier.shared.post(id: Self.notificationPrefix + session.id, title: title, body: subtitle(session) ?? "")
    }

    // MARK: Rows

    /// "nabiz · Work": the project, and the account when it isn't the default one.
    func subtitle(_ session: ClaudeSession) -> String? {
        // The folder adds nothing when the title already names it ("nabiz-fix" in nabiz).
        let project = ClaudeSessions.project(session.cwd).flatMap { project in
            ClaudeSessions.title(session).localizedCaseInsensitiveContains(project) ? nil : project
        }
        let parts = [project, account(session)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The nickname of a non-default account (as set under AI limits), else a short form of its folder.
    func account(_ session: ClaudeSession) -> String? {
        guard session.configDir != ClaudeSessions.defaultDir else { return nil }
        let limits = AILimitsStore.shared
        if let account = limits.accounts.first(where: { $0.provider == .claude && $0.folder == session.configDir }) {
            let nick = limits.nickname(account).trimmingCharacters(in: .whitespaces)
            if !nick.isEmpty { return nick }
        }
        if let nick = limits.nicknames["dir:" + session.configDir]?.trimmingCharacters(in: .whitespaces), !nick.isEmpty {
            return nick
        }
        return ClaudeSessions.folderLabel(session.configDir)
    }

    func canShow(_ session: ClaudeSession) -> Bool { hosts[session.id] != nil }

    /// Brings the session's app forward. Claude's own sessions open the Claude app; it has no documented way to open
    /// one session, so it shows whichever was last open there.
    func show(_ session: ClaudeSession) {
        guard let pid = hosts[session.id], let app = NSRunningApplication(processIdentifier: pid) else { return }
        Monitor.panelActions.close()
        if let url = app.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            app.activate()
        }
    }

    /// A click on a waiting notification.
    func show(notification identifier: String) {
        guard identifier.hasPrefix(Self.notificationPrefix) else { return }
        let id = String(identifier.dropFirst(Self.notificationPrefix.count))
        if let session = sessions.first(where: { $0.id == id }) { show(session) }
    }
}
