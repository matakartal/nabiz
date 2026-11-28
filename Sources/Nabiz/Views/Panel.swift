// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import SwiftUI

/// What the panel asks its owner to do.
struct PanelActions: Sendable {
    var copy: @MainActor @Sendable (String) -> Void = { _ in }
    /// Shows a short confirmation in the menu bar ("Copied", "Disks ejected").
    var flash: @MainActor @Sendable (String) -> Void = { _ in }
    var close: @MainActor @Sendable () -> Void = {}
}

/// The status item's panel: opaque, on one grid copied from native menus.
/// Icons start `Theme.menuInset` in, text `Theme.menuTextInset` in, values end `Theme.menuInset` before the edge.
struct PanelView: View {
    let monitor: Monitor
    let actions: PanelActions
    /// Snapshots render without the panel being open.
    var alwaysRender = false
    @AppStorage(Prefs.language) private var language = "system"
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        // While the panel is closed nothing is drawn: a placeholder holds its last size, so it reopens without a jump.
        if monitor.panelVisible || alwaysRender {
            content
        } else {
            Color.clear.frame(width: Theme.menuPanelWidth, height: height)
        }
    }

    private var height: CGFloat { min(max(contentHeight, Theme.menuRow), Theme.menuPanelMaxHeight) }

    private var content: some View {
        ScrollView {
            PanelContent(monitor: monitor, actions: actions)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.never)
        .background(HiddenScrollers())
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Theme.menuPanelWidth, height: height)
        // The window behind is the native menu material (frosted), like system menus.
        .environment(\.panelOpen, monitor.panelVisible)
        .environment(\.flash, FlashAction(actions.flash))
        .appearanceRoot()
    }
}

extension EnvironmentValues {
    /// False while the panel is hidden, so rows drop a hover highlight left over from the last time it was open.
    @Entry var panelOpen = true
    /// A short confirmation in the menu bar ("Quit Chrome").
    @Entry var flash = FlashAction { _ in }
}

/// Wraps the flash closure so the environment can compare it (closures can't be); it never changes after launch.
struct FlashAction: Equatable, Sendable {
    let run: @MainActor @Sendable (String) -> Void
    init(_ run: @escaping @MainActor @Sendable (String) -> Void) { self.run = run }
    @MainActor func callAsFunction(_ message: String) { run(message) }
    static func == (lhs: FlashAction, rhs: FlashAction) -> Bool { true }
}

struct PanelContent: View {
    let monitor: Monitor
    let actions: PanelActions
    @AppStorage(Prefs.showSystem) private var showSystem = true
    @AppStorage(Prefs.showAdvice) private var showAdvice = true
    @AppStorage(Prefs.showSimulators) private var showSimulators = true
    @AppStorage(Prefs.showPorts) private var showPorts = true
    @AppStorage(Prefs.showProjects) private var showProjects = true
    @AppStorage(Prefs.showDocker) private var showDocker = true
    @AppStorage(Prefs.showDisplays) private var showDisplays = true
    @AppStorage(Prefs.showApps) private var showMemory = true
    @AppStorage(Prefs.showCPUApps) private var showCPU = true
    @AppStorage(Prefs.showCurrency) private var showCurrency = true
    @AppStorage(Prefs.showMarkets) private var showMarkets = true
    @AppStorage(Prefs.watchedMarkets) private var watchedMarkets = ""
    @AppStorage(Prefs.showTools) private var showTools = true
    @AppStorage(Prefs.showAI) private var showAI = true
    @AppStorage(Prefs.memoryAppCount) private var memoryCount = 5
    @AppStorage(Prefs.cpuAppCount) private var cpuCount = 3
    @AppStorage(Prefs.baseCurrency) private var base = "TRY"
    @AppStorage(Prefs.watchedCurrencies) private var watched = "USD,EUR,GBP"
    @AppStorage(Prefs.sectionOrder) private var order = ""
    @AppStorage(Prefs.calendarEnabled) private var calendarOn = false
    @AppStorage(Prefs.showWeather) private var showWeather = true

    var body: some View {
        let advice = monitor.advice
        let memory = monitor.top(by: .memory, count: memoryCount)
        let cpu = monitor.top(by: .cpu, count: cpuCount)
        let codes = watched.split(separator: ",").map(String.init).filter { $0 != base }
        VStack(alignment: .leading, spacing: 0) {
            MetersView(monitor: monitor)
            WhatsNewSection(actions: actions)
            ForEach(PanelSection.ordered) { section in
                self.section(section, advice: advice, memory: memory, cpu: cpu, codes: codes)
            }
            PanelDivider()
            PanelFooter(monitor: monitor, actions: actions)
        }
        .padding(.vertical, Theme.menuHighlightInset)
        .frame(width: Theme.menuPanelWidth, alignment: .leading)
        .background {
            // Keyboard shortcuts while the panel is key.
            Button("") { actions.close(); SettingsWindow.show(nil) }.keyboardShortcut(",", modifiers: .command).hidden()
            Button("") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command).hidden()
        }
        .id(order)
    }

    /// One section, in the place Settings → Panel gives it.
    @ViewBuilder
    private func section(_ section: PanelSection, advice: [Advice], memory: [ProcessGroup], cpu: [ProcessGroup], codes: [String]) -> some View {
        switch section {
        case .system:
            if showSystem, let system = monitor.system {
                CollapsibleSection(.system, summary: Summary.system(system), summaryColor: Summary.pressureColor(system.pressure)) {
                    StatusSection(monitor: monitor)
                }
            }
        case .advice:
            if showAdvice && !advice.isEmpty {
                CollapsibleSection(.advice, summary: "\(advice.count)",
                                   summaryColor: advice.contains { $0.level != .info } ? Theme.warning.mark : Theme.textMuted) {
                    AdviceSection(monitor: monitor, advice: advice)
                }
            }
        case .simulators:
            if showSimulators && !monitor.simulators.isEmpty {
                CollapsibleSection(.simulators, summary: L("\(monitor.simulators.count) açık", "\(monitor.simulators.count) running")) {
                    SimulatorSection(monitor: monitor)
                }
            }
        case .ports:
            if showPorts && !monitor.devServers.isEmpty {
                let servers = monitor.devServers
                CollapsibleSection(.ports, summary: servers.count == 1 ? servers[0].portsText : L("\(servers.count) açık", "\(servers.count) running"),
                                   summaryColor: DevServers.duplicateProjects(servers).isEmpty ? Theme.textMuted : Theme.warning.mark) {
                    DevServerSection(monitor: monitor)
                }
            }
        case .projects:
            if showProjects && !ProjectStore.shared.projects.isEmpty {
                CollapsibleSection(.projects, summary: ProjectSection.summary,
                                   summaryColor: ProjectStore.shared.projects.contains { $0.ahead > 0 } ? Theme.warning.mark : Theme.textMuted) {
                    ProjectSection()
                }
            }
        case .docker:
            if showDocker && !DockerStore.shared.containers.isEmpty {
                CollapsibleSection(.docker, summary: DockerStore.shared.summary) { DockerSection() }
            }
        case .displays:
            if showDisplays && !Brightness.shared.displays.isEmpty {
                CollapsibleSection(.displays, summary: Brightness.shared.summary) { DisplaySection() }
            }
        case .ai:
            if showAI {
                CollapsibleSection(.ai, summary: Summary.ai()) { AISection(actions: actions) }
            }
        case .calendar:
            if calendarOn && CalendarAgenda.shared.authorized {
                let next = CalendarAgenda.shared.next
                CollapsibleSection(.calendar, summary: next.map { "\($0.title) · \(CalendarAgenda.untilText($0))" } ?? L("Boş", "Free")) {
                    CalendarSection()
                }
            }
        case .weather:
            if showWeather, let report = WeatherStore.shared.report {
                CollapsibleSection(.weather, summary: "\(Format.degrees(report.temperature)) · \(WeatherCode.title(report.code))") {
                    WeatherSection(report: report)
                }
            }
        case .memory:
            if showMemory && !memory.isEmpty {
                CollapsibleSection(.memory, summary: memory.first.map { "\($0.name) \(Format.bytes($0.memory))" } ?? "") {
                    ForEach(memory) { AppRow(group: $0, value: Format.bytes($0.memory), monitor: monitor) }
                }
            }
        case .cpu:
            if showCPU && !cpu.isEmpty {
                CollapsibleSection(.cpu, summary: cpu.first.map { "\($0.name) \(Format.percent($0.cpu))" } ?? "") {
                    ForEach(cpu) { AppRow(group: $0, value: Format.percent($0.cpu), monitor: monitor) }
                }
            }
        case .markets:
            if showMarkets {
                CollapsibleSection(.markets, summary: Summary.market()) {
                    MarketsSection(ids: watchedMarkets.split(separator: ",").map(String.init), actions: actions)
                }
            }
        case .currency:
            if showCurrency && !codes.isEmpty {
                CollapsibleSection(.currency, summary: Summary.rate(codes[0], base: base)) {
                    CurrencySection(codes: codes, base: base, actions: actions)
                }
            }
        case .tools:
            if showTools {
                CollapsibleSection(.tools, summary: KeepAwake.shared.isOn ? L("Uyanık", "Awake") : "",
                                   summaryColor: Palette.green.mark) {
                    ToolsSection(monitor: monitor, actions: actions)
                }
            }
        }
    }
}

