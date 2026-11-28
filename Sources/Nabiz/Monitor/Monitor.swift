// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Observation

/// A suggestion shown when something is slowing the Mac down, with the one-tap fix for it when there is one.
struct Advice: Identifiable {
    enum Level: Int, Comparable {
        case info, warning, danger
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    let kind: AdviceKind
    let title: String
    let detail: String
    let level: Level
    var fix: Fix?
    /// Usually the kind; security adds which checks are off, so turning another one off shows again after a hide.
    var id: String

    init(_ kind: AdviceKind, id: String? = nil, title: String, detail: String, level: Level, fix: Fix? = nil) {
        self.kind = kind
        self.id = id ?? kind.rawValue
        self.title = title
        self.detail = detail
        self.level = level
        self.fix = fix
    }
}

/// One tap that deals with a problem directly, instead of sending the user to a tool they may not know.
enum Fix {
    case shutdownSimulators
    case quit(ProcessGroup)
    case openClaude
    case openStorage
    case openSettings(URL?)
    case quitDocker
    case cleanRust
    case openDeveloper
    case push(String)

    /// Quitting and shutting down end something the user may still want, so the button says so in red.
    var isDestructive: Bool {
        switch self {
        case .shutdownSimulators, .quit, .quitDocker, .cleanRust: true
        case .openClaude, .openStorage, .openSettings, .openDeveloper, .push: false
        }
    }

    /// The confirmation shown in the menu bar after the tap, when there is something to confirm.
    var doneMessage: String? {
        switch self {
        case .shutdownSimulators: L("Simülatörler kapatılıyor", "Shutting down simulators")
        case .quit(let group): L("\(group.name) kapatıldı", "Quit \(group.name)")
        case .quitDocker: L("Docker kapatılıyor", "Quitting Docker")
        case .cleanRust: nil
        case .push: L("Terminal'de gönderiliyor", "Pushing in Terminal")
        case .openClaude, .openStorage, .openSettings, .openDeveloper: nil
        }
    }

    /// The button text, kept short so it fits next to the suggestion.
    var title: String {
        switch self {
        case .shutdownSimulators: L("Kapat", "Shut down")
        case .quit, .quitDocker: L("Kapat", "Quit")
        case .openClaude: L("Aç", "Open")
        case .openStorage: L("Yönet", "Manage")
        case .openSettings: L("Aç", "Open")
        case .cleanRust: L("Temizle", "Clean")
        case .openDeveloper: L("Göster", "Show")
        case .push: L("Gönder", "Push")
        }
    }
}

enum SortKey: String, CaseIterable {
    case memory, cpu
}

@MainActor
@Observable
final class Monitor {
    private(set) var system: SystemSnapshot?
    private(set) var groups: [ProcessGroup] = []
    private(set) var simulators: [Simulator] = []
    /// Dev servers listening on local ports, refreshed while the panel is open.
    private(set) var devServers: [DevServer] = []
    private(set) var network: NetworkRate?
    private(set) var battery: BatteryState?
    private(set) var batteryHealth: BatteryHealth?
    private(set) var security: [SecurityCheck] = []
    /// When the CPU went above 90% and stayed there; nil while it is below.
    private(set) var busySince: Date?
    /// When memory pressure left normal; a short spike isn't worth a suggestion.
    private(set) var tightSince: Date?
    /// Bumped when a suggestion is hidden, so the panel redraws without waiting for the next sample.
    private(set) var adviceRevision = 0
    @ObservationIgnored private var securityAt: Date?
    /// Running Docker containers; nil when Docker isn't running or its CLI isn't found.
    private(set) var dockerContainers: Int?
    @ObservationIgnored private var dockerAt: Date?
    /// The last 60 samples of CPU, RAM and GPU, oldest first, for the small graphs.
    private(set) var history = History()
    /// Simulator ids (or "all") with a shutdown in flight.
    private(set) var stopping: Set<String> = []

