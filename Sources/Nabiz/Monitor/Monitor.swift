import AppKit
import Observation

/// A suggestion shown when something is slowing the Mac down, with the one-tap fix for it when there is one.
struct Advice: Identifiable {
    enum Level { case info, warning, danger }

    let id: String
    let title: String
    let detail: String
    let level: Level
    var fix: Fix?
}

/// One tap that deals with a problem directly, instead of sending the user to a tool they may not know.
enum Fix {
    case shutdownSimulators
    case quit(ProcessGroup)
    case openClaude
    case openStorage
    case openSettings(URL?)

    /// Quitting and shutting down end something the user may still want, so the button says so in red.
    var isDestructive: Bool {
        switch self {
        case .shutdownSimulators, .quit: true
        case .openClaude, .openStorage, .openSettings: false
        }
    }

    /// The confirmation shown in the menu bar after the tap, when there is something to confirm.
    var doneMessage: String? {
        switch self {
        case .shutdownSimulators: L("Simülatörler kapatılıyor", "Shutting down simulators")
        case .quit(let group): L("\(group.name) kapatıldı", "Quit \(group.name)")
        case .openClaude, .openStorage, .openSettings: nil
        }
    }

    /// The button text, kept short so it fits next to the suggestion.
    var title: String {
        switch self {
        case .shutdownSimulators: L("Kapat", "Shut down")
        case .quit: L("Kapat", "Quit")
        case .openClaude: L("Aç", "Open")
        case .openStorage: L("Yönet", "Manage")
        case .openSettings: L("Aç", "Open")
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
    private(set) var network: NetworkRate?
    private(set) var battery: BatteryState?
    private(set) var batteryHealth: BatteryHealth?
    private(set) var security: [SecurityCheck] = []
    /// When the CPU went above 90% and stayed there; nil while it is below.
    private(set) var busySince: Date?
    @ObservationIgnored private var securityAt: Date?
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

    init(autostart: Bool = true) {
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
        // With the panel closed, the per-app scan (the heaviest part) runs every sixth tick: enough for suggestions.
        if panelVisible || groups.isEmpty || ticks % 6 == 0 {
            groups = await processSampler.sample()
        }
        network = await networkSampler.sample()
        battery = Battery.read()
        if panelVisible || batteryHealth == nil || ticks % 60 == 0 {
            batteryHealth = battery == nil ? nil : BatteryHealthReader.read()
        }
        // The security checklist barely changes: every 30 minutes, and when the panel opens after that.
        if securityAt.map({ Date().timeIntervalSince($0) > 1800 }) ?? true {
            securityAt = Date()
            Task { security = await SecurityChecker.run() }
        }
        let simulatorsRunning = groups.contains { $0.kind == .simulators }
        if forceSimulators || (panelVisible && ticks % 3 == 0) || (!simulatorsRunning && !simulators.isEmpty) {
            await refreshSimulators()
        }
        onUpdate?()
    }

    /// Two quick samples so per-app CPU has a delta right away.
    func refreshForPanel() async {
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

    var advice: [Advice] {
        guard let s = system else { return [] }
        var list: [Advice] = []

        // Memory: one suggestion, with the single step that frees the most.
        let swapHigh = s.swapTotal > 0 && s.swapFraction > 0.6 && s.swapUsed >= 2 << 30
        if s.pressure != .normal || swapHigh {
            let fix = memoryFix
            let fallback = swapHigh
                ? L("Takas alanı \(Format.bytes(s.swapUsed)) dolu, Mac yavaşlar.", "Swap is at \(Format.bytes(s.swapUsed)); the Mac slows down.")
                : L("Açık uygulamalar RAM'i dolduruyor.", "Open apps are filling RAM.")
            list.append(Advice(id: "memory",
                               title: s.pressure == .critical ? L("Bellek kritik seviyede", "Memory is critical") : L("Bellek dolu", "Memory is full"),
                               detail: fix?.detail ?? fallback,
                               level: s.pressure == .critical ? .danger : .warning, fix: fix?.fix))
        }

        if let claude = claudeCode, claude.count >= 20 {
            let memory = Format.bytes(claude.memory)
            list.append(Advice(id: "claude", title: L("\(claude.count) Claude Code işlemi açık", "\(claude.count) Claude Code processes"),
                               detail: L("\(memory) · eskileri Claude'da arşivle", "\(memory) · archive old ones in Claude"),
                               level: .info, fix: .openClaude))
        }

        if let burn = AILimitsStore.shared.burning.first, let runway = burn.limit.pace?.runway {
            let name = "\(burn.provider.shortName) · \(burn.limit.label)"
            list.append(Advice(id: "ai-burn", title: L("\(name) hızlı bitiyor", "\(name) is burning fast"),
                               detail: L("Bu hızla \(Format.duration(runway)) sonra biter, sıfırlanmadan önce.",
                                         "At this speed it runs out in \(Format.duration(runway)), before it resets."),
                               level: .warning))
        }

        if let free = s.diskFree, free < 10 << 30 {
            let left = Format.bytes(free)
            list.append(Advice(id: "disk", title: L("Disk dolmak üzere", "Disk almost full"),
                               detail: L("\(left) boş kaldı.", "\(left) left."), level: .warning, fix: .openStorage))
        }

        if let health = batteryHealth?.health, health < 0.8 {
            list.append(Advice(id: "battery-health", title: L("Pil yıpranmış", "Battery is worn"),
                               detail: L("Kapasite \(Format.percent(health)); servis zamanı gelmiş olabilir.",
                                         "Capacity is \(Format.percent(health)); it may be due for service."), level: .info))
        }

        if let off = security.first(where: { !$0.on }) {
            list.append(Advice(id: "security", title: L("\(off.title) kapalı", "\(off.title) is off"),
                               detail: L("Mac'in daha az korunuyor.", "Your Mac is less protected."),
                               level: .info, fix: .openSettings(off.settingsURL)))
        }

        if let battery, !battery.plugged, battery.percent <= 15 {
            list.append(Advice(id: "battery", title: L("Pil azaldı", "Battery low"),
                               detail: Format.percent(Double(battery.percent) / 100), level: .warning))
        }

        if s.thermal >= ProcessInfo.ThermalState.serious.rawValue {
            let busiest = groups.filter { $0.kind == .app && $0.cpu > 0.15 }.sorted { $0.cpu > $1.cpu }.first(where: canQuit)
            list.append(Advice(id: "thermal", title: L("Mac ısınıyor", "Your Mac is hot"),
                               detail: busiest.map { L("En çok \($0.name) yoruyor (\(Format.percent($0.cpu)))",
                                                       "\($0.name) works it hardest (\(Format.percent($0.cpu)))") }
                                   ?? L("İşlemci yavaşlatılıyor.", "The CPU is being throttled."),
                               level: s.thermal >= ProcessInfo.ThermalState.critical.rawValue ? .danger : .warning,
                               fix: busiest.map { .quit($0) }))
        }

        if let boot = s.bootDate {
            let days = Int(Date().timeIntervalSince(boot) / 86_400)
            if days >= 7 {
                list.append(Advice(id: "uptime", title: L("\(days) gündür yeniden başlatılmadı", "Not restarted for \(days) days"),
                                   detail: L("Yeniden başlatmak takas alanını temizler.", "A restart clears swap."), level: .info))
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

    /// The step that frees the most memory: running simulators first (they are rarely needed in the background),
    /// otherwise the biggest app that can be quit. Claude, Finder and Nabız are never picked.
    private var memoryFix: (fix: Fix, detail: String)? {
        if !simulators.isEmpty, let sims = groups.first(where: { $0.kind == .simulators }), sims.memory >= 512 << 20 {
            let size = Format.bytes(sims.memory)
            return (.shutdownSimulators, L("Simülatörler \(size) kullanıyor.", "Simulators use \(size)."))
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