// MARK: - Sections

private struct StatusSection: View {
    let monitor: Monitor

    var body: some View {
        if let system = monitor.system {
            PanelRow(icon: .symbol("memorychip"), title: L("Bellek baskısı", "Memory pressure")) { _ in
                Value(pressureLabel(system.pressure), color: pressureColor(system.pressure))
            }
            PanelRow(icon: .symbol("arrow.left.arrow.right"), title: L("Takas alanı", "Swap")) { _ in
                Value("\(Format.bytes(system.swapUsed)) / \(Format.bytes(system.swapTotal))",
                      color: system.swapTotal > 0 && system.swapFraction > 0.6 ? Theme.warning.mark : Theme.textMuted)
            }
            if let free = system.diskFree {
                PanelRow(icon: .symbol("internaldrive"), title: L("Disk", "Disk"), action: { monitor.perform(.openStorage) }) { hovering in
                    if hovering { Value(Fix.openStorage.title, color: Palette.green.mark) } else { Value(L("\(Format.bytes(free)) boş", "\(Format.bytes(free)) free"),
                          color: free < 10 << 30 ? Theme.warning.mark : Theme.textMuted) }
                }
            }
            if let network = monitor.network {
                PanelRow(icon: .symbol("wifi"), title: L("Ağ", "Network"),
                         action: nil) { _ in
                    TwoColumns("↓ " + Format.rate(network.down), "↑ " + Format.rate(network.up))
                }
            }
            if let battery = monitor.battery {
                PanelRow(icon: .symbol(battery.charging ? "battery.100.bolt" : "battery.75"), title: L("Pil", "Battery"),
                         action: nil) { _ in
                    TwoColumns(batteryDetail(battery), Format.percent(Double(battery.percent) / 100),
                               color: !battery.plugged && battery.percent <= 15 ? Theme.warning.mark : Theme.textMuted)
                }
                if let health = monitor.batteryHealth, let capacity = health.health {
                    PanelRow(icon: .symbol("heart.text.square"), title: L("Pil sağlığı", "Battery health")) { _ in
                        TwoColumns(health.cycles.map { L("\($0) döngü", "\($0) cycles") } ?? "", Format.percent(capacity),
                                   color: capacity < 0.8 ? Theme.warning.mark : Theme.textMuted)
                    }
                    .help(L("Tam şarj kapasitesinin, pilin ilk hâline oranı. %80'in altı yıpranmış sayılır.",
                            "Full-charge capacity against the battery's original. Under 80% counts as worn."))
                }
            }
            PanelRow(icon: .symbol("thermometer.medium"), title: L("Isı", "Heat")) { _ in
                Value(thermalLabel(system.thermal), color: system.thermal >= 2 ? Theme.warning.mark : Theme.textMuted)
            }
            .help(L("macOS'un ısı durumu. Sıcakken işlemci kendini yavaşlatır.", "macOS's thermal state. When hot, the processor slows itself down."))
            if !monitor.security.isEmpty {
                // Checks the user chose not to watch (the firewall, by default) don't turn the row orange.
                let off = monitor.security.filter { !$0.on && $0.kind.isWatched }
                PanelRow(icon: .symbol(off.isEmpty ? "checkmark.shield" : "exclamationmark.shield"), title: L("Güvenlik", "Security"),
                         action: off.first.map { check in { if let url = check.settingsURL { NSWorkspace.shared.open(url) } } }) { _ in
                    let on = monitor.security.filter(\.on).count
                    Value(off.isEmpty ? (on == monitor.security.count ? L("\(on)/\(on) açık", "all \(on) on") : L("Sorun yok", "All fine"))
                                      : off.count == 1 ? L("\(off[0].title) kapalı", "\(off[0].title) off") : L("\(off.count) ayar kapalı", "\(off.count) off"),
                          color: off.isEmpty ? Palette.green.mark : Theme.warning.mark)
                }
                .help(monitor.security.map { ($0.on ? "✓ " : "✗ ") + $0.title }.joined(separator: "\n"))
            }
        }
    }

    private func thermalLabel(_ state: Int) -> String {
        switch state {
        case 0: L("Normal", "Normal")
        case 1: L("Ilık", "Warm")
        case 2: L("Sıcak", "Hot")
        default: L("Kritik", "Critical")
        }
    }

    private func batteryDetail(_ battery: BatteryState) -> String {
        if battery.charging, let watts = monitor.batteryHealth?.adapterWatts { return "⚡︎ \(watts) W" }
        if battery.charging { return L("şarj oluyor", "charging") }
        if battery.plugged { return L("prizde", "plugged in") }
        guard let minutes = battery.minutesLeft else { return "" }
        return L("\(minutes / 60) sa \(minutes % 60) dk", "\(minutes / 60)h \(minutes % 60)m")
    }

    private func pressureLabel(_ pressure: Pressure) -> String {
        switch pressure {
        case .normal: L("Normal", "Normal")
        case .warning: L("Sıkışık", "Tight")
        case .critical: L("Kritik", "Critical")
        }
    }

    private func pressureColor(_ pressure: Pressure) -> Color {
        switch pressure {
        case .normal: Theme.textMuted
        case .warning: Theme.warning.mark
        case .critical: Theme.danger
        }
    }
}

private struct AdviceSection: View {
    let monitor: Monitor
    let advice: [Advice]
    @Environment(\.flash) private var flash

    private func run(_ fix: Fix) {
        monitor.perform(fix)
        if let message = fix.doneMessage { flash(message) }
    }

    var body: some View {
        ForEach(advice) { item in
            PanelRow(icon: .dot(color(item.level)), title: item.title, subtitle: item.detail,
                     titleColor: item.level == .danger ? Theme.danger : nil,
                     action: item.fix.map { fix in { run(fix) } }) { _ in
                // The fix is always visible: one tap, no hunting for it.
                if let fix = item.fix {
                    InlineButton(fix.title, role: fix.isDestructive ? .destructive : nil) { run(fix) }
                }
            }
            .contextMenu {
                Button(L("Yarına kadar gizle", "Hide until tomorrow")) { hide(item, for: 86_400) }
                Button(L("Bir hafta gizle", "Hide for a week")) { hide(item, for: 7 * 86_400) }
                Divider()
                Button(item.kind == .security ? L("Bu kontrolü izleme", "Stop watching this check") : L("Bir daha gösterme", "Don't show again")) {
                    monitor.turnOff(item)
                    flash(L("Ayarlar → Öneriler'den geri açabilirsin", "Turn it back on in Settings → Suggestions"))
                }
                Button(L("Öneri ayarları…", "Suggestion settings…")) { SettingsWindow.show(.advice) }
            }
        }
    }

    private func hide(_ item: Advice, for seconds: TimeInterval) {
        monitor.hide(item, for: seconds)
        flash(L("Gizlendi; ciddileşirse yine görünür", "Hidden; it comes back if it gets worse"))
    }