    /// Faster refresh while the menu is open.
    var panelVisible = false {
        didSet { if panelVisible && !oldValue { Task { await refreshForPanel() } } }
    }

    @ObservationIgnored private let systemSampler = SystemSampler()
    @ObservationIgnored private let processSampler = ProcessSampler()
    @ObservationIgnored private let networkSampler = NetworkSampler()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var ticks = 0
    /// Called after every sample, so the native menu can refresh its items.
    @ObservationIgnored var onUpdate: (() -> Void)?
    /// The panel's actions, for fixes that need to close it or confirm in the menu bar.
    @ObservationIgnored static var panelActions = PanelActions()

    init(autostart: Bool = true) {
        // The login shell's PATH (for git, docker, brew), read once off the main thread.
        Task.detached(priority: .utility) { _ = Shell.path }
        if autostart { start() }
    }

    func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let seconds = self.panelVisible ? 2 : max(Prefs.int(Prefs.refreshSeconds), 1)
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func tick(forceSimulators: Bool = false) async {
        ticks += 1
        let snapshot = await systemSampler.sample()
        system = snapshot
        history.append(snapshot)
        busySince = snapshot.cpu > 0.9 ? (busySince ?? Date()) : nil
        tightSince = snapshot.pressure != .normal ? (tightSince ?? Date()) : nil
        UsageHistory.shared.record(cpu: snapshot.cpu, memory: snapshot.memoryFraction, gpu: snapshot.gpu,
                                   ai: AILimitsStore.shared.statuses.first(where: { !$0.limits.isEmpty })?.headline?.used)
        // With the panel closed, the per-app scan (the heaviest part) runs every sixth tick: enough for suggestions.
        if panelVisible || groups.isEmpty || ticks % 6 == 0 {
            groups = await processSampler.sample()
        }
        network = await networkSampler.sample()
        battery = Battery.read()
        if panelVisible || batteryHealth == nil || ticks % 60 == 0 {
            batteryHealth = battery == nil ? nil : BatteryHealthReader.read()
        }
        // Docker's VM holds its memory even with nothing running: count containers once a minute while it's up.
        if let vm = groups.first(where: { $0.kind == .virtualMachine }), vm.memory >= 1 << 30, ProcessSampler.dockerApp != nil {
            if dockerAt.map({ Date().timeIntervalSince($0) > 60 }) ?? true {
                dockerAt = Date()
                Task { dockerContainers = await Self.dockerContainerCount() }
            }
        } else {
            dockerContainers = nil
        }
        // Rust caches: scanned at most every 30 minutes; with auto clean on, this is what keeps the disk tidy.
        if Prefs.bool(Prefs.rustAutoClean) && ticks % 60 == 0 { Toolbox.shared.scanRust() }
        // The security checklist barely changes: every 30 minutes, and when the panel opens after that.
        if securityAt.map({ Date().timeIntervalSince($0) > 1800 }) ?? true {
            securityAt = Date()
            Task { security = await SecurityChecker.run() }
        }
        let simulatorsRunning = groups.contains { $0.kind == .simulators }
        if forceSimulators || (panelVisible && ticks % 3 == 0) || (!simulatorsRunning && !simulators.isEmpty) {
            await refreshSimulators()
        }
        // Listening ports: a few milliseconds through libproc, so every tick while the panel is open.
        if panelVisible || forceSimulators { await refreshDevServers() }
        // Projects (git status) every 5 minutes in the background, for the "not pushed" suggestion; at most once a
        // minute while the panel is open.
        if ticks % 60 == 0 || panelVisible { ProjectStore.shared.refresh() }
        if panelVisible && ticks % 5 == 0 { DockerStore.shared.refresh() }
        if ticks % 3 == 0 { NotaryWatch.shared.check() }
        // The developer leftovers' size, for the suggestion: in the background twice a day.
        if ticks % 120 == 0 && AdviceKind.devCleanup.isOn { DevCleanupStore.shared.scanIfStale() }
        onUpdate?()
    }