    private func color(_ level: Advice.Level) -> Color {
        switch level {
        case .info: Theme.textMuted
        case .warning: Theme.warning.fill
        case .danger: Theme.danger
        }
    }
}

private struct SimulatorSection: View {
    let monitor: Monitor
    @Environment(\.flash) private var flash

    var body: some View {
        ForEach(monitor.simulators) { simulator in
            let busy = monitor.stopping.contains(simulator.id) || monitor.stopping.contains("all")
            PanelRow(icon: .symbol("iphone"), title: simulator.name, subtitle: simulator.runtime,
                     action: busy ? nil : {
                         monitor.shutdown(simulator)
                         flash(L("\(simulator.name) kapatılıyor", "Shutting down \(simulator.name)"))
                     }) { hovering in
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    HStack(spacing: Theme.Spacing.m) {
                        if hovering && simulator.runtime != "Android" { SimulatorMenu(simulator: simulator) }
                        if SimTools.shared.recording?.udid == simulator.id {
                            Image(systemName: "record.circle").foregroundStyle(Theme.danger)
                        }
                        Value(L("Kapat", "Shut down"), color: hovering ? Theme.text : Theme.textMuted)
                    }
                }
            }
            .task { if simulator.runtime != "Android" { SimTools.shared.loadApps(simulator.id) } }
        }
        PanelRow(icon: .symbol("xmark.circle"), title: L("Hepsini kapat", "Shut down all"),
                 action: monitor.stopping.contains("all") ? nil : {
                     monitor.shutdownAllSimulators()
                     flash(L("Simülatörler kapatılıyor", "Shutting down simulators"))
                 }) { _ in EmptyView() }
    }
}

/// Dev servers: the project and its ports normally; open, reveal and stop while hovered.
private struct DevServerSection: View {
    let monitor: Monitor
    @Environment(\.flash) private var flash

    var body: some View {
        let servers = monitor.devServers
        let duplicates = DevServers.duplicateProjects(servers)
        ForEach(servers) { server in
            let busy = monitor.stopping.contains("port:\(server.pid)") || monitor.stopping.contains("ports")
            let twice = duplicates.contains(server.project)
            PanelRow(icon: .symbol("chevron.left.forwardslash.chevron.right"), title: server.projectName,
                     titleColor: twice ? Theme.warning.mark : nil, hoverable: !busy) { hovering in
                if busy {
                    ProgressView().controlSize(.mini)
                } else if hovering {
                    HStack(spacing: Theme.Spacing.m) {
                        if let url = server.url {
                            InlineButton(L("Aç", "Open")) { NSWorkspace.shared.open(url) }
                        }
                        Button { PhoneQR.show(server) } label: {
                            Image(systemName: "iphone").font(Theme.body).foregroundStyle(Palette.green.mark)
                        }
                        .buttonStyle(.plain)
                        .help(L("Telefonda aç (QR)", "Open on a phone (QR)"))
                        InlineButton(L("Göster", "Reveal")) {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: server.folder)])
                        }
                        InlineButton(L("Durdur", "Stop"), role: .destructive) {
                            monitor.stop(server)
                            flash(L("\(server.projectName) durduruldu", "Stopped \(server.projectName)"))
                        }
                    }
                } else {
                    Value(server.portsText)
                }
            }
            .help(twice ? L("Bu projede birden fazla sunucu açık; biri büyük ihtimalle unutulmuş.",
                            "More than one server is running in this project; one is probably forgotten.") + "\n" + subtitle(server)
                  : subtitle(server))
        }
        if servers.count > 1 {
            PanelRow(icon: .symbol("xmark.circle"), title: L("Hepsini durdur", "Stop all"),
                     action: monitor.stopping.contains("ports") ? nil : {
                         monitor.stopAllDevServers()
                         flash(L("Sunucular durduruluyor", "Stopping servers"))
                     }) { _ in EmptyView() }
        }
    }

    /// The tooltip: "vite · apps/web · 2 sa 5 dk"; one line in the panel, like every other row.
    private func subtitle(_ server: DevServer) -> String {
        var parts = [server.tool]
        if let sub = server.subfolder { parts.append(sub) }
        if let started = server.started { parts.append(Format.duration(Date().timeIntervalSince(started))) }
        return parts.joined(separator: " · ")
    }
}

/// External displays' brightness, one slider each, on the menu grid.
private struct DisplaySection: View {
    var body: some View {
        ForEach(Brightness.shared.displays) { display in
            BrightnessRow(display: display)
        }
    }
}

private struct BrightnessRow: View {
    let display: Brightness.Display
    @State private var value: Double = 0
    @State private var editing = false

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "sun.max").font(Theme.body).foregroundStyle(Theme.textMuted)
                .frame(width: Theme.menuIcon, height: Theme.menuIcon)
                .frame(width: Theme.menuTextInset - Theme.menuInset, alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text(verbatim: display.name).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer(minLength: Theme.Spacing.s)
                    Value(Format.percent(value))
                }
                Slider(value: $value, in: 0...1) { editing = $0 }
                    .controlSize(.mini)
                    .onChange(of: value) { if editing { Brightness.shared.set(value, on: display.id) } }
            }
        }
        .padding(.horizontal, Theme.menuInset)
        .padding(.vertical, Theme.Spacing.xs)
        .onAppear { value = display.brightness }
        .onChange(of: display.brightness) { if !editing { value = display.brightness } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("\(display.name) parlaklığı", "\(display.name) brightness"))
    }
}

/// An app row: the value normally, its actions while hovered.
private struct AppRow: View {
    let group: ProcessGroup
    let value: String
    let monitor: Monitor
    @Environment(\.flash) private var flash

    var body: some View {
        PanelRow(icon: icon, title: group.name, hoverable: true) { hovering in
            if hovering {
                HStack(spacing: Theme.Spacing.m) {
                    if let path = group.bundlePath {
                        InlineButton(L("Göster", "Reveal")) {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                    }
                    switch group.kind {
                    case .claudeCode:
                        InlineButton(L("Arşivle", "Archive")) { monitor.perform(Fix.openClaude) }
                    case .simulators:
                        InlineButton(L("Kapat", "Shut down")) {
                            monitor.shutdownAllSimulators()
                            flash(L("Simülatörler kapatılıyor", "Shutting down simulators"))
                        }
                    default:
                        if monitor.canQuit(group) {
                            InlineButton(L("Çık", "Quit"), role: .destructive) {
                                monitor.quit(group)
                                flash(L("\(group.name) kapatıldı", "Quit \(group.name)"))
                            }
                        }
                    }
                }
            } else {
                Value(value)
            }
        }
        .help(detail)
    }

    private var icon: RowIcon {
        if let path = group.bundlePath { return .app(path) }
        switch group.kind {
        case .simulators: return .symbol("iphone")
        case .virtualMachine: return .symbol("shippingbox")
        default: return .symbol("terminal")
        }
    }

    private var detail: String {
        let line = L("Bellek \(Format.bytes(group.memory)) · İşlemci \(Format.percent(group.cpu))",
                     "Memory \(Format.bytes(group.memory)) · CPU \(Format.percent(group.cpu))")
        return group.count > 1 ? line + " · " + L("\(group.count) işlem", "\(group.count) processes") : line
    }
}

private struct CurrencySection: View {
    let codes: [String]
    let base: String
    let actions: PanelActions
    private let rates = RateStore.shared

    var body: some View {
        ForEach(codes, id: \.self) { code in
            let value = rates.convert(1, from: code, to: base)
            PanelRow(icon: .symbol(currencySymbol(code)), title: "1 \(code)",
                     action: value.map { v in { actions.copy(Format.number(v, maxDigits: 4, minDigits: 2)) } }) { _ in
                if let value {
                    TwoColumns(changeText(code), Format.money(value, base), firstColor: changeColor(code), color: Theme.text)
                } else {
                    Value(rates.failed ? L("bağlantı yok", "offline") : L("yükleniyor…", "loading…"))
                }
            }
            .help(L("Kopyalamak için tıkla · \(rates.table?.date ?? "")", "Click to copy · \(rates.table?.date ?? "")"))
        }
    }

    private func changeText(_ code: String) -> String { Format.change(rates.change(code, in: base)) }

    private func changeColor(_ code: String) -> Color {
        guard let change = rates.change(code, in: base), abs(change) >= 0.0005 else { return Theme.textMuted }
        return change > 0 ? Palette.green.mark : Theme.warning.mark
    }

    private func currencySymbol(_ code: String) -> String {
        let names = ["TRY": "turkishlirasign", "USD": "dollarsign", "EUR": "eurosign", "GBP": "sterlingsign", "JPY": "yensign",
                     "CHF": "francsign", "INR": "indianrupeesign", "KRW": "wonsign", "CNY": "yensign"]
        return names[code].map { $0 + ".circle" } ?? "banknote"
    }
}

/// Now, rain on the way, the next sunrise or sunset and the coming days, one line each. Any row opens Weather.
private struct WeatherSection: View {
    let report: WeatherStore.Report
    @AppStorage(Prefs.weatherDetails) private var showDetails = false

    var body: some View {
        let open = { WeatherStore.openWeatherApp() }
        let feels = L("hissedilen \(Format.degrees(report.feelsLike))", "feels like \(Format.degrees(report.feelsLike))")
        PanelRow(icon: .symbol(WeatherCode.symbol(report.code, day: report.isDay)), title: report.place.name,
                 subtitle: "\(WeatherCode.title(report.code)) · \(feels)", action: open) { _ in
            Value(Format.degrees(report.temperature), color: Theme.text)
        }
        .help(details)
        if showDetails, let line = report.humidityAndWind {
            PanelRow(icon: .symbol("humidity"), title: line, action: open) { _ in EmptyView() }
        }
        if let rain = report.nextRain {
            PanelRow(icon: .symbol("umbrella"), title: WeatherCode.title(rain.code), subtitle: L("%\(rain.rain) ihtimal", "\(rain.rain)% chance"),
                     action: open) { _ in
                Value(report.clock(rain.date), color: Theme.warning.mark)
            }
        }
        if let sun = report.nextSun {
            PanelRow(icon: .symbol(sun.rise ? "sunrise" : "sunset"), title: sun.rise ? L("Gün doğumu", "Sunrise") : L("Gün batımı", "Sunset"),
                     action: open) { _ in
                Value(report.clock(sun.date))
            }
        }
        ForEach(report.upcomingDays.prefix(4)) { day in
            PanelRow(icon: .symbol(WeatherCode.symbol(day.code)), title: report.dayName(day.date),
                     subtitle: WeatherCode.title(day.code), action: open) { _ in
                TwoColumns(day.rain.map { $0 >= 20 ? L("☂ %\($0)", "☂ \($0)%") : "" } ?? "",
                           "\(Format.degrees(day.high)) / \(Format.degrees(day.low))", color: Theme.text)
            }
        }
    }

    private var details: String {
        var parts = [report.place.detail.isEmpty ? report.place.name : "\(report.place.name), \(report.place.detail)"]
        if let line = report.humidityAndWind { parts.append(line) }
        parts.append(L("Open-Meteo · Hava'da açmak için tıkla", "Open-Meteo · click to open Weather"))
        return parts.joined(separator: " · ")
    }
}

/// What's left today: each event's time on the right; a meeting with a call link joins it on click.
private struct CalendarSection: View {
    private let agenda = CalendarAgenda.shared

    var body: some View {
        let events = agenda.upcoming.prefix(5)
        if events.isEmpty {
            PanelRow(icon: .symbol("calendar"), title: L("Bugün başka etkinlik yok", "Nothing else today"),
                     action: { agenda.openInCalendar() }) { _ in EmptyView() }
        }
        ForEach(Array(events)) { event in
            PanelRow(icon: .dot(event.color), title: event.title, titleColor: event.isNow ? Theme.text : nil,
                     action: { event.meetingURL != nil ? agenda.join(event) : agenda.openInCalendar() }) { hovering in
                if hovering && event.meetingURL != nil {
                    Value(L("Katıl", "Join"), color: Theme.accent)
                } else {
                    Value(CalendarAgenda.timeText(event), color: event.isNow ? Theme.accent : Theme.textMuted)
                }
            }
            .help(event.meetingURL != nil ? L("Toplantıya katılmak için tıkla · \(event.calendar)", "Click to join the call · \(event.calendar)")
                                          : [event.location, event.calendar].compactMap { $0 }.joined(separator: " · "))
        }
    }
}

/// Watched Hyperliquid markets: 24-hour change and price; a click opens the market on Hyperliquid.
private struct MarketsSection: View {
    let ids: [String]
    let actions: PanelActions
    private let store = MarketStore.shared

    var body: some View {
        if ids.isEmpty {
            PanelRow(icon: .symbol("plus.circle"), title: L("Piyasa ekle…", "Add markets…"), action: {
                actions.close()
                SettingsWindow.show(.markets)
            }) { _ in EmptyView() }
        } else if store.markets.isEmpty && store.failed {
            PanelRow(icon: .symbol("wifi.exclamationmark"), title: L("Bağlanılamadı", "Couldn't connect"),
                     action: { store.retry() }) { _ in
                Value(L("Tekrar dene", "Try again"), color: Palette.green.mark)
            }
        } else if store.markets.isEmpty {
            PanelRow(icon: .symbol("chart.line.uptrend.xyaxis"), title: L("Yükleniyor…", "Loading…")) { _ in
                ProgressView().controlSize(.mini)
            }
        } else {
            ForEach(ids, id: \.self) { id in
                if let market = store.markets[id] {
                    PanelRow(icon: .none,
                             title: market.name,
                             action: market.tradeURL.map { url in { actions.close(); NSWorkspace.shared.open(url) } }) { hovering in
                        if hovering {
                            InlineButton(L("Alarm kur", "Set alert")) {
                                actions.close()
                                SettingsWindow.show(.markets)
                            }
                        } else {
                            HStack(spacing: Theme.Spacing.xs) {
                                if PriceAlerts.shared.markets.contains(id) {
                                    Image(systemName: "bell.fill").font(Theme.small).foregroundStyle(Theme.textMuted)
                                }
                                TwoColumns(Format.change(market.change), Format.price(market.price),
                                           firstColor: (market.change ?? 0) >= 0 ? Palette.green.mark : Theme.warning.mark, color: Theme.text)
                            }
                        }
                    }
                    .help(L("\(store.dexTitle(market.dex)) · Hyperliquid'de aç", "\(store.dexTitle(market.dex)) · open on Hyperliquid"))
                }
            }
        }
    }
}

/// The tools as a grid of tiles, Control Center style: one tap each. Keep awake opens its durations under the grid.
/// "Label: [chip] [chip]" under the tools grid.
private struct ChipRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(verbatim: label).font(Theme.small).foregroundStyle(Theme.textMuted)
            content
        }
        .padding(.horizontal, Theme.menuInset)
        .padding(.vertical, Theme.Spacing.xs)
    }
}

private enum GridEntry: Hashable {
    case tool(ToolKind)
    case more(Int)
}