    func refreshDevServers() async {
        devServers = await Task.detached(priority: .utility) { DevServers.running() }.value
    }

    /// Two quick samples so per-app CPU has a delta right away.
    func refreshForPanel() async {
        Brightness.shared.refresh()
        ProjectStore.shared.refresh()
        DockerStore.shared.refresh()
        await tick(forceSimulators: true)
        try? await Task.sleep(for: .milliseconds(600))
        await tick()
    }

    private func refreshSimulators() async {
        simulators = await Task.detached(priority: .utility) { Simulators.booted() }.value
    }

    // MARK: - Derived

    func top(by key: SortKey, count: Int) -> [ProcessGroup] {
        let sorted = groups.sorted { key == .memory ? $0.memory > $1.memory : $0.cpu > $1.cpu }
        return Array(sorted.prefix(max(count, 0)))
    }

    var claudeCode: ProcessGroup? { groups.first { $0.kind == .claudeCode } }

    /// What to show: every rule that fires, minus the ones turned off in Settings or hidden for now,
    /// the most serious first.
    var advice: [Advice] {
        _ = adviceRevision
        return allAdvice
            .filter { $0.kind.isOn && !AdviceSnooze.isHidden($0) }
            .enumerated()
            .sorted { $0.element.level != $1.element.level ? $0.element.level > $1.element.level : $0.offset < $1.offset }
            .map(\.element)
    }

    func hide(_ item: Advice, for seconds: TimeInterval) {
        AdviceSnooze.hide(item, for: seconds)
        adviceRevision += 1
    }

    /// "Don't show again": turns the kind off, or for security just the checks it named.
    func turnOff(_ item: Advice) {
        if item.kind == .security {
            security.filter { !$0.on && $0.kind.isWatched }.forEach { UserDefaults.standard.set(false, forKey: $0.kind.prefKey) }
        } else {
            UserDefaults.standard.set(false, forKey: item.kind.prefKey)
        }
        adviceRevision += 1
    }

    func adviceSettingsChanged() { adviceRevision += 1 }