/// "More tools 16 ⌄": shows the rest of the grid, or folds it back.
private struct MoreTile: View {
    let title: String
    let detail: String?
    let expanded: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: expanded ? "chevron.up" : "ellipsis").font(Theme.body).frame(width: Theme.menuIcon)
                Text(verbatim: title).font(Theme.body).lineLimit(1)
                Spacer(minLength: Theme.Spacing.xs)
                if let detail { Text(verbatim: detail).font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted) }
            }
            .padding(.horizontal, Theme.Spacing.s)
            .foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity, minHeight: Theme.toolTile)
            .background(hovering ? Theme.hover : Color.clear, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).strokeBorder(Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ToolsSection: View {
    let monitor: Monitor
    let actions: PanelActions
    @AppStorage(Prefs.hiddenTools) private var hidden = ""
    @AppStorage("toolsShowAll") private var showAll = false
    /// The tool whose duration chips are showing under the grid (keep awake or the timer).
    @State private var chips: ToolKind?
    private let timer = CountdownTimer.shared
    private let toolbox = Toolbox.shared
    private let awake = KeepAwake.shared

    var body: some View {
        let hiddenSet = Set(hidden.split(separator: ",").map(String.init))
        let tools = ToolKind.allCases.filter { !hiddenSet.contains($0.rawValue) }
        // The everyday tools first; the rest behind "More" so the grid stays short.
        let extra = tools.filter { !ToolKind.everyday.contains($0) }
        let shown: [GridEntry] = (showAll ? tools : tools.filter { ToolKind.everyday.contains($0) }).map { .tool($0) }
            + (extra.isEmpty ? [] : [.more(extra.count)])
        let rows = stride(from: 0, to: shown.count, by: Theme.toolColumns).map { Array(shown[$0..<min($0 + Theme.toolColumns, shown.count)]) }
        VStack(spacing: Theme.Spacing.xs) {
            ForEach(rows, id: \.first) { row in
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(row, id: \.self) { entry in
                        switch entry {
                        case .tool(let kind):
                            ToolTile(kind: kind, detail: toolbox.detail(kind), active: toolbox.isActive(kind),
                                     enabled: toolbox.isEnabled(kind), busy: toolbox.isBusy(kind)) {
                                if Self.withChips.contains(kind) {
                                    chips = chips == kind ? nil : kind
                                } else {
                                    toolbox.run(kind, actions: actions, monitor: monitor)
                                }
                            }
                        case .more(let count):
                            MoreTile(title: showAll ? L("Daha az", "Fewer") : L("Diğer araçlar", "More tools"),
                                     detail: showAll ? nil : "\(count)", expanded: showAll) {
                                showAll.toggle()
                                if !showAll, let open = chips, !ToolKind.everyday.contains(open) { chips = nil }
                            }
                        }
                    }
                    // An odd last row keeps its tile half wide.
                    if row.count < Theme.toolColumns { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                }
                // The choices open right under the tile that was tapped.
                if let chips, row.contains(.tool(chips)) {
                    chipsView.padding(.horizontal, -Theme.menuInset).transition(.opacity)
                }
            }
        }
        .padding(.horizontal, Theme.menuInset)
        .padding(.vertical, Theme.Spacing.xs)
    }

    private static let withChips: Set<ToolKind> = [.keepAwake, .timer, .pomodoro, .focus, .screenshot, .sleepTimer]

    @ViewBuilder private var chipsView: some View {
        if chips == .timer {
            HStack(spacing: Theme.Spacing.xs) {
                Text(L("Zamanlayıcı:", "Timer:")).font(Theme.small).foregroundStyle(Theme.textMuted)
                ForEach([5, 15, 25, 45, 60], id: \.self) { minutes in
                    Chip(L("\(minutes) dk", "\(minutes)m")) { timer.start(minutes: minutes); chips = nil }
                }
                if timer.isRunning { Chip(L("Durdur", "Stop")) { timer.stop(); chips = nil } }
            }
            .padding(.horizontal, Theme.menuInset)
            .padding(.vertical, Theme.Spacing.xs)
        }
        if chips == .pomodoro {
            let pomodoro = Pomodoro.shared
            ChipRow(L("Pomodoro:", "Pomodoro:")) {
                if !pomodoro.isActive {
                    Chip(L("Başlat \(pomodoro.minutes(.work)) dk", "Start \(pomodoro.minutes(.work))m")) { pomodoro.start(); chips = nil }
                } else {
                    Chip(pomodoro.isRunning ? L("Duraklat", "Pause") : L("Devam", "Resume")) { pomodoro.toggle(); chips = nil }
                    Chip(L("Atla", "Skip")) { pomodoro.skip(); chips = nil }
                    Chip(L("Bitir", "Stop")) { pomodoro.stop(); chips = nil }
                }
                if pomodoro.today.count > 0 {
                    Text(L("bugün \(pomodoro.today.count)", "\(pomodoro.today.count) today")).font(Theme.small).foregroundStyle(Theme.textMuted)
                }
            }
        }
        if chips == .focus {
            let focus = FocusMode.shared
            ChipRow(L("Odak:", "Focus:")) {
                Chip(L("25 dk", "25m")) { focus.start(minutes: 25); chips = nil }
                Chip(L("1 sa", "1h")) { focus.start(minutes: 60); chips = nil }
                Chip(L("2 sa", "2h")) { focus.start(minutes: 120); chips = nil }
                Chip("∞") { focus.start(minutes: nil); chips = nil }
                if focus.isOn { Chip(L("Kapat", "Off")) { focus.stop(); chips = nil } }
            }
        }
        if chips == .screenshot {
            ChipRow(L("Ekran:", "Capture:")) {
                ForEach([CaptureMode.area, .window, .screenFile]) { mode in
                    Chip(mode.chip) { chips = nil; Capture.run(mode, actions: actions) }
                }
                Chip(L("Kaydet", "Record")) { chips = nil; actions.close(); RecControl.toggle() }
            }
        }
        if chips == .sleepTimer {
            let sleep = SleepTimer.shared
            ChipRow(L("Uyut:", "Sleep in:")) {
                ForEach([15, 30, 60, 90], id: \.self) { minutes in
                    Chip(L("\(minutes) dk", "\(minutes)m")) { sleep.start(minutes: minutes); chips = nil }
                }
                if sleep.at != nil { Chip(L("İptal", "Cancel")) { sleep.cancel(); chips = nil } }
            }
        }
        if chips == .keepAwake {
            HStack(spacing: Theme.Spacing.xs) {
                Text(L("Uyanık kal:", "Keep awake:")).font(Theme.small).foregroundStyle(Theme.textMuted)
                Chip(L("15 dk", "15m")) { awake.start(minutes: 15); chips = nil }
                Chip(L("1 sa", "1h")) { awake.start(minutes: 60); chips = nil }
                Chip(L("2 sa", "2h")) { awake.start(minutes: 120); chips = nil }
                Chip("∞") { awake.start(minutes: nil); chips = nil }
                if awake.isOn { Chip(L("Kapat", "Off")) { awake.stop(); chips = nil } }
            }
            .padding(.horizontal, Theme.menuInset)
            .padding(.vertical, Theme.Spacing.xs)
        }
    }
}

/// One tool: symbol, title and an optional status line. Accent-filled while its setting is on.
private struct ToolTile: View {
    let kind: ToolKind
    let detail: String?
    let active: Bool
    let enabled: Bool
    let busy: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.panelOpen) private var panelOpen

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                ZStack {
                    if busy {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: kind.symbol).font(Theme.body)
                    }
                }
                .frame(width: Theme.menuIcon)
                Text(verbatim: kind.title).font(Theme.body).lineLimit(1).minimumScaleFactor(0.85)
                    .layoutPriority(1)
                Spacer(minLength: Theme.Spacing.xs)
                if let detail {
                    Text(verbatim: detail).font(Theme.small).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(active ? Color.white.opacity(0.85) : Theme.textMuted)
                }
            }
            .padding(.horizontal, Theme.Spacing.s)
            .foregroundStyle(active ? Color.white : Theme.text)
            .frame(maxWidth: .infinity, minHeight: Theme.toolTile)
            .background(active ? Theme.accent : (hovering && enabled ? Theme.hover : Theme.track),
                        in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .help(kind.help)
        .onHover { hovering = $0 }
        .onChange(of: panelOpen) { if !panelOpen { hovering = false } }
        .help(kind.help)
        .accessibilityLabel(kind.title)
        .accessibilityValue(detail ?? "")
        .accessibilityHint(kind.help)
    }
}

/// What came with this version, once, until it's closed: each row opens the thing it names.
private struct WhatsNewSection: View {
    let actions: PanelActions
    @AppStorage(Prefs.seenVersion) private var seen = ""
    @AppStorage(Prefs.onboarded) private var onboarded = false

    var body: some View {
        if WhatsNew.shouldShow(seen: seen, onboarded: onboarded) {
            PanelDivider()
            HStack(spacing: Theme.Spacing.s) {
                Text(L("Bu sürümde yeni", "New in this version")).font(Theme.smallStrong).foregroundStyle(Theme.accent).lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                Button(L("Hepsi", "All")) {
                    actions.close()
                    HelpWindow.show()
                }
                .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.textMuted))
                Button { seen = WhatsNew.id } label: {
                    Image(systemName: "xmark").font(Theme.smallStrong).frame(width: Theme.menuIcon - Theme.Spacing.xs)
                }
                .buttonStyle(TextButtonStyle(color: Theme.textMuted))
                .help(L("Kapat", "Close"))
                .accessibilityLabel(L("Kapat", "Close"))
            }
            .padding(.horizontal, Theme.menuInset - Theme.menuHighlightInset)
            .frame(height: Theme.menuLine)
            .padding(.horizontal, Theme.menuHighlightInset)
            .padding(.vertical, Theme.Spacing.xs)
            ForEach(WhatsNew.items) { item in
                PanelRow(icon: .symbol(item.symbol), title: item.title, action: {
                    actions.close()
                    item.open()
                }) { _ in Value(item.keys) }
                .help(item.detail)
            }
        }
    }
}

private struct AISection: View {
    let actions: PanelActions
    @AppStorage("ai.claude") private var claude = false
    @AppStorage("ai.codex") private var codex = false
    @AppStorage("ai.gemini") private var gemini = false
    @AppStorage("ai.grok") private var grok = false
    @AppStorage(Prefs.aiAsk) private var askOn = true
    private let store = AILimitsStore.shared

    var body: some View {
        // The way in to the AI itself first; the subscription limits under it.
        PanelRow(icon: .symbol("sparkles"), title: L("Sohbet", "Chat"), action: {
            actions.close()
            AIChatWindow.show()
        }) { _ in Value(Prefs.bool(Prefs.aiChatHotkey) ? HotKey.label(.aiChat) : "") }
        .help(L("Claude, Codex, Gemini, Grok ya da Apple'ın modeliyle sohbet penceresi.",
                "The chat window: Claude, Codex, Gemini, Grok or Apple's model."))
        if askOn {
            PanelRow(icon: .symbol("questionmark.bubble"), title: L("Hızlı sor", "Quick question"), action: {
                actions.close()
                LauncherPanel.shared.show(.ai)
            }) { _ in Value(Prefs.bool(Prefs.aiHotkey) ? HotKey.label(.ai) : "") }
            .help(L("Başlatıcıda sor; seçili ya da kopyalanan metni özetle, düzelt, çevir.",
                    "Ask in the launcher; summarise, fix or translate selected or copied text."))
        }
        if !(claude || codex || gemini || grok) {
            PanelRow(icon: .symbol("gauge.with.dots.needle.33percent"), title: L("Abonelik limitlerini göster…", "Show subscription limits…"), action: {
                actions.close()
                SettingsWindow.show(.aiLimits)
            }) { _ in EmptyView() }
        } else if !store.hasRead {
            PanelRow(icon: .symbol("sparkles"), title: L("Okunuyor…", "Reading…")) { _ in ProgressView().controlSize(.mini) }
        } else {
            // One block per account; a second account of the same provider carries its nickname (or e-mail).
            ForEach(store.statuses) { status in
                PanelRow(icon: icon(status.provider), title: status.provider.name, subtitle: store.label(status),
                         hoverable: status.needsSignIn) { hovering in
                    if hovering {
                        InlineButton(L("Giriş yap…", "Sign in…")) {
                            actions.close()
                            store.signIn(status.account)
                        }
                    } else {
                        Value(status.plan ?? "")
                    }
                }
                .help(store.details(status.account, email: status.email))
                if let problem = status.problem {
                    Text(verbatim: problem).font(Theme.small).foregroundStyle(Theme.textMuted).lineLimit(1)
                        .padding(.leading, Theme.menuTextInset)
                        .padding(.trailing, Theme.menuInset)
                        .frame(height: Theme.menuLine)
                }
                ForEach(status.limits) { LimitRow(limit: $0) }
            }
        }
    }

    private func icon(_ provider: AIProvider) -> RowIcon {
        let bundles = switch provider {
        case .claude: ["com.anthropic.claudefordesktop"]
        case .codex: ["com.openai.codex", "com.openai.chat"]
        case .gemini, .grok: [String]()
        }
        for bundle in bundles {
            if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)?.path { return .app(path) }
        }
        let symbol = switch provider {
        case .gemini: "sparkle"
        case .grok: "xmark.square"
        default: "bubble.left.and.text.bubble.right"
        }
        return .symbol(symbol)
    }
}

/// "Weekly  ▬▬▬▬|▭▭▭  55%  5d 3h": label, bar, percent and time to reset, each in its own column, on one line.
/// The bar shows the same thing as the number: what's left (shrinking as you use it) or what's used, as chosen in
/// Settings. The tick across it is where an even pace would be now; a fill past the tick means faster than normal.
/// The colour says where the window is heading; the forecast and exact reset time are in the tooltip.
private struct LimitRow: View {
    let limit: AILimit
    @AppStorage(Prefs.aiRemaining) private var showRemaining = true

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(verbatim: limit.label).font(Theme.small).foregroundStyle(Theme.textMuted).lineLimit(1)
                .frame(width: Theme.limitLabelColumn, alignment: .leading)
            MeterBar(value: showRemaining ? limit.remaining : limit.used, fill: color, minimum: 0,
                     mark: expected.map { showRemaining ? 1 - $0 : $0 })
            Text(verbatim: spent ? L("Bitti", "Out") : limit.shortText)
                .font(spent ? Theme.smallStrong : Theme.small).monospacedDigit().lineLimit(1)
                .foregroundStyle(spent || limit.pace?.status == .behind ? Theme.danger : Theme.text)
                .frame(width: Theme.limitPercentColumn, alignment: .trailing)
            Text(verbatim: limit.resetsAt.map(Format.resetIn(until:)) ?? "")
                .font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted).lineLimit(1)
                .frame(width: Theme.limitResetColumn, alignment: .trailing)
        }
        .frame(height: Theme.menuLine)
        .padding(.leading, Theme.menuTextInset)
        .padding(.trailing, Theme.menuInset)
        .contentShape(Rectangle())
        .help(help)
        .accessibilityElement(children: .combine)
    }

    /// The share of the window that has passed: where an even pace would have used up to by now.
    private var expected: Double? {
        if let pace = limit.pace { return pace.expected }
        guard let resetsAt = limit.resetsAt, let period = limit.period, period > 0 else { return nil }
        let passed = 1 - resetsAt.timeIntervalSinceNow / period
        return (0...1).contains(passed) ? passed : nil
    }

    private var spent: Bool { limit.used >= 1 }

    /// Red when it is used up or will run out before the reset, orange when little is left, green otherwise.
    private var color: Color {
        if spent || limit.pace?.status == .behind { return Theme.danger }
        if limit.remaining < 0.1 || limit.pace?.status == .onTrack { return Theme.warning.fill }
        return Theme.accent
    }

    private var help: String {
        var lines = [limit.displayText]
        if let expected {
            lines.append(L("Normal hızla şu an \(Format.percent(expected)) kullanılmış olurdu; sen \(Format.percent(limit.used)) kullandın.",
                           "An even pace would have used \(Format.percent(expected)) by now; you've used \(Format.percent(limit.used))."))
        }
        if let pace = limit.pace, pace.status != .spent {
            if pace.status == .behind, let runway = pace.runway {
                lines.append(L("Bu hızla \(Format.duration(runway)) sonra biter, sıfırlanmadan önce.",
                               "At this speed it runs out in \(Format.duration(runway)), before the reset."))
            } else if pace.unusedNearReset {
                lines.append(L("\(Format.percent(limit.remaining)) kullanılmadan sıfırlanacak.", "\(Format.percent(limit.remaining)) resets unused."))
            } else {
                let projected = Format.percent(min(pace.projected, 1)) + (pace.projected > 1 ? "+" : "")
                lines.append(L("Bu hızla sıfırlanırken ~\(projected) kullanılmış olur.", "At this speed ~\(projected) is used by the reset."))
            }
        }
        if let resetsAt = limit.resetsAt {
            let date = resetsAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Format.locale))
            lines.append(L("Sıfırlanma: \(date)", "Resets: \(date)"))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Grid components

enum RowIcon {
    /// No icon column: the title starts at the section heading's edge.
    case none
    case symbol(String)
    case app(String)
    case dot(Color)
}