    /// Every rule, in priority order within each level.
    private var allAdvice: [Advice] {
        guard let s = system else { return [] }
        var list: [Advice] = []
        let now = Date()

        // Memory: one suggestion, with the single step that frees the most. Critical shows at once; a tight
        // spike has to last half a minute first, so it doesn't flicker in and out.
        let swapHigh = s.swapTotal > 0 && s.swapFraction > 0.6 && s.swapUsed >= 2 << 30
        let tightLasted = tightSince.map { now.timeIntervalSince($0) >= 30 } ?? false
        if s.pressure == .critical || tightLasted || swapHigh {
            let fix = memoryFix
            let fallback = swapHigh
                ? L("Takas alanı \(Format.bytes(s.swapUsed)) dolu, Mac yavaşlar.", "Swap is at \(Format.bytes(s.swapUsed)); the Mac slows down.")
                : L("Açık uygulamalar RAM'i dolduruyor.", "Open apps are filling RAM.")
            list.append(Advice(.memory,
                               title: s.pressure == .critical ? L("Bellek kritik seviyede", "Memory is critical") : L("Bellek dolu", "Memory is full"),
                               detail: fix?.detail ?? fallback,
                               level: s.pressure == .critical ? .danger : .warning, fix: fix?.fix))
        }

        // Heat: name what works the Mac hardest, with a Quit for it.
        let busiest = groups.filter { $0.kind == .app && $0.cpu > 0.15 }.sorted { $0.cpu > $1.cpu }.first(where: canQuit)
        let hot = s.thermal >= ProcessInfo.ThermalState.serious.rawValue
        if hot {
            list.append(Advice(.thermal, title: L("Mac ısınıyor", "Your Mac is hot"),
                               detail: busiest.map { L("En çok \($0.name) yoruyor (\(Format.percent($0.cpu)))",
                                                       "\($0.name) works it hardest (\(Format.percent($0.cpu)))") }
                                   ?? L("İşlemci yavaşlatılıyor.", "The CPU is being throttled."),
                               level: s.thermal >= ProcessInfo.ThermalState.critical.rawValue ? .danger : .warning,
                               fix: busiest.map { .quit($0) }))
        }

        // CPU pinned for two minutes (and not already covered by the heat suggestion).
        if !hot, let since = busySince, now.timeIntervalSince(since) >= 120 {
            let minutes = Int(now.timeIntervalSince(since) / 60)
            list.append(Advice(.cpu, title: L("İşlemci \(minutes) dakikadır yoğun", "CPU busy for \(minutes) minutes"),
                               detail: busiest.map { L("En çok \($0.name) kullanıyor (\(Format.percent($0.cpu))).",
                                                       "\($0.name) uses the most (\(Format.percent($0.cpu))).") }
                                   ?? L("Pil daha hızlı biter, fan çalışabilir.", "The battery drains faster and the fan may spin."),
                               level: .warning, fix: busiest.map { .quit($0) }))
        }

        if let free = s.diskFree, free < 10 << 30 {
            let left = Format.bytes(free)
            list.append(Advice(.disk, title: L("Disk dolmak üzere", "Disk almost full"),
                               detail: free < 3 << 30 ? L("\(left) boş kaldı; uygulamalar kaydedemeyebilir.", "\(left) left; apps may fail to save.")
                                                      : L("\(left) boş kaldı.", "\(left) left."),
                               level: free < 3 << 30 ? .danger : .warning, fix: .openStorage))
        }

        if let battery, !battery.plugged, battery.percent <= 15 {
            let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            let time = battery.minutesLeft.map { L("yaklaşık \(Format.duration(TimeInterval($0 * 60))) kaldı", "about \(Format.duration(TimeInterval($0 * 60))) left") }
            let hint = lowPower ? nil : L("Düşük Güç Modu pili uzatır.", "Low Power Mode makes it last longer.")
            let parts = [time, hint].compactMap { $0 }
            list.append(Advice(.battery, title: L("Pil \(Format.percent(Double(battery.percent) / 100))", "Battery at \(Format.percent(Double(battery.percent) / 100))"),
                               detail: parts.isEmpty ? L("Şarja tak.", "Plug in.") : parts.joined(separator: " · "),
                               level: battery.percent <= 5 ? .danger : .warning,
                               fix: lowPower ? nil : .openSettings(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension"))))
        }

        if let burn = AILimitsStore.shared.burning.first, let runway = burn.limit.pace?.runway {
            let name = "\(AILimitsStore.shared.title(burn.status)) · \(burn.limit.label)"
            list.append(Advice(.aiBurn, title: L("\(name) hızlı bitiyor", "\(name) is burning fast"),
                               detail: L("Bu hızla \(Format.duration(runway)) sonra biter, sıfırlanmadan önce.",
                                         "At this speed it runs out in \(Format.duration(runway)), before it resets."),
                               level: .warning))
        }

        // Docker: only when the memory suggestion isn't already offering to quit it.
        if let docker = idleDocker, !list.contains(where: { $0.fix.map { if case .quitDocker = $0 { true } else { false } } ?? false }) {
            list.append(Advice(.docker, title: L("Docker boşta", "Docker is idle"),
                               detail: L("Çalışan konteyner yok ama \(Format.bytes(docker.memory)) kullanıyor.",
                                         "No containers running, but it uses \(Format.bytes(docker.memory))."),
                               level: .info, fix: .quitDocker))
        }

        if let claude = claudeCode, claude.count >= 20 {
            let memory = Format.bytes(claude.memory)
            list.append(Advice(.claude, title: L("\(claude.count) Claude Code işlemi açık", "\(claude.count) Claude Code processes"),
                               detail: L("\(memory) · eskileri Claude'da arşivle", "\(memory) · archive old ones in Claude"),
                               level: .info, fix: .openClaude))
        }

        // Developer: commits sitting unpushed for a day, leftovers past 20 GB, a crowd of simulators, notarization.
        if AdviceKind.unpushed.isOn {
            let stale = ProjectStore.shared.projects.filter { $0.ahead > 0 && $0.upstream != nil
                && ($0.lastActivity.map { Date().timeIntervalSince($0) > 86_400 } ?? false) }.sorted { $0.ahead > $1.ahead }
            if let first = stale.first {
                list.append(Advice(.unpushed, id: "unpushed:" + stale.map(\.name).joined(separator: ","),
                                   title: stale.count == 1 ? L("\(first.displayName): \(first.ahead) commit gönderilmedi", "\(first.displayName): \(first.ahead) commits not pushed")
                                                           : L("\(stale.count) projede gönderilmemiş commit", "Unpushed commits in \(stale.count) projects"),
                                   detail: stale.count == 1 ? L("\(first.branch ?? "") · bu Mac'e bir şey olursa kaybolur", "\(first.branch ?? "") · lost if something happens to this Mac")
                                                            : stale.prefix(3).map { "\($0.displayName) ↑\($0.ahead)" }.joined(separator: ", "),
                                   level: .info, fix: stale.count == 1 ? .push(first.path) : nil))
            }
        }
        let leftovers = DevCleanupStore.shared.lastTotal
        if leftovers >= 20 << 30 {
            list.append(Advice(.devCleanup, title: L("\(Format.bytes(leftovers)) geliştirici artığı", "\(Format.bytes(leftovers)) of developer leftovers"),
                               detail: L("Worktree, simülatör, build ve paket önbellekleri", "Worktrees, simulators, builds and package caches"),
                               level: .info, fix: .openDeveloper))
        }
        if simulators.count >= 3, !list.contains(where: { $0.kind == .memory }) {
            let memory = groups.first { $0.kind == .simulators }?.memory ?? 0
            list.append(Advice(.simulators, title: L("\(simulators.count) simülatör açık", "\(simulators.count) simulators running"),
                               detail: memory > 0 ? L("\(Format.bytes(memory)) bellek · kullanmadıklarını kapat", "\(Format.bytes(memory)) of memory · shut the idle ones")
                                                  : L("Kullanmadıklarını kapat", "Shut the idle ones"),
                               level: .info, fix: .shutdownSimulators))
        }
        if let notary = NotaryWatch.shared.running {
            list.append(Advice(.notarize, title: L("Apple notarize ediyor", "Apple is notarizing"),
                               detail: L("\(Format.duration(Date().timeIntervalSince(notary.started))) · bitince bildirim gelir", "\(Format.duration(Date().timeIntervalSince(notary.started))) · you'll be notified"),
                               level: .info))
        }

        let rust = Toolbox.shared.rustSize
        if rust >= 10 << 30 {
            list.append(Advice(.rust, title: L("Rust önbelleği \(Format.bytes(rust))", "Rust caches: \(Format.bytes(rust))"),
                               detail: L("Derleme önbellekleri; silinebilir, gerekince yeniden oluşur.", "Build caches; safe to delete, rebuilt when needed."),
                               level: .info, fix: .cleanRust))
        }

        // Security: only the checks the user watches, the most important named first.
        let off = security.filter { !$0.on && $0.kind.isWatched }.sorted { $0.kind.priority < $1.kind.priority }
        if let first = off.first {
            let id = "security:" + off.map(\.kind.rawValue).sorted().joined(separator: ",")
            let title = off.count == 1 ? L("\(first.title) kapalı", "\(first.title) is off")
                                       : L("\(off.count) güvenlik ayarı kapalı", "\(off.count) security settings are off")
            let detail = off.count == 1 ? first.kind.risk : off.map(\.title).joined(separator: ", ")
            list.append(Advice(.security, id: id, title: title, detail: detail,
                               level: first.kind == .fileVault ? .warning : .info,
                               fix: off.first(where: { $0.settingsURL != nil }).map { .openSettings($0.settingsURL) }))
        }

        if let health = batteryHealth?.health, health < 0.8 {
            list.append(Advice(.batteryHealth, title: L("Pil yıpranmış", "Battery is worn"),
                               detail: L("Kapasite \(Format.percent(health)); servis zamanı gelmiş olabilir.",
                                         "Capacity is \(Format.percent(health)); it may be due for service."), level: .info))
        }

        // Uptime: only when it is likely to matter (swap piling up), or after a month.
        if let boot = s.bootDate {
            let days = Int(now.timeIntervalSince(boot) / 86_400)
            if (days >= 7 && s.swapUsed >= 1 << 30) || days >= 30 {
                list.append(Advice(.uptime, title: L("\(days) gündür yeniden başlatılmadı", "Not restarted for \(days) days"),
                                   detail: s.swapUsed >= 1 << 30
                                       ? L("Takasta \(Format.bytes(s.swapUsed)) birikti; yeniden başlatmak temizler.", "\(Format.bytes(s.swapUsed)) piled up in swap; a restart clears it.")
                                       : L("Yeniden başlatmak bekleyen güncellemeleri de kurar.", "A restart also installs pending updates."),
                                   level: .info))
            }
        }
        return list
    }

    // MARK: - Actions

    func shutdown(_ simulator: Simulator) {
        stopping.insert(simulator.id)
        Task {
            await Task.detached(priority: .userInitiated) { Simulators.shutdown(simulator.id) }.value
            stopping.remove(simulator.id)
            await tick(forceSimulators: true)
        }
    }

    func stop(_ server: DevServer) {
        let key = "port:\(server.pid)"
        stopping.insert(key)
        Task {
            _ = await Task.detached(priority: .userInitiated) { DevServers.stop(server.pid) }.value
            stopping.remove(key)
            await refreshDevServers()
        }
    }

    func stopAllDevServers() {
        stopping.insert("ports")
        let pids = devServers.map(\.pid)
        Task {
            await Task.detached(priority: .userInitiated) { for pid in pids { DevServers.stop(pid) } }.value
            stopping.remove("ports")
            await refreshDevServers()
        }
    }

    func shutdownAllSimulators() {
        stopping.insert("all")
        Task {
            await Task.detached(priority: .userInitiated) { Simulators.shutdownAll() }.value
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iphonesimulator").forEach { $0.terminate() }
            stopping.remove("all")
            await tick(forceSimulators: true)
        }
    }

    /// Apps that are never offered a Quit button: Claude (would end this kind of session), Finder, ourselves.
    private static let protectedBundles: Set<String> = [
        "com.anthropic.claudefordesktop", "com.apple.finder", Bundle.main.bundleIdentifier ?? "app.nabiz.menubar",
    ]

    private func runningApps(for group: ProcessGroup) -> [NSRunningApplication] {
        guard group.kind == .app, let path = group.bundlePath else { return [] }
        return NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.path == path && !Self.protectedBundles.contains($0.bundleIdentifier ?? "")
        }
    }

    func canQuit(_ group: ProcessGroup) -> Bool { !runningApps(for: group).isEmpty }

    func quit(_ group: ProcessGroup) {
        runningApps(for: group).forEach { $0.terminate() }
        Task {
            try? await Task.sleep(for: .seconds(1))
            await tick()
        }
    }

    private static let dockerCLI = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker",
                                    "/Applications/Docker.app/Contents/Resources/bin/docker"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    private static func dockerContainerCount() async -> Int? {
        guard let cli = dockerCLI, let output = await Toolbox.run(cli, ["ps", "-q"]) else { return nil }
        return output.split(separator: "\n").count
    }

    /// Docker using a lot of memory with no container running.
    var idleDocker: ProcessGroup? {
        guard dockerContainers == 0, let vm = groups.first(where: { $0.kind == .virtualMachine }), vm.memory >= 2 << 30 else { return nil }
        return vm
    }

    /// The step that frees the most memory: running simulators first (they are rarely needed in the background),
    /// otherwise the biggest app that can be quit. Claude, Finder and Nabız are never picked.
    private var memoryFix: (fix: Fix, detail: String)? {
        if !simulators.isEmpty, let sims = groups.first(where: { $0.kind == .simulators }), sims.memory >= 512 << 20 {
            let size = Format.bytes(sims.memory)
            return (.shutdownSimulators, L("Simülatörler \(size) kullanıyor.", "Simulators use \(size)."))
        }
        if let docker = idleDocker {
            let size = Format.bytes(docker.memory)
            return (.quitDocker, L("Docker boşta \(size) kullanıyor.", "Docker sits idle using \(size)."))
        }
        let apps = groups.filter { $0.kind == .app && $0.memory >= 1 << 30 }.sorted { $0.memory > $1.memory }
        if let app = apps.first(where: canQuit) {
            let size = Format.bytes(app.memory)
            return (.quit(app), L("En çok \(app.name) kullanıyor (\(size)).", "\(app.name) uses the most (\(size))."))
        }
        return nil
    }

    func perform(_ fix: Fix) {
        switch fix {
        case .shutdownSimulators:
            shutdownAllSimulators()
        case .quit(let group):
            quit(group)
        case .openClaude:
            guard let path = ProcessSampler.claudeApp else { return }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
        case .openStorage:
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") { NSWorkspace.shared.open(url) }
        case .openSettings(let url):
            if let url { NSWorkspace.shared.open(url) }
        case .cleanRust:
            Toolbox.shared.cleanRust(actions: Monitor.panelActions)
        case .openDeveloper:
            Monitor.panelActions.close()
            SettingsWindow.show(.developer)
        case .push(let path):
            TerminalLauncher.open(path, run: "git push", title: (path as NSString).lastPathComponent + " · push")
        case .quitDocker:
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.docker.docker").forEach { $0.terminate() }
            Task {
                try? await Task.sleep(for: .seconds(2))
                await tick()
            }
        }
    }

    func openActivityMonitor() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
                                           configuration: NSWorkspace.OpenConfiguration())
    }
}

struct History {
    static let length = 60
    private(set) var cpu: [Double] = []
    private(set) var memory: [Double] = []
    private(set) var gpu: [Double] = []