/// One row on the menu grid. Rows with an action (or `hoverable`) highlight under the pointer like a native menu item.
struct PanelRow<Trailing: View>: View {
    let icon: RowIcon
    let title: String
    var subtitle: String?
    var titleColor: Color?
    var hoverable = false
    var action: (() -> Void)?
    @ViewBuilder var trailing: (Bool) -> Trailing
    @State private var hovering = false
    @Environment(\.panelOpen) private var panelOpen

    init(icon: RowIcon, title: String, subtitle: String? = nil, titleColor: Color? = nil, hoverable: Bool = false,
         action: (() -> Void)? = nil, @ViewBuilder trailing: @escaping (Bool) -> Trailing) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.hoverable = hoverable
        self.action = action
        self.trailing = trailing
    }

    private var interactive: Bool { action != nil || hoverable }

    var body: some View {
        HStack(spacing: 0) {
            if case .none = icon {} else {
                iconView
                    .frame(width: Theme.menuIcon, height: Theme.menuIcon)
                    .frame(width: Theme.menuTextInset - Theme.menuInset, alignment: .leading)
            }
            // One line for every row: the subtitle follows the title, muted, and truncates first.
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text(verbatim: title).font(Theme.body).foregroundStyle(titleColor ?? Theme.text).lineLimit(1)
                    .layoutPriority(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle).font(Theme.small).foregroundStyle(Theme.textMuted)
                        .lineLimit(1).truncationMode(.tail)
                        .help(subtitle)
                }
            }
            Spacer(minLength: Theme.Spacing.s)
            trailing(hovering && interactive)
        }
        .padding(.horizontal, Theme.menuInset - Theme.menuHighlightInset)
        .frame(minHeight: Theme.menuRow)
        .background(hovering && interactive ? Theme.hover : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
        .padding(.horizontal, Theme.menuHighlightInset)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { action?() }
        .onChange(of: panelOpen) { if !panelOpen { hovering = false } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(action != nil ? .isButton : [])
        .accessibilityAction { action?() }
    }

    @ViewBuilder private var iconView: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name).font(Theme.body).foregroundStyle(Theme.textMuted)
        case .app(let path):
            Image(nsImage: IconCache.icon(for: path)).resizable().interpolation(.high)
        case .dot(let color):
            Circle().fill(color).frame(width: Theme.dot, height: Theme.dot)
        case .none:
            EmptyView()
        }
    }
}

/// A panel section: divider, a header that folds it open and shut, and its rows.
/// Closed, the header shows a one-line summary on the right, so nothing important disappears.
struct CollapsibleSection<Content: View>: View {
    let section: PanelSection
    var summary: String
    var summaryColor: Color
    @ViewBuilder var content: Content
    @AppStorage private var expanded: Bool
    @AppStorage(Prefs.collapsible) private var collapsible = true

    init(_ section: PanelSection, summary: String = "", summaryColor: Color = Theme.textMuted, @ViewBuilder content: () -> Content) {
        self.section = section
        self.summary = summary
        self.summaryColor = summaryColor
        self.content = content()
        _expanded = AppStorage(wrappedValue: true, section.expandedKey)
    }

    private var open: Bool { !collapsible || expanded }

    var body: some View {
        PanelDivider()
        SectionHeader(section.title, summary: open ? "" : summary, summaryColor: summaryColor,
                      open: open, collapsible: collapsible) { section.toggle() }
        if open { content }
    }
}

/// A section title on the menu grid. Collapsible headers highlight under the pointer and end in a chevron
/// that sits in the value column's right edge.
struct SectionHeader: View {
    let text: String
    var symbol: String?
    var summary = ""
    var summaryColor = Theme.textMuted
    var open = true
    var collapsible = false
    var action: () -> Void = {}
    @State private var hovering = false
    @Environment(\.panelOpen) private var panelOpen

    init(_ text: String, symbol: String? = nil, summary: String = "", summaryColor: Color = Theme.textMuted, open: Bool = true,
         collapsible: Bool = false, action: @escaping () -> Void = {}) {
        self.text = text
        self.symbol = symbol
        self.summary = summary
        self.summaryColor = summaryColor
        self.open = open
        self.collapsible = collapsible
        self.action = action
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(verbatim: text).font(Theme.smallStrong).foregroundStyle(Theme.textMuted).lineLimit(1)
            Spacer(minLength: Theme.Spacing.s)
            if !summary.isEmpty {
                Text(verbatim: summary).font(Theme.small).monospacedDigit().foregroundStyle(summaryColor).lineLimit(1)
            }
            if collapsible {
                Image(systemName: "chevron.right")
                    .font(Theme.smallStrong)
                    .foregroundStyle(Theme.textMuted)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: Theme.menuIcon - Theme.Spacing.xs)
            }
        }
        .padding(.horizontal, Theme.menuInset - Theme.menuHighlightInset)
        .frame(height: Theme.menuLine)
        .background(hovering && collapsible ? Theme.hover : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
        .padding(.horizontal, Theme.menuHighlightInset)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, open ? Theme.Spacing.xs : 0)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if collapsible { action() } }
        .onChange(of: panelOpen) { if !panelOpen { hovering = false } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(collapsible ? .isButton : .isHeader)
        .accessibilityValue(collapsible ? (open ? L("açık", "expanded") : L("kapalı", "collapsed")) : "")
        .accessibilityAction { if collapsible { action() } }
    }
}

/// "● All good" / "● 2 suggestions": the panel's one-glance verdict, in the header.
private struct StatusPill: View {
    let monitor: Monitor

    var body: some View {
        let advice = monitor.advice
        let danger = advice.contains { $0.level == .danger }
        let warning = advice.contains { $0.level == .warning }
        let color = danger ? Theme.danger : warning ? Theme.warning.fill : Theme.accent
        let text = advice.isEmpty ? L("Her şey yolunda", "All good")
            : danger ? L("Dikkat gerekiyor", "Needs attention")
            : L("\(advice.count) öneri", advice.count == 1 ? "1 suggestion" : "\(advice.count) suggestions")
        HStack(spacing: Theme.Spacing.xs) {
            Circle().fill(color).frame(width: Theme.dot, height: Theme.dot)
            Text(verbatim: text).font(Theme.smallStrong).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs / 2)
        .background(Theme.track, in: Capsule())
    }
}

/// Uptime and load on the left; Settings and Quit as small buttons on the right.
private struct PanelFooter: View {
    let monitor: Monitor
    let actions: PanelActions

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let release = Updater.shared.available {
                Button {
                    actions.close()
                    Updater.shared.offer()
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        if Updater.shared.installing { ProgressView().controlSize(.mini) }
                        Text(L("\(release.version) sürümüne güncelle", "Update to \(release.version)")).font(Theme.smallStrong)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, Theme.Spacing.xs / 2)
                    .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(Updater.shared.installing)
                .help(L("Yenilikleri gösterir; sonra indirir, kurar ve Nabız'ı yeniden açar.", "Shows what's new, then downloads, installs and reopens Nabız."))
            } else {
                Text(verbatim: detail).font(Theme.small).foregroundStyle(Theme.textMuted).lineLimit(1)
            }
            Spacer()
            FooterButton(symbol: "questionmark.circle", help: L("Neler yapabilir?", "What can it do?")) {
                actions.close()
                HelpWindow.show()
            }
            FooterButton(symbol: "gearshape", help: L("Ayarlar (⌘,)", "Settings (⌘,)")) {
                actions.close()
                SettingsWindow.show(nil)
            }
            FooterButton(symbol: "power", help: L("Nabız'dan çık (⌘Q)", "Quit Nabız (⌘Q)")) { NSApp.terminate(nil) }
        }
        .padding(.leading, Theme.menuInset)
        .padding(.trailing, Theme.menuInset - Theme.Spacing.xs)
    }

    private var detail: String {
        guard let system = monitor.system else { return "" }
        let uptime = system.bootDate.map(Format.uptime(since:)) ?? ""
        return [uptime, L("yük", "load") + " " + Format.load(system.load)].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct FooterButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.body)
                .foregroundStyle(hovering ? Theme.text : Theme.textMuted)
                .frame(width: Theme.menuRow, height: Theme.menuRow)
                .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// One-line summaries shown on a closed section's header.
@MainActor
enum Summary {
    static func system(_ s: SystemSnapshot) -> String {
        let pressure = switch s.pressure {
        case .normal: L("Normal", "Normal")
        case .warning: L("Sıkışık", "Tight")
        case .critical: L("Kritik", "Critical")
        }
        return "\(pressure) · " + L("takas \(Format.bytes(s.swapUsed))", "swap \(Format.bytes(s.swapUsed))")
    }

    static func pressureColor(_ pressure: Pressure) -> Color {
        switch pressure {
        case .normal: Theme.textMuted
        case .warning: Theme.warning.mark
        case .critical: Theme.danger
        }
    }

    static func ai() -> String {
        guard let status = AILimitsStore.shared.statuses.first(where: { !$0.limits.isEmpty }),
              let top = status.headline else { return "" }
        return Prefs.bool(Prefs.aiRemaining)
            ? L("\(status.provider.shortName) \(top.shortText) kaldı", "\(status.provider.shortName) \(top.shortText) left")
            : "\(status.provider.shortName) \(top.shortText)"
    }

    static func market() -> String {
        guard let market = MarketStore.shared.watched.first else { return "" }
        return "\(market.name) \(Format.price(market.price))"
    }

    static func rate(_ code: String, base: String) -> String {
        guard let value = RateStore.shared.convert(1, from: code, to: base) else { return "" }
        return "\(code) \(Format.money(value, base))"
    }
}

struct PanelDivider: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
            .padding(.horizontal, Theme.menuInset)
            .padding(.vertical, Theme.menuHighlightInset)
    }
}

/// A right-aligned value in the row's trailing column.
struct Value: View {
    let text: String
    var color: Color = Theme.textMuted
    init(_ text: String, color: Color = Theme.textMuted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(verbatim: text).font(Theme.body).monospacedDigit().foregroundStyle(color).lineLimit(1)
    }
}

/// Two right-aligned values; the first sits in a fixed column so it lines up from row to row.
struct TwoColumns: View {
    let first: String
    let second: String
    var firstColor: Color = Theme.textMuted
    var color: Color = Theme.textMuted

    init(_ first: String, _ second: String, firstColor: Color = Theme.textMuted, color: Color = Theme.textMuted) {
        self.first = first
        self.second = second
        self.firstColor = firstColor
        self.color = color
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: first).font(Theme.body).monospacedDigit().foregroundStyle(firstColor).lineLimit(1)
                .frame(width: Theme.menuValueColumn, alignment: .trailing)
            Text(verbatim: second).font(Theme.body).monospacedDigit().foregroundStyle(color).lineLimit(1)
                .frame(minWidth: Theme.menuValueColumn, alignment: .trailing)
        }
    }
}

struct Shortcut: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }
    var body: some View { Text(verbatim: keys).font(Theme.body).foregroundStyle(Theme.textMuted) }
}

/// A compact text button inside a row (Reveal, Quit).
struct InlineButton: View {
    let title: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) { Text(verbatim: title) }
            .buttonStyle(TextButtonStyle(font: Theme.body, color: role == .destructive ? Theme.danger : Palette.green.mark))
    }
}

/// A small pill choice (keep-awake durations).
struct Chip: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(verbatim: title).font(Theme.small).foregroundStyle(Theme.text)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.hover, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
enum IconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(for path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }
}

private func openSettings(_ pane: String) {
    guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
    NSWorkspace.shared.open(url)
}

// MARK: - Meters

/// CPU, RAM and GPU with the last two minutes each, on the same grid as the rows.
struct MetersView: View {
    let monitor: Monitor

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: Theme.menuIcon + 2, height: Theme.menuIcon + 2)
                Text(verbatim: "Nabız").font(Theme.bodyStrong).foregroundStyle(Theme.text)
                Spacer()
                StatusPill(monitor: monitor)
                    .onTapGesture {
                        UserDefaults.standard.set(true, forKey: Prefs.showAdvice)
                        PanelSection.advice.setExpanded(true)
                    }
                    .help(L("Önerileri göster", "Show suggestions"))
            }
            HStack(spacing: Theme.Spacing.m) {
                if let system = monitor.system {
                    Meter(label: "CPU", value: system.cpu, history: monitor.history.cpu,
                          fill: system.cpu > 0.85 ? Theme.warning.fill : Theme.accent,
                          detail: L("\(system.cores) çekirdek", "\(system.cores) cores"))
                    Meter(label: "RAM", value: system.memoryFraction, history: monitor.history.memory, fill: ramFill(system.pressure),
                          detail: Format.usage(system.memoryUsed, of: system.memoryTotal))
                    Meter(label: "GPU", value: system.gpu ?? 0, history: monitor.history.gpu,
                          fill: (system.gpu ?? 0) > 0.85 ? Theme.warning.fill : Theme.accent,
                          detail: system.gpu == nil ? "—" : L("Grafik", "Graphics"))
                } else {
                    Text(L("Ölçülüyor…", "Measuring…")).font(Theme.small).foregroundStyle(Theme.textMuted)
                }
            }
        }
        .padding(.horizontal, Theme.menuInset)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture {
            HistoryWindow.show()
        }
        .help(L("Tıkla: son 1 saat, 24 saat ve 7 gün", "Click: the last hour, day and week"))
    }

    private func ramFill(_ pressure: Pressure) -> Color {
        switch pressure {
        case .normal: Theme.accent
        case .warning: Theme.warning.fill
        case .critical: Theme.danger
        }
    }
}

private struct Meter: View {
    let label: String
    let value: Double
    let history: [Double]
    let fill: Color
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: label).font(Theme.small).foregroundStyle(Theme.textMuted)
                Spacer(minLength: 0)
                Text(verbatim: Format.percent(value)).font(Theme.bodyStrong).monospacedDigit().foregroundStyle(Theme.text)
            }
            Sparkline(values: history, fill: fill)
            Text(verbatim: detail).font(Theme.small).foregroundStyle(Theme.textMuted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The last two minutes as a filled line, 0...1 bottom to top.
private struct Sparkline: View {
    let values: [Double]
    let fill: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.track))
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(History.length - 1)
            let start = size.width - step * CGFloat(values.count - 1)
            func point(_ index: Int) -> CGPoint {
                CGPoint(x: start + step * CGFloat(index), y: size.height * (1 - CGFloat(min(max(values[index], 0), 1))))
            }
            var line = Path()
            line.move(to: point(0))
            for index in values.indices.dropFirst() { line.addLine(to: point(index)) }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: start, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(fill.opacity(0.25)))
            context.stroke(line, with: .color(fill), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .frame(height: Theme.Spacing.xl)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.xs, style: .continuous))
    }
}

/// Sample limits for `--snapshot … --limits`: every state a limit row can be in.
struct LimitsPreview: View {
    var body: some View {
        let now = Date()
        func limit(_ label: String, used: Double, hoursLeft: Double, period: Double, rate: Double? = nil) -> AILimit {
            let reset = now.addingTimeInterval(hoursLeft * 3600)
            var item = AILimit(id: label, label: label, used: used, resetsAt: reset, period: period * 3600)
            item.pace = PaceModel.read(used: used, resetsAt: reset, period: period * 3600, recentRate: rate, now: now)
            return item
        }
        return VStack(alignment: .leading, spacing: 0) {
            LimitRowPreviewHost(limit: limit("Weekly", used: 0.98, hoursLeft: 2, period: 168))
            LimitRowPreviewHost(limit: limit("Fable", used: 1, hoursLeft: 2, period: 168))
            LimitRowPreviewHost(limit: limit("5-hour", used: 0.62, hoursLeft: 3.5, period: 5))
            LimitRowPreviewHost(limit: limit("Burst", used: 0.30, hoursLeft: 100, period: 168, rate: 0.05 / 3600))
            LimitRowPreviewHost(limit: limit("Codex", used: 0.2, hoursLeft: 20, period: 168))
        }
        .padding(.vertical, Theme.Spacing.s)
        .frame(width: Theme.menuPanelWidth)
    }
}

private struct LimitRowPreviewHost: View {
    let limit: AILimit
    var body: some View { LimitRow(limit: limit) }
}