    mutating func append(_ s: SystemSnapshot) {
        push(&cpu, s.cpu)
        push(&memory, s.memoryFraction)
        push(&gpu, s.gpu ?? 0)
    }

    private func push(_ list: inout [Double], _ value: Double) {
        list.append(value)
        if list.count > Self.length { list.removeFirst(list.count - Self.length) }
    }
}

enum Format {
    private static let turkish = Locale(identifier: "tr_TR")
    private static let english = Locale(identifier: "en_US")
    static var locale: Locale { Prefs.isTurkish ? turkish : english }

    /// "12,4 GB", "640 MB".
    static func bytes(_ value: UInt64) -> String {
        let gb = Double(value) / 1_073_741_824
        if gb >= 1 { return number(gb, maxDigits: gb >= 100 ? 0 : 1, minDigits: gb >= 100 ? 0 : 1) + " GB" }
        return "\(Int((Double(value) / 1_048_576).rounded())) MB"
    }

    /// "40 / 48 GB": whole gigabytes, so it fits a narrow column.
    static func usage(_ used: UInt64, of total: UInt64) -> String {
        "\(Int((Double(used) / 1_073_741_824).rounded())) / \(Int((Double(total) / 1_073_741_824).rounded())) GB"
    }

    /// Turkish puts the sign first: "%34"; English after: "34%".
    static func percent(_ fraction: Double) -> String {
        let value = Int((min(max(fraction, 0), 1) * 100).rounded())
        return Prefs.isTurkish ? "%\(value)" : "\(value)%"
    }

    static func load(_ value: Double) -> String { number(value, maxDigits: 1, minDigits: 1) }

    static func uptime(since boot: Date) -> String {
        let hours = max(Int(Date().timeIntervalSince(boot) / 3600), 1)
        if hours >= 24 { return L("\(hours / 24) gündür açık", "up \(hours / 24) days") }
        return L("\(hours) saattir açık", "up \(hours) h")
    }

    /// Time left until `date`: "45 dk", "3 sa", "2 g" / "45m", "3h", "2d".
    static func countdown(until date: Date) -> String {
        let minutes = max(Int(date.timeIntervalSinceNow / 60), 0)
        if minutes < 60 { return L("\(minutes) dk", "\(minutes)m") }
        if minutes < 48 * 60 { return L("\((minutes + 30) / 60) sa", "\((minutes + 30) / 60)h") }
        return L("\((minutes + 720) / 1440) g", "\((minutes + 720) / 1440)d")
    }

    /// Time to a reset, short but exact enough to plan by: "5g 3sa", "4sa 12dk", "12dk" / "5d 3h", "4h 12m", "12m".
    static func resetIn(until date: Date) -> String {
        let minutes = max(Int(date.timeIntervalSinceNow / 60), 0)
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        if days > 0 { return hours > 0 ? L("\(days)g \(hours)sa", "\(days)d \(hours)h") : L("\(days)g", "\(days)d") }
        if hours > 0 { return mins > 0 ? L("\(hours)sa \(mins)dk", "\(hours)h \(mins)m") : L("\(hours)sa", "\(hours)h") }
        return L("\(mins)dk", "\(mins)m")
    }

    /// "3 sa 20 dk", "45 dk", "2 g 4 sa" / "3h 20m", "45m", "2d 4h".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(Int(seconds / 60), 1)
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        if days > 0 { return L("\(days) g \(hours) sa", "\(days)d \(hours)h") }
        if hours > 0 { return L("\(hours) sa \(mins) dk", "\(hours)h \(mins)m") }
        return L("\(mins) dk", "\(mins)m")
    }

    /// "1,2 MB/s", "40 KB/s".
    static func rate(_ bytesPerSecond: Double) -> String {
        let kb = bytesPerSecond / 1024
        if kb >= 1024 { return number(kb / 1024, maxDigits: 1, minDigits: 1) + " MB/s" }
        return "\(Int(kb.rounded())) KB/s"
    }

    static func number(_ value: Double, maxDigits: Int, minDigits: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(minDigits...max(minDigits, maxDigits))).locale(locale))
    }

    /// Market prices: "60.104", "1.689,0", "70,56", "0,05587" — fewer decimals as the price grows.
    static func price(_ value: Double) -> String {
        switch value {
        case 10_000...: number(value, maxDigits: 0)
        case 10...: number(value, maxDigits: 2, minDigits: 2)
        case 1...: number(value, maxDigits: 3, minDigits: 3)
        default: number(value, maxDigits: 5, minDigits: 4)
        }
    }

    /// "▲ %1,2" / "▼ 0.4%"; empty when the move is under 0.05%.
    static func change(_ fraction: Double?) -> String {
        guard let fraction, abs(fraction) >= 0.0005 else { return "" }
        let value = number(abs(fraction) * 100, maxDigits: 1, minDigits: 1)
        return (fraction > 0 ? "▲ " : "▼ ") + (Prefs.isTurkish ? "%" + value : value + "%")
    }

    static func symbol(_ code: String) -> String {
        ["TRY": "₺", "USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥"][code] ?? code
    }

    /// "4.235,00 ₺".
    static func money(_ value: Double, _ code: String) -> String {
        number(value, maxDigits: 2, minDigits: 2) + " " + symbol(code)
    }
}
