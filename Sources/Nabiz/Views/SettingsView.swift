import AppKit
import Observation
import ServiceManagement
import Carbon.HIToolbox
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general, appearance, menuBar, panel, launcher, clipboard, snippets, windows, focus, schedules, markets, currency, ai, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L("Genel", "General")
        case .appearance: L("Görünüm", "Appearance")
        case .menuBar: L("Menü çubuğu", "Menu Bar")
        case .panel: L("Panel", "Panel")
        case .launcher: L("Başlatıcı", "Launcher")
        case .clipboard: L("Pano", "Clipboard")
        case .snippets: L("Parçacıklar", "Snippets")
        case .windows: L("Pencereler", "Windows")
        case .focus: L("Odak", "Focus")
        case .schedules: L("Görevler", "Schedules")
        case .markets: L("Piyasalar", "Markets")
        case .currency: L("Döviz", "Currency")
        case .ai: L("AI limitleri", "AI Limits")
        case .about: L("Hakkında", "About")
        }
    }

    /// One line under the page title: what this page is for.
    var subtitle: String {
        switch self {
        case .general: L("Dil, açılış, yenileme ve kısayollar.", "Language, startup, refresh and shortcuts.")
        case .appearance: L("Renk, tema, yazı tipi, boyut ve sıklık.", "Colour, theme, typeface, size and density.")
        case .menuBar: L("Menü çubuğunda ne ve nasıl görüneceği.", "What the menu bar shows, and how.")
        case .panel: L("Paneldeki bölümler, sıraları, katlama ve araçlar.", "The panel's sections, their order, folding and tools.")
        case .launcher: L("Uygulama, komut, hesap ve web araması tek yerde.", "Apps, commands, maths and web search in one place.")
        case .clipboard: L("Kopyaladıklarının geçmişi ve yapıştırma.", "The history of what you copied, and pasting.")
        case .snippets: L("Kısa bir kelimeyle yapıştırılan hazır metinler.", "Saved text you paste with a short keyword.")
        case .windows: L("Öndeki pencereyi kısayolla yerleştir.", "Place the front window with a shortcut.")
        case .focus: L("Pomodoro süreleri ve odakta gizlenecek uygulamalar.", "Pomodoro lengths, and the apps focus mode hides.")
        case .schedules: L("Belirli gün ve saatlerde kendiliğinden yapılacak işler.", "Things done on their own at set days and times.")
        case .markets: L("Hyperliquid'den izlenecek piyasalar.", "The Hyperliquid markets to watch.")
        case .currency: L("Ana para birimi ve izlenen kurlar.", "Your main currency and the rates you watch.")
        case .ai: L("Abonelik limitleri ve harcama hızı.", "Subscription limits and how fast they burn.")
        case .about: ""
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintpalette.fill"
        case .menuBar: "menubar.rectangle"
        case .panel: "list.bullet.rectangle.fill"
        case .launcher: "magnifyingglass"
        case .clipboard: "doc.on.clipboard.fill"
        case .snippets: "text.quote"
        case .windows: "rectangle.split.2x1.fill"
        case .focus: "brain.head.profile"
        case .schedules: "calendar.badge.clock"
        case .markets: "chart.line.uptrend.xyaxis"
        case .currency: "dollarsign.arrow.circlepath"
        case .ai: "sparkles"
        case .about: "info.circle.fill"
        }
    }
}

@MainActor
@Observable
final class SettingsSelection {
    var page: SettingsPage? = .general
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    private static let selection = SettingsSelection()
    /// The live monitor, for the menu bar preview.
    static weak var monitor: Monitor?

    static func show(_ page: SettingsPage?) {
        if let page { selection.page = page }
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(selection: selection))
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.setContentSize(NSSize(width: 680, height: 500))
            window.center()
            self.window = window
        }
        window?.title = L("Nabız Ayarları", "Nabız Settings")
        // macOS 14+ activates cooperatively: ask the frontmost app to yield, then come forward regardless.
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            NSRunningApplication.current.activate(from: front, options: [])
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

/// Settings in the System Settings shape: a sidebar of pages, a grouped form on the right. Opaque throughout.
struct SettingsView: View {
    @Bindable var selection: SettingsSelection
    @AppStorage(Prefs.language) private var language = "system"

    init(selection: SettingsSelection = SettingsSelection()) {
        self.selection = selection
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $selection.page) { page in
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: page.symbol)
                        .font(Theme.small)
                        .foregroundStyle(.white)
                        .frame(width: Theme.settingsIcon, height: Theme.settingsIcon)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
                    Text(page.title).font(Theme.body).lineLimit(1).minimumScaleFactor(0.85)
                }
                .tag(page)
            }
            .listStyle(.sidebar)
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)
            .navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 260)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                switch selection.page ?? .general {
                case .general: GeneralPage()
                case .appearance: AppearancePage()
                case .menuBar: MenuBarPage()
                case .panel: PanelPage()
                case .launcher: LauncherPage()
                case .clipboard: ClipboardPage()
                case .snippets: SnippetsPage()
                case .windows: WindowsPage()
                case .focus: FocusPage()
                case .schedules: SchedulesPage()
                case .markets: MarketsPage()
                case .currency: CurrencyPage()
                case .ai: AIPage()
                case .about: AboutPage()
                }
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .background(HiddenScrollers().id(selection.page))
            .navigationTitle("")
        }
        .frame(minWidth: 640, minHeight: 460)
        .background(MenuMaterial().ignoresSafeArea())
        .appearanceRoot(opaqueFill: Theme.surface)
    }
}

// MARK: - Pages

private struct GeneralPage: View {
    @AppStorage(Prefs.language) private var language = "system"
    @AppStorage(Prefs.refreshSeconds) private var refresh = 5
    @AppStorage(Prefs.hotkey) private var hotkey = true
    @AppStorage(Prefs.panelHotkey) private var panelHotkey = true
    @AppStorage(Prefs.clipboardHotkey) private var clipboardHotkey = true
    @AppStorage(Prefs.noteHotkey) private var noteHotkey = true
    @AppStorage(Prefs.notesApp) private var notesApp = "nabiz"
    @AppStorage(Prefs.notifications) private var notifications = false
    @AppStorage(Prefs.rustAutoClean) private var rustAutoClean = false
    @AppStorage(Prefs.rustAutoCleanDays) private var rustDays = 14
    @State private var login = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .general) }
            Section {
                Picker(L("Dil", "Language"), selection: $language) {
                    Text(L("Sistem", "System")).tag("system")
                    Text(verbatim: "Türkçe").tag("tr")
                    Text(verbatim: "English").tag("en")
                }
                Toggle(L("Girişte aç", "Open at login"), isOn: Binding(get: { login }, set: setLogin))
            }
            Section {
                Picker(L("Arka planda yenile", "Refresh in background"), selection: $refresh) {
                    ForEach([1, 2, 5, 10, 30], id: \.self) { Text(L("\($0) saniyede bir", "every \($0) s")).tag($0) }
                }
            } footer: {
                Footnote(L("Panel açıkken her 2 saniyede bir yenilenir. Seyrek yenileme pili korur.",
                       "While the panel is open it refreshes every 2 seconds. Slower refresh saves battery."))
            }
            Section {
                HotKeyRow(title: L("Başlatıcı", "Launcher"), shortcut: .launcher, enabled: $hotkey)
                HotKeyRow(title: L("Pano geçmişi", "Clipboard history"), shortcut: .clipboard, enabled: $clipboardHotkey)
                HotKeyRow(title: L("Notlar", "Notes"), shortcut: .note, enabled: $noteHotkey)
                HotKeyRow(title: L("Panel", "Panel"), shortcut: .panel, enabled: $panelHotkey)
                Button(L("Neler yapabilir?", "What can it do?")) { HelpWindow.show() }
            } header: {
                Text(L("Kısayollar", "Shortcuts"))
            } footer: {
                Footnote(L("Değiştirmek için kısayola tıkla ve yeni tuşlara bas (en az bir ⌘, ⌃ ya da ⌥ ile). ⎋ vazgeçer, ⌫ varsayılana döndürür. Pencere kısayolları Pencereler sayfasında.",
                           "Click a shortcut and press the new keys (with at least ⌘, ⌃ or ⌥). ⎋ cancels, ⌫ goes back to the default. Window shortcuts are on the Windows page."))
            }
            Section {
                Picker(L("Notlar için", "For notes"), selection: $notesApp) {
                    Text(L("Nabız notları", "Nabız notes")).tag("nabiz")
                    Text(L("Apple Notlar", "Apple Notes")).tag("apple")
                }
            } footer: {
                Footnote(L("Not kısayolu, Notlar aracı ve \"Not olarak kaydet\" seçtiğin uygulamayı kullanır. Apple Notlar için macOS bir kez izin ister.",
                           "The notes shortcut, the Notes tool and \"Save as note\" use the app you pick. For Apple Notes, macOS asks once for permission."))
            }
            Section {
                Toggle(L("Bildirimler", "Notifications"), isOn: Binding(get: { notifications }, set: { on in
                    notifications = on
                    if on { Notifier.shared.requestPermission() }
                }))
            } footer: {
                Footnote(L("Bellek kritikleşince, işlemci 3 dakika %90'ın üstünde kalınca, disk 10 GB'ın altına inince, pil %10'a düşünce ve açık bir AI limiti hızlı bitince ya da kullanılmadan sıfırlanacakken haber verir. Her durum için bir kez.",
                           "Tells you when memory turns critical, the CPU stays above 90% for 3 minutes, the disk drops under 10 GB, the battery reaches 10%, and an AI limit you turned on burns fast or is about to reset unused. Once each time."))

            }
            Section {
                Toggle(L("Kullanılmayan Rust önbelleklerini otomatik sil", "Delete unused Rust build caches automatically"),
                       isOn: $rustAutoClean)
                Picker(L("Ne kadar süre derlenmediyse", "When not built for"), selection: $rustDays) {
                    ForEach([3, 7, 14, 30], id: \.self) { Text(L("\($0) gün", "\($0) days")).tag($0) }
                }
                .disabled(!rustAutoClean)
            } header: {
                Text(L("Otomatik temizlik", "Automatic clean-up"))
            } footer: {
                Footnote(L("Sadece cargo'nun işaretlediği target/ klasörleri silinir; kod, ayar ve Cargo.lock'a dokunulmaz. Son 10 dakikada derlenen proje atlanır. Taranan yerler: ~/Developer, ~/Projects, ~/code, ~/src.",
                           "Only target/ folders cargo marked as caches are deleted; code, settings and Cargo.lock are untouched. A project built in the last 10 minutes is skipped. Looks in ~/Developer, ~/Projects, ~/code, ~/src."))
            }
            Section {
                Button(L("Tüm ayarları sıfırla…", "Reset all settings…"), role: .destructive) { resetAll() }
            }
        }
        .formStyle(.grouped)
    }

    /// Back to the defaults; the cached rates and the welcome stay so nothing has to load or show again.
    private func resetAll() {
        let alert = NSAlert()
        alert.messageText = L("Tüm ayarlar sıfırlansın mı?", "Reset all settings?")
        alert.informativeText = L("Menü çubuğu, panel, piyasalar, döviz ve AI seçimleri ilk hâline döner.",
                                  "Menu bar, panel, markets, currency and AI choices go back to how they started.")
        alert.addButton(withTitle: L("Sıfırla", "Reset"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn, let domain = Bundle.main.bundleIdentifier else { return }
        let keep = ["rateCache", Prefs.onboarded]
        let saved = keep.compactMap { key in UserDefaults.standard.object(forKey: key).map { (key, $0) } }
        UserDefaults.standard.removePersistentDomain(forName: domain)
        for (key, value) in saved { UserDefaults.standard.set(value, forKey: key) }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()
        }
        login = SMAppService.mainApp.status == .enabled
    }
}

private struct MenuBarPage: View {
    @AppStorage(Prefs.barIcon) private var icon = true
    @AppStorage(Prefs.barSymbol) private var symbol = "gauge.with.dots.needle.33percent"
    @AppStorage(Prefs.barLabels) private var labels = true
    @AppStorage(Prefs.barStyle) private var style = "stacked"
    @AppStorage(Prefs.barMarket) private var marketOn = false
    @AppStorage(Prefs.barMarketID) private var barMarketID = ""
    @AppStorage(Prefs.watchedMarkets) private var watchedRaw = ""
    private var watchedMarkets: [String] { watchedRaw.split(separator: ",").map(String.init) }
    @AppStorage("ai.claude") private var claude = false
    @AppStorage("ai.codex") private var codex = false
    @AppStorage("ai.gemini") private var gemini = false

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .menuBar) }
            Section {
                MenuBarPreview(showIcon: icon, stacked: style != "line")
                Picker(L("Yerleşim", "Layout"), selection: $style) {
                    Text(L("İki satır", "Two lines")).tag("stacked")
                    Text(L("Tek satır", "One line")).tag("line")
                }
                .pickerStyle(.segmented)
            } header: {
                Text(L("Önizleme", "Preview"))
            }
            Section(L("Sistem", "System")) {
                ForEach([MenuBarItem.cpu, .ram, .gpu, .swap, .network, .disk, .battery]) { BarToggle(item: $0) }
            }
            Section {
                BarToggle(item: .ai)
                BarToggle(item: .market)
                if marketOn && !watchedMarkets.isEmpty {
                    Picker(L("Gösterilecek piyasa", "Market to show"), selection: $barMarketID) {
                        Text(L("İlk izlenen", "First watched")).tag("")
                        ForEach(watchedMarkets, id: \.self) { Text(verbatim: $0).tag($0) }
                    }
                }
                BarToggle(item: .currency)
            } header: {
                Text(L("Diğer", "Other"))
            } footer: {
                Footnote(claude || codex || gemini
                    ? L("AI limiti, açık sağlayıcılar arasında en çok dolmuş olanı gösterir. Döviz kuru, izlenen ilk kuru gösterir.",
                        "AI limit shows the fullest window among the providers you turned on. Exchange rate shows the first watched rate.")
                    : L("AI limitini göstermek için önce AI limitleri sayfasından bir sağlayıcı aç.",
                        "To show an AI limit, first turn on a provider on the AI Limits page."))
            }
            Section {
                Toggle(L("Simge", "Icon"), isOn: $icon)
                Picker(L("Simge biçimi", "Icon style"), selection: $symbol) {
                    ForEach(BarSymbol.all, id: \.self) { name in
                        Label { Text(verbatim: BarSymbol.title(name)) } icon: { Image(systemName: name) }.tag(name)
                    }
                }
                .disabled(!icon)
                Toggle(L("Etiketleri yaz (CPU, RAM…)", "Show labels (CPU, RAM…)"), isOn: $labels)
                    .disabled(style != "line")
            } footer: {
                Footnote(L("İki satırda etiket her zaman üstte durur. Hiçbiri seçili değilse yalnızca simge görünür. Bellek kritikleşince simge her zaman uyarıya döner.",
                           "Two lines always show the label on top. With nothing picked only the icon shows. When memory turns critical the icon always becomes a warning."))
            }
        }
        .formStyle(.grouped)
    }
}

private struct BarToggle: View {
    let item: MenuBarItem
    @AppStorage private var on: Bool

    init(item: MenuBarItem) {
        self.item = item
        _on = AppStorage(wrappedValue: false, item.key)
    }

    var body: some View { Toggle(item.title, isOn: $on) }
}

/// The status item as it will look, refreshed every two seconds.
private struct MenuBarPreview: View {
    let showIcon: Bool
    let stacked: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            let text = MenuBarText.compose(monitor: SettingsWindow.monitor)
            let parts = MenuBarText.parts(monitor: SettingsWindow.monitor)
            let symbol = BarSymbol.current
            HStack(spacing: Theme.Spacing.xs) {
                if stacked {
                    let icon = (showIcon || parts.isEmpty) ? NSImage(systemSymbolName: symbol, accessibilityDescription: nil) : nil
                    Image(nsImage: MenuBarText.image(parts: parts, icon: icon, height: NSStatusBar.system.thickness))
                        .renderingMode(.template)
                } else {
                    if showIcon || text.isEmpty { Image(systemName: symbol) }
                    if !text.isEmpty { Text(verbatim: text).monospacedDigit().lineLimit(1) }
                }
            }
            .font(Theme.body)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.hover, in: Capsule())
            .frame(maxWidth: .infinity)
        }
    }
}

private struct PanelPage: View {
    @AppStorage(Prefs.collapsible) private var collapsible = true
    @AppStorage(Prefs.accordion) private var accordion = false
    @AppStorage(Prefs.memoryAppCount) private var memoryCount = 5
    @AppStorage(Prefs.cpuAppCount) private var cpuCount = 3
    @AppStorage(Prefs.sectionOrder) private var order = ""

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .panel) }
            Section {
                Toggle(L("Bölümler katlanabilsin", "Collapsible sections"), isOn: $collapsible)
                Toggle(L("Akordeon: aynı anda tek bölüm açık", "Accordion: one section open at a time"), isOn: $accordion)
                    .disabled(!collapsible)
            } header: {
                Text(L("Katlama", "Folding"))
            } footer: {
                Footnote(L("Paneldeki bir başlığa tıklayınca o bölüm açılır ya da kapanır. Kapalı bölümün başlığında kısa bir özet görünür.",
                           "Click a heading in the panel to open or close its section. A closed section shows a short summary in its heading."))
            }
            Section {
                let ordered = PanelSection.ordered
                ForEach(ordered) { section in
                    SectionSettingRow(section: section, collapsible: collapsible,
                                      isFirst: section == ordered.first, isLast: section == ordered.last)
                }
            } header: {
                Text(L("Bölümler ve sıraları", "Sections and their order"))
            } footer: {
                HStack(spacing: Theme.Spacing.m) {
                    Button(L("Tümünü aç", "Expand all")) {
                        PanelSection.allCases.forEach { UserDefaults.standard.set(true, forKey: $0.expandedKey) }
                    }
                    .disabled(!collapsible || accordion)
                    Button(L("Tümünü kapat", "Collapse all")) {
                        PanelSection.allCases.forEach { UserDefaults.standard.set(false, forKey: $0.expandedKey) }
                    }
                    .disabled(!collapsible)
                    Spacer()
                    Button(L("Sırayı sıfırla", "Reset order")) { order = "" }
                        .disabled(order.isEmpty)
                }
                .padding(.horizontal, Theme.formInset)
            }
            Section {
                ForEach(ToolKind.allCases) { ToolSettingRow(kind: $0) }
            } header: {
                Text(L("Araçlar", "Tools"))
            } footer: {
                Footnote(L("Kapattığın araçlar paneldeki ızgaradan kalkar.", "Tools you turn off leave the panel's grid."))
            }
            Section(L("Uygulama listesi", "App list")) {
                Stepper(L("Bellekte ilk \(memoryCount)", "Top \(memoryCount) by memory"), value: $memoryCount, in: 1...10)
                Stepper(L("İşlemcide ilk \(cpuCount)", "Top \(cpuCount) by CPU"), value: $cpuCount, in: 1...10)
            }
        }
        .formStyle(.grouped)
        .onChange(of: accordion) {
            // Turning accordion on keeps only the first open section open.
            guard accordion, let first = PanelSection.allCases.first(where: { $0.isExpanded }) else { return }
            first.setExpanded(true)
        }
    }
}

private struct ToolSettingRow: View {
    let kind: ToolKind
    @AppStorage(Prefs.hiddenTools) private var hidden = ""

    var body: some View {
        Toggle(isOn: Binding(get: { !set.contains(kind.rawValue) }, set: { on in
            var list = set
            if on { list.remove(kind.rawValue) } else { list.insert(kind.rawValue) }
            hidden = ToolKind.allCases.map(\.rawValue).filter(list.contains).joined(separator: ",")
        })) {
            Label {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: kind.title)
                    Text(verbatim: kind.help).font(Theme.small).foregroundStyle(Theme.textMuted)
                }
            } icon: {
                Image(systemName: kind.symbol)
            }
        }
    }

    private var set: Set<String> { Set(hidden.split(separator: ",").map(String.init)) }
}

/// "↑ ↓  Simulators   ☑ Open   [on]": its place in the panel, whether it shows, and whether it starts open.
private struct SectionSettingRow: View {
    let section: PanelSection
    let collapsible: Bool
    var isFirst = false
    var isLast = false
    @AppStorage private var shown: Bool
    @AppStorage private var expanded: Bool

    init(section: PanelSection, collapsible: Bool, isFirst: Bool, isLast: Bool) {
        self.section = section
        self.collapsible = collapsible
        self.isFirst = isFirst
        self.isLast = isLast
        _shown = AppStorage(wrappedValue: true, section.showKey)
        _expanded = AppStorage(wrappedValue: true, section.expandedKey)
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.l) {
                Toggle(L("Açık", "Open"), isOn: Binding(get: { expanded }, set: { section.setExpanded($0) }))
                    .toggleStyle(.checkbox)
                    .disabled(!shown || !collapsible)
                Toggle(section.title, isOn: $shown).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                MoveButtons(up: isFirst ? nil : { PanelSection.move(section, by: -1) },
                            down: isLast ? nil : { PanelSection.move(section, by: 1) })
                Image(systemName: section.symbol).foregroundStyle(Theme.textMuted).frame(width: Theme.menuIcon)
                Text(verbatim: section.title)
            }
        }
    }
}

/// Two small arrows that move a row up or down; a missing action greys its arrow out.
private struct MoveButtons: View {
    let up: (() -> Void)?
    let down: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Spacing.xs / 2) {
            Button { up?() } label: { Image(systemName: "chevron.up") }.disabled(up == nil)
            Button { down?() } label: { Image(systemName: "chevron.down") }.disabled(down == nil)
        }
        .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.textMuted))
        .help(L("Sırasını değiştir", "Change its place"))
    }
}

/// Every Hyperliquid market — the main crypto dex and every HIP-3 dex (stocks, indices, commodities) — searchable,
/// busiest first, with live price and 24-hour change. Ticking a market adds it to the panel.
private struct MarketsPage: View {
    @AppStorage(Prefs.watchedMarkets) private var watched = ""
    @State private var query = ""
    @State private var dex = "*"
    private let store = MarketStore.shared

    private var watchedIDs: [String] { watched.split(separator: ",").map(String.init) }

    var body: some View {
        let results = filtered
        Form {
            Section {} header: { PageHeader(page: .markets) }
            Section {
                if watchedIDs.isEmpty {
                    Text(L("Henüz piyasa seçilmedi.", "No markets picked yet.")).foregroundStyle(Theme.textMuted)
                }
                ForEach(watchedIDs, id: \.self) { id in
                    LabeledContent {
                        HStack(spacing: Theme.Spacing.s) {
                            Button { move(id, by: -1) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.borderless).disabled(watchedIDs.first == id)
                            Button { move(id, by: 1) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.borderless).disabled(watchedIDs.last == id)
                            Button { set(id, false) } label: { Image(systemName: "minus.circle.fill") }
                                .buttonStyle(.borderless).foregroundStyle(Theme.danger)
                        }
                    } label: {
                        MarketLabel(id: id, market: store.markets[id], dexTitle: store.markets[id].map { store.dexTitle($0.dex) } ?? "")
                    }
                }
            } header: {
                Text(L("Panelde", "In the panel"))
            }

            PriceAlertsSection(watched: watchedIDs)

            Section {
                TextField(L("Ara: BTC, TSLA, GOLD…", "Search: BTC, TSLA, GOLD…"), text: $query)
                Picker(L("Borsa", "Exchange"), selection: $dex) {
                    Text(L("Hepsi", "All")).tag("*")
                    ForEach(store.dexes.filter { dex in store.markets.values.contains { $0.dex == dex.id } }) { dex in
                        Text(verbatim: dex.title).tag(dex.id)
                    }
                }
            } header: {
                HStack {
                    Text(L("Tüm piyasalar", "All markets"))
                    if store.loadingCatalog { ProgressView().controlSize(.small) }
                    Spacer()
                    Text(verbatim: "\(results.count)").foregroundStyle(Theme.textMuted)
                }
            } footer: {
                Footnote(L("Fiyatlar Hyperliquid'den gelir: ana borsadaki kripto piyasaları ve HIP-3 borsalarındaki hisse, endeks ve emtia piyasaları. Hesap ya da anahtar gerekmez.",
                           "Prices come from Hyperliquid: crypto on the main dex and stocks, indices and commodities on HIP-3 dexes. No account or key needed."))
            }

            Section {
                ForEach(results.prefix(250)) { market in
                    Toggle(isOn: Binding(get: { watchedIDs.contains(market.id) }, set: { set(market.id, $0) })) {
                        MarketLabel(id: market.id, market: market, dexTitle: store.dexTitle(market.dex))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { store.refreshCatalog() }
    }

    private var filtered: [Market] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.markets.values
            .filter { dex == "*" || $0.dex == dex }
            .filter { needle.isEmpty || $0.name.lowercased().contains(needle) || store.dexTitle($0.dex).lowercased().contains(needle) }
            .sorted { $0.volume > $1.volume }
    }

    private func set(_ id: String, _ on: Bool) {
        var list = watchedIDs.filter { $0 != id }
        if on { list.append(id) }
        watched = list.joined(separator: ",")
        store.refreshWatched(maxAge: 0)
    }

    private func move(_ id: String, by offset: Int) {
        var list = watchedIDs
        guard let index = list.firstIndex(of: id), list.indices.contains(index + offset) else { return }
        list.swapAt(index, index + offset)
        watched = list.joined(separator: ",")
    }
}

/// "TSLA  XYZ        382,69  ▲ %1,2"
private struct MarketLabel: View {
    let id: String
    let market: Market?
    let dexTitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(verbatim: market?.name ?? id).font(Theme.bodyStrong)
            if !dexTitle.isEmpty {
                Text(verbatim: dexTitle).font(Theme.small).foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: Theme.Spacing.s)
            if let market {
                Text(verbatim: Format.change(market.change)).font(Theme.small).monospacedDigit()
                    .foregroundStyle((market.change ?? 0) >= 0 ? Palette.green.mark : Theme.warning.mark)
                Text(verbatim: Format.price(market.price)).font(Theme.body).monospacedDigit().foregroundStyle(Theme.text)
            }
        }
    }
}

private struct CurrencyPage: View {
    @AppStorage(Prefs.baseCurrency) private var base = "TRY"
    @AppStorage(Prefs.watchedCurrencies) private var watched = "USD,EUR,GBP"
    private let rates = RateStore.shared

    var body: some View {
        let codes = rates.codes
        Form {
            Section {} header: { PageHeader(page: .currency) }
            Section {
                Picker(L("Ana para birimi", "Main currency"), selection: $base) {
                    ForEach(codes, id: \.self) { Text(verbatim: label(for: $0)).tag($0) }
                }
            } footer: {
                Footnote(L("Kurlar bu para biriminde gösterilir; hızlı hesapta hedef yazılmazsa buna çevrilir.",
                       "Rates are shown in this currency; quick conversions go to it when no target is given."))
            }
            Section(L("Panelde izlenenler", "Watched in the panel")) {
                ForEach(codes.filter { $0 != base }, id: \.self) { code in
                    Toggle(label(for: code), isOn: binding(for: code))
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { rates.refreshIfNeeded() }
    }

    private func label(for code: String) -> String {
        let name = Format.locale.localizedString(forCurrencyCode: code) ?? code
        return "\(code) · \(name)"
    }

    private func binding(for code: String) -> Binding<Bool> {
        Binding {
            watched.split(separator: ",").contains { $0 == code }
        } set: { on in
            var list = watched.split(separator: ",").map(String.init).filter { $0 != code }
            if on { list.append(code) }
            watched = list.joined(separator: ",")
        }
    }
}

private struct AIPage: View {
    @AppStorage("ai.claude") private var claude = false
    @AppStorage("ai.codex") private var codex = false
    @AppStorage("ai.gemini") private var gemini = false
    @AppStorage(Prefs.aiRemaining) private var remaining = true
    private let store = AILimitsStore.shared

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .ai) }
            Section {
                ForEach(AIProvider.allCases) { provider in
                    Toggle(isOn: binding(provider)) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(verbatim: provider.name)
                            Text(verbatim: "\(provider.source) → \(provider.server)").font(Theme.small).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            } footer: {
                Footnote(L("Nabız, resmi CLI'lerin bu Mac'te zaten tuttuğu oturumu okur ve yalnızca o sağlayıcının kendi sunucusuna sorar. Oturum bilgisi saklanmaz, yenilenmez ve başka bir yere gönderilmez. macOS ilk okumada izin isteyebilir.",
                       "Nabız reads the sign-in the official CLIs already keep on this Mac and asks only that provider's own server. The sign-in is never stored, refreshed or sent anywhere else. macOS may ask for permission the first time."))
            }
            Section {
                Picker(L("Göster", "Show"), selection: $remaining) {
                    Text(L("Kalan", "What's left")).tag(true)
                    Text(L("Kullanılan", "What's used")).tag(false)
                }
                .pickerStyle(.segmented)
            } footer: {
                Footnote(L("Örnek: haftalık limitin %94'ü kullanıldıysa \"%6 kaldı\" ya da \"%94\" yazar. Çubuk da aynısını gösterir; kalanı seçersen harcadıkça kısalır.",
                           "Example: with 94% of the weekly limit used it reads \"6% left\" or \"94%\". The bar shows the same; with what's left it shrinks as you use it."))
            }
            Section {
                LabeledContent("Grok") {
                    Text(L("Herkese açık limit verisi yok", "No public limit data")).foregroundStyle(Theme.textMuted)
                }
            } footer: {
                Footnote(L("xAI kullanım limitlerini okuyacak bir yol sunduğunda eklenecek.", "Will be added once xAI offers a way to read usage limits."))
            }
            Section {
                HStack {
                    Button(L("Şimdi yenile", "Refresh now")) { store.refreshIfNeeded(force: true) }
                        .disabled(store.enabled.isEmpty || store.loading)
                    if store.loading { ProgressView().controlSize(.small) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ provider: AIProvider) -> Binding<Bool> {
        switch provider {
        case .claude: $claude
        case .codex: $codex
        case .gemini: $gemini
        }
    }
}

private struct AboutPage: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
            Text(verbatim: "Nabız").font(Theme.title).foregroundStyle(Theme.text)
            Text(verbatim: L("Sürüm", "Version") + " " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"))
                .font(Theme.small).foregroundStyle(Theme.textMuted)
            UpdateRow()
            Text(L("Mac'inin nabzını menü çubuğunda tutar. Açık kaynak, MIT lisansı.",
                   "Keeps your Mac's pulse in the menu bar. Open source, MIT license."))
                .font(Theme.body).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            Text(L("Ölçümler Mac'inde yapılır. Döviz kurları Avrupa Merkez Bankası'ndan (frankfurter.dev) gelir; AI limitleri yalnızca açtığın sağlayıcıların kendi sunucularından okunur.",
                   "Everything is measured on your Mac. Rates come from the European Central Bank (frankfurter.dev); AI limits are read only from the providers you turn on, from their own servers."))
                .font(Theme.small).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center)
            HStack(spacing: Theme.Spacing.l) {
                Button(L("Neler yapabilir?", "What can it do?")) { HelpWindow.show() }
                if let crash = CrashReporter.latest {
                    Button(L("Son çökmeyi bildir (\(crash.date.formatted(date: .abbreviated, time: .omitted)))",
                             "Report the last crash (\(crash.date.formatted(date: .abbreviated, time: .omitted)))")) {
                        if let url = CrashReporter.reportURL(crash.url) { NSWorkspace.shared.open(url) }
                    }
                }
            }
            .font(Theme.small)
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A form footer, left-aligned like System Settings.
private struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: text).font(Theme.small).foregroundStyle(Theme.textMuted)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.formInset)
    }
}

/// The page's title block: its icon tile, title and one line on what it is for. Lined up with the form's cards.
private struct PageHeader: View {
    let page: SettingsPage

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: page.symbol)
                .font(Theme.title)
                .foregroundStyle(.white)
                .frame(width: Theme.settingsHeaderIcon, height: Theme.settingsHeaderIcon)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(verbatim: page.title).font(Theme.title).foregroundStyle(Theme.text)
                Text(verbatim: page.subtitle).font(Theme.small).foregroundStyle(Theme.textMuted)
            }
            Spacer()
        }
        .padding(.bottom, Theme.Spacing.s)
        .textCase(nil)
    }
}

/// Price alerts: the list, and a row to add one for a watched market (prefilled with its current price).
/// Price alerts: a composer that reads like a sentence ("BTC reaches 62,000"), quick ±% targets from the current
/// price, and a list showing how far each line still is.
private struct PriceAlertsSection: View {
    let watched: [String]
    @State private var market = ""
    @State private var price: Double?
    @State private var repeats = false
    private let alerts = PriceAlerts.shared
    private let store = MarketStore.shared

    var body: some View {
        Section {
            let sorted = alerts.alerts.sorted { a, b in
                if a.armed != b.armed { return a.armed }
                let da = store.markets[a.market].map { a.distance(from: $0.price) } ?? 1
                let db = store.markets[b.market].map { b.distance(from: $0.price) } ?? 1
                return da < db
            }
            ForEach(sorted) { AlertRow(alert: $0) }
            if !watched.isEmpty { composer }
        } header: {
            Text(L("Fiyat alarmları", "Price alerts"))
        } footer: {
            Footnote(L("Fiyat çizgiye gelince bir kez bildirim gelir. Tekrarlayan alarm, fiyat çizgiden %0,5 geri dönünce kendiliğinden yeniden kurulur. Alarm varken fiyatlar arka planda 30 saniyede bir okunur.",
                       "When the price reaches the line you get one notification. A repeating alert arms itself again once the price moves 0.5% back. While an alert is set, prices are read every 30 seconds in the background."))
        }
        .onAppear { pick(watched.first ?? "") }
        .onChange(of: market) { pick(market) }
    }

    private var current: Double? { store.markets[market]?.price }

    /// Up or down follows from the target: above today's price means "rises to", below means "falls to".
    private var above: Bool { (price ?? 0) >= (current ?? 0) }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                Picker(L("Piyasa", "Market"), selection: $market) {
                    ForEach(watched, id: \.self) { Text(verbatim: store.markets[$0]?.name ?? $0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                if let current {
                    Text(verbatim: Format.price(current)).font(Theme.bodyStrong).monospacedDigit()
                    if let change = store.markets[market]?.change {
                        Text(verbatim: Format.change(change)).font(Theme.small).monospacedDigit()
                            .foregroundStyle(change >= 0 ? Palette.green.mark : Theme.warning.mark)
                    }
                }
                Spacer()
            }
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: above ? "arrow.up.right" : "arrow.down.right")
                    .foregroundStyle(above ? Palette.green.mark : Theme.warning.mark)
                    .frame(width: Theme.menuIcon)
                Text(above ? L("Şu fiyata çıkınca:", "When it rises to:") : L("Şu fiyata düşünce:", "When it falls to:"))
                    .foregroundStyle(Theme.textMuted)
                TextField(L("Fiyat", "Price"), value: $price, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 120)
                if let current, let price, current > 0 {
                    Text(verbatim: (price >= current ? "+" : "−") + Format.percent(abs(price / current - 1)))
                        .font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Toggle(L("Tekrarla", "Repeat"), isOn: $repeats).toggleStyle(.checkbox)
                Button(L("Alarm kur", "Set alert")) { add() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!valid)
            }
            HStack(spacing: Theme.Spacing.xs) {
                ForEach([-10, -5, -2, 2, 5, 10], id: \.self) { step in
                    Button { set(percent: step) } label: {
                        Text(verbatim: (step > 0 ? "+" : "−") + Format.percent(Double(abs(step)) / 100))
                            .font(Theme.small).monospacedDigit()
                            .padding(.horizontal, Theme.Spacing.s)
                            .padding(.vertical, Theme.Spacing.xs / 2)
                            .background(Theme.track, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(current == nil)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var valid: Bool {
        guard let price, price > 0, !market.isEmpty else { return false }
        return price != current
    }

    private func add() {
        guard valid, let price else { return }
        alerts.add(market: market, above: above, price: price, repeats: repeats)
        Monitor.panelActions.flash(L("Alarm kuruldu", "Alert set"))
        set(percent: 5)
    }

    private func set(percent: Int) {
        guard let current else { return }
        price = Self.rounded(current * (1 + Double(percent) / 100))
    }

    /// Keeps three significant digits or so: 60,494 → 63,500, 1.2345 → 1.30.
    static func rounded(_ value: Double) -> Double {
        guard value > 0 else { return value }
        let step = pow(10, floor(log10(value)) - 2)
        return (value / step).rounded() * step
    }

    /// Selecting a market starts at +5% from its current price.
    private func pick(_ id: String) {
        if market.isEmpty { market = id }
        set(percent: 5)
    }
}

private struct AlertRow: View {
    let alert: PriceAlert
    private let alerts = PriceAlerts.shared
    private let store = MarketStore.shared

    var body: some View {
        let now = store.markets[alert.market]?.price
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: alert.above ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                .foregroundStyle(alert.armed ? (alert.above ? Palette.green.mark : Theme.warning.mark) : Theme.textMuted)
            Text(verbatim: store.markets[alert.market]?.name ?? alert.market).font(Theme.bodyStrong)
            Text(verbatim: Format.price(alert.price)).monospacedDigit()
            if alert.armed, let now {
                Text(L("\(Format.percent(alert.distance(from: now))) uzakta", "\(Format.percent(alert.distance(from: now))) away"))
                    .font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted)
            } else if let fired = alert.firedAt {
                Text(L("tetiklendi \(fired.formatted(.relative(presentation: .named).locale(Format.locale)))",
                       "fired \(fired.formatted(.relative(presentation: .named).locale(Format.locale)))"))
                    .font(Theme.small).foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Button { alerts.setRepeats(alert, alert.repeats != true) } label: {
                Image(systemName: "repeat").foregroundStyle(alert.repeats == true ? Theme.accent : Theme.textMuted)
            }
            .buttonStyle(.borderless)
            .help(alert.repeats == true ? L("Tekrarlıyor", "Repeats") : L("Tekrarla", "Repeat"))
            if !alert.armed {
                Button(L("Yeniden kur", "Re-arm")) { alerts.rearm(alert) }.buttonStyle(.borderless)
            }
            Button { alerts.remove(alert) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).foregroundStyle(Theme.textMuted)
                .help(L("Sil", "Delete"))
        }
        .opacity(alert.armed ? 1 : 0.65)
    }
}

private struct UpdateRow: View {
    private let updater = Updater.shared

    var body: some View {
        if let release = updater.available {
            Button(updater.installing ? L("Güncelleniyor…", "Updating…") : L("\(release.version) sürümüne güncelle", "Update to \(release.version)")) {
                updater.install()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(updater.installing)
        } else {
            Button(L("Güncellemeleri denetle", "Check for updates")) { updater.check(force: true) }
        }
        if let error = updater.lastError {
            Text(verbatim: error).font(Theme.small).foregroundStyle(Theme.warning.mark)
        }
    }
}

private struct AppearancePage: View {
    @AppStorage(Prefs.accentColor) private var accent = "green"
    @AppStorage(Prefs.customAccent) private var customHex = "#1DB954"
    @AppStorage(Prefs.panelStyle) private var style = "material"
    @AppStorage(Prefs.panelWidth) private var width = 320
    @AppStorage(Prefs.textSize) private var textSize = "normal"
    @AppStorage(Prefs.fontDesign) private var fontDesign = "standard"
    @AppStorage(Prefs.density) private var density = "normal"
    @AppStorage(Prefs.meterStyle) private var meterStyle = "thin"
    @AppStorage(Prefs.appearanceMode) private var mode = "system"
    @AppStorage(Prefs.barColors) private var barColors = false

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .appearance) }
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(Theme.settingsIcon + Theme.Spacing.s), spacing: Theme.Spacing.s),
                                         count: 9), alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(AccentChoice.swatches) { Swatch(choice: $0, selected: accent == $0.rawValue) { accent = $0.rawValue } }
                }
                .padding(.vertical, Theme.Spacing.xs)
                LabeledContent(L("Sistemin vurgu rengi", "System accent colour")) {
                    Swatch(choice: .system, selected: accent == AccentChoice.system.rawValue) { accent = $0.rawValue }
                }
                LabeledContent(L("Kendi rengin", "Your own colour")) {
                    HStack(spacing: Theme.Spacing.m) {
                        if accent == AccentChoice.custom.rawValue {
                            Text(verbatim: customHex.uppercased()).font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted)
                        }
                        ColorPicker("", selection: customBinding, supportsOpacity: false).labelsHidden()
                    }
                }
            } header: {
                Text(L("Vurgu rengi", "Accent colour"))
            } footer: {
                Footnote(L("Göstergeler, düğmeler, açık araçlar, başlatıcı ve grafikler bu rengi alır. Turuncu ve kırmızı uyarılar için ayrıldı; çok açık bir renk seçersen yazılar zor okunabilir.",
                           "Meters, buttons, active tools, the launcher and charts take this colour. Orange and red are kept for warnings; a very light colour can make text hard to read."))
            }
            Section(L("Tema", "Theme")) {
                Picker(L("Görünüm", "Appearance"), selection: $mode) {
                    Text(L("Sistem", "System")).tag("system")
                    Text(L("Açık", "Light")).tag("light")
                    Text(L("Koyu", "Dark")).tag("dark")
                }
                .pickerStyle(.segmented)
                Picker(L("Arka plan", "Background"), selection: $style) {
                    Text(L("Buzlu cam", "Frosted")).tag("material")
                    Text(L("Opak", "Opaque")).tag("opaque")
                }
                .pickerStyle(.segmented)
            }
            Section(L("Yazı", "Text")) {
                Picker(L("Yazı tipi", "Typeface"), selection: $fontDesign) {
                    Text(L("Standart", "Standard")).tag("standard")
                    Text(L("Yuvarlak", "Rounded")).font(.system(.body, design: .rounded)).tag("rounded")
                    Text(L("Eşit aralıklı", "Monospaced")).font(.system(.body, design: .monospaced)).tag("mono")
                }
                .pickerStyle(.segmented)
                Picker(L("Yazı boyutu", "Text size"), selection: $textSize) {
                    Text(L("Normal", "Normal")).tag("normal")
                    Text(L("Büyük", "Large")).tag("large")
                }
                .pickerStyle(.segmented)
            }
            Section(L("Panel", "Panel")) {
                Picker(L("Genişlik", "Width"), selection: $width) {
                    Text(L("Dar", "Narrow")).tag(300)
                    Text(L("Normal", "Normal")).tag(320)
                    Text(L("Geniş", "Wide")).tag(360)
                }
                .pickerStyle(.segmented)
                Picker(L("Satırlar", "Rows"), selection: $density) {
                    Text(L("Sıkı", "Compact")).tag("compact")
                    Text(L("Normal", "Normal")).tag("normal")
                    Text(L("Ferah", "Roomy")).tag("roomy")
                }
                .pickerStyle(.segmented)
                Picker(L("Çubuklar", "Bars"), selection: $meterStyle) {
                    Text(L("İnce", "Thin")).tag("thin")
                    Text(L("Kalın", "Thick")).tag("thick")
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle(L("Değerleri renklendir", "Colour the values"), isOn: $barColors)
            } header: {
                Text(L("Menü çubuğu", "Menu bar"))
            } footer: {
                Footnote(L("Dikkat isteyen değer turuncu ya da kırmızı olur (yoğun CPU, sıkışık bellek, azalan pil, biten AI limiti); piyasalar yükselişte yeşil, düşüşte kırmızı. Her şey yolundaysa menü çubuğu sade kalır. Simge biçimi Menü çubuğu sayfasında.",
                           "A value that needs attention turns orange or red (busy CPU, tight memory, low battery, an AI limit running out); markets go green when up and red when down. When all is well the menu bar stays plain. The icon style is on the Menu Bar page."))
            }
            Section {
                Button(L("Görünümü sıfırla", "Reset appearance")) {
                    for key in [Prefs.accentColor, Prefs.customAccent, Prefs.panelStyle, Prefs.panelWidth, Prefs.textSize, Prefs.fontDesign,
                                Prefs.density, Prefs.meterStyle, Prefs.appearanceMode, Prefs.barColors] {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// The colour well: picking a colour also makes it the accent.
    private var customBinding: Binding<Color> {
        Binding(get: { Color(hex: customHex) ?? Palette.green.fill }, set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            customHex = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                               Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
            accent = AccentChoice.custom.rawValue
        })
    }
}

/// One accent colour: a dot, ringed and ticked when chosen.
private struct Swatch: View {
    let choice: AccentChoice
    let selected: Bool
    let pick: (AccentChoice) -> Void

    var body: some View {
        Button { pick(choice) } label: {
            Circle().fill(choice.color)
                .frame(width: Theme.settingsIcon, height: Theme.settingsIcon)
                .overlay {
                    if selected { Image(systemName: "checkmark").font(Theme.smallStrong).foregroundStyle(.white) }
                }
                .padding(Theme.Spacing.xs / 2)
                .overlay(Circle().strokeBorder(selected ? choice.color : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(choice.title)
        .accessibilityLabel(choice.title)
    }
}

private struct SchedulesPage: View {
    private let scheduler = Scheduler.shared

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .schedules) }
            Section {
                if scheduler.tasks.isEmpty {
                    Text(L("Henüz görev yok. Aşağıdan hazır bir tane ekle ya da kendin oluştur.",
                           "No tasks yet. Add a ready-made one below, or make your own."))
                        .foregroundStyle(Theme.textMuted)
                }
                ForEach(scheduler.tasks) { TaskRow(task: $0) }
            } header: {
                Text(L("Görevler", "Tasks"))
            } footer: {
                Footnote(L("Görev seçtiğin saatte kendiliğinden çalışır ve kısa bir bildirim gönderir. Mac o saatte uykudaysa 6 saat içinde uyanınca telafi edilir; daha geç olursa bir sonraki güne kalır.",
                           "A task runs on its own at the time you set and posts a short notification. If the Mac was asleep, it catches up within 6 hours of waking; later than that it waits for its next day."))
            }
            Section(L("Ekle", "Add")) {
                Menu {
                    ForEach(ScheduledAction.allCases) { action in
                        Button { scheduler.add(ScheduledTask(action: action, hour: 9, minute: 0)) } label: {
                            Label(action.title, systemImage: action.symbol)
                        }
                    }
                } label: {
                    Label(L("Yeni görev", "New task"), systemImage: "plus")
                }
                ForEach(Scheduler.presets.filter { preset in !scheduler.tasks.contains { $0.action == preset.action } }, id: \.action) { preset in
                    Button { scheduler.add(preset) } label: {
                        HStack {
                            Image(systemName: preset.action.symbol).frame(width: Theme.menuIcon)
                            Text(verbatim: preset.action.title)
                            Spacer()
                            Text(verbatim: "\(WeekdayChips.summary(preset.weekdays)) \(preset.timeText)").foregroundStyle(Theme.textMuted)
                            Image(systemName: "plus.circle").foregroundStyle(Theme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// One task: on/off, what it does, when, which days, and a menu to run it now or delete it.
private struct TaskRow: View {
    let task: ScheduledTask
    private let scheduler = Scheduler.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Toggle("", isOn: binding(\.enabled)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                Image(systemName: task.action.symbol).foregroundStyle(task.enabled ? Theme.accent : Theme.textMuted)
                    .frame(width: Theme.menuIcon)
                Text(verbatim: task.action.title).font(Theme.bodyStrong)
                Spacer()
                DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                Menu {
                    Button(L("Şimdi çalıştır", "Run now")) { scheduler.runNow(task) }
                    Divider()
                    Button(L("Sil", "Delete"), role: .destructive) { scheduler.remove(task) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            if task.action == .reminder {
                TextField(L("Hatırlatma metni", "Reminder text"), text: binding(\.note))
            }
            WeekdayChips(days: binding(\.weekdays)).fixedSize()
            HStack {
                if task.enabled, let next = task.next() {
                    Text(L("Sıradaki: ", "Next: ") + next.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Format.locale)))
                        .font(Theme.small).foregroundStyle(Theme.textMuted)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .opacity(task.enabled ? 1 : 0.6)
    }

    private func binding<Value>(_ path: WritableKeyPath<ScheduledTask, Value>) -> Binding<Value> {
        Binding(get: { task[keyPath: path] }, set: { value in
            var copy = task
            copy[keyPath: path] = value
            scheduler.update(copy)
        })
    }

    private var timeBinding: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: task.hour, minute: task.minute, second: 0, of: Date()) ?? Date()
        }, set: { date in
            var copy = task
            copy.hour = Calendar.current.component(.hour, from: date)
            copy.minute = Calendar.current.component(.minute, from: date)
            // Changing the time starts it afresh from now.
            copy.lastRun = Date()
            scheduler.update(copy)
        })
    }
}

/// Seven toggles, Monday first: "Pzt Sal Çar Per Cum Cmt Paz".
private struct WeekdayChips: View {
    @Binding var days: Set<Int>
    private static let order = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Self.order, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on { if days.count > 1 { days.remove(day) } } else { days.insert(day) }
                } label: {
                    Text(verbatim: Self.name(day)).font(Theme.small)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(on ? .white : Theme.textMuted)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, Theme.Spacing.xs / 2)
                        .background(on ? Theme.accent : Theme.hover, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    static func name(_ day: Int) -> String {
        let symbols = Format.locale.identifier.hasPrefix("tr")
            ? ["Paz", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt"] : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return symbols[(day - 1) % 7]
    }

    /// "Her gün", "Hafta içi", or the day names.
    static func summary(_ days: Set<Int>) -> String {
        if days.count == 7 { return L("Her gün", "Every day") }
        if days == Set(2...6) { return L("Hafta içi", "Weekdays") }
        if days == [1, 7] { return L("Hafta sonu", "Weekends") }
        return order.filter(days.contains).map(name).joined(separator: " ")
    }
}

// MARK: - Launcher, clipboard, snippets, windows

private struct LauncherPage: View {
    @AppStorage(Prefs.hotkey) private var hotkey = true
    @AppStorage(Prefs.launcherApps) private var apps = true
    @AppStorage(Prefs.launcherClipboard) private var clips = true
    private let store = LauncherStore.shared

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .launcher) }
            Section {
                Toggle(L("⌃⌥Boşluk ile aç", "Open with ⌃⌥Space"), isOn: $hotkey)
                Toggle(L("Uygulamaları ara", "Search apps"), isOn: $apps)
                Toggle(L("Pano öğelerini göster", "Show clipboard items"), isOn: $clips)
                Button(L("Başlatıcıyı aç", "Open the launcher")) { LauncherPanel.shared.show() }
            } footer: {
                Footnote(L("Yaz: uygulama adı, komut (kilitle, uyut, sol yarı…), hesap (12*4, 100 usd, 5 km mi), \"25 dk\" zamanlayıcı ya da \"g kelime\" ile web araması. ↑↓ seç, ↩ çalıştır, ⌘↩ ikinci işlem, esc kapat.",
                           "Type an app name, a command (lock, sleep, left half…), maths (12*4, 100 usd, 5 km mi), \"25 min\" for a timer or \"g words\" to search the web. ↑↓ to pick, ↩ to run, ⌘↩ for the second action, esc to close."))
            }
            Section {
                ForEach(store.quicklinks) { QuicklinkRow(link: $0) }
                HStack {
                    Button {
                        store.save(quicklink: Quicklink(keyword: "", name: L("Yeni bağlantı", "New link"), url: "https://"))
                    } label: { Label(L("Bağlantı ekle", "Add a link"), systemImage: "plus") }
                    Spacer()
                    Button(L("Varsayılanlar", "Defaults")) {
                        store.quicklinks.forEach(store.remove(quicklink:))
                        LauncherStore.defaultQuicklinks.forEach(store.save(quicklink:))
                    }
                }
            } header: {
                Text(L("Hızlı bağlantılar", "Quicklinks"))
            } footer: {
                Footnote(L("Adreste {query} yazan yere, kısaltmadan sonra yazdığın gelir: \"gh nabiz\" → GitHub'da nabiz araması. İlk bağlantı, başka sonuç olmayınca web araması için kullanılır.",
                           "{query} in the address is replaced by what you type after the keyword: \"gh nabiz\" searches GitHub for nabiz. The first link is used for web search when nothing else matches."))
            }
            ExtensionsSection()
            DownloadSection()
        }
        .formStyle(.grouped)
    }
}

/// Files, Shortcuts and scripts in the launcher.
private struct ExtensionsSection: View {
    @AppStorage(Prefs.launcherFiles) private var files = true
    @AppStorage(Prefs.launcherShortcuts) private var shortcuts = true
    private let extensions = Extensions.shared

    var body: some View {
        Section {
            Toggle(L("Aramada dosyaları da göster", "Show files in searches"), isOn: $files)
            Toggle(L("Kestirmeler uygulamasındaki kestirmeleri göster", "Show your Shortcuts"), isOn: Binding(get: { shortcuts }, set: { on in
                shortcuts = on
                extensions.refreshIfNeeded(force: true)
            }))
            LabeledContent(L("Betikler", "Scripts")) {
                HStack(spacing: Theme.Spacing.m) {
                    Text(L("\(extensions.scripts.count) betik", "\(extensions.scripts.count) scripts")).foregroundStyle(Theme.textMuted)
                    Button(L("Klasörü aç", "Open folder")) { NSWorkspace.shared.open(Extensions.scriptsFolder) }
                    Button(L("Örnek ekle", "Add example")) { extensions.createSample() }
                }
            }
        } header: {
            Text(L("Dosyalar, kestirmeler ve betikler", "Files, Shortcuts and scripts"))
        } footer: {
            Footnote(L("\"/\" ile başlarsan yalnızca dosyalar aranır (Spotlight dizini). Betik klasörüne koyduğun her .sh, .py ya da çalıştırılabilir dosya başlatıcıda bir komut olur; yazdığı çıktı panoya kopyalanır. Başlık için ilk satırlara \"# @nabiz.title Adı\" yaz.",
                       "Start with \"/\" to search only files (Spotlight's index). Every .sh, .py or executable in the scripts folder becomes a launcher command; whatever it prints is copied. Add \"# @nabiz.title Name\" near the top for its title."))
        }
        .onAppear { extensions.refreshIfNeeded(force: true) }
    }
}

/// Video downloads: quality, folder, and whether yt-dlp and ffmpeg are there.
private struct DownloadSection: View {
    @AppStorage(Prefs.downloadQuality) private var quality = "best"
    @AppStorage(Prefs.downloadFolder) private var folder = ""
    private let downloader = Downloader.shared

    var body: some View {
        Section {
            Picker(L("Video kalitesi", "Video quality"), selection: $quality) {
                Text(L("En iyi", "Best")).tag("best")
                Text(verbatim: "1080p").tag("1080")
                Text(verbatim: "720p").tag("720")
            }
            LabeledContent(L("Kayıt yeri", "Save to")) {
                HStack(spacing: Theme.Spacing.m) {
                    Text(verbatim: downloader.folder.lastPathComponent).foregroundStyle(Theme.textMuted)
                    Button(L("Değiştir…", "Change…")) {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.directoryURL = downloader.folder
                        NSApp.activate()
                        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
                    }
                }
            }
            LabeledContent("yt-dlp") {
                if downloader.ytdlp != nil {
                    Label(L("Kurulu", "Installed"), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.green.mark)
                } else {
                    Button(downloader.installing ? L("Kuruluyor…", "Installing…") : L("Kur…", "Install…")) { downloader.install() }
                        .disabled(downloader.installing)
                }
            }
            LabeledContent("ffmpeg") {
                Text(downloader.ffmpeg != nil ? L("Kurulu: en iyi kalite ve MP3", "Installed: best quality and MP3")
                                              : L("Yok: en fazla 720p, ses M4A", "Missing: up to 720p, sound as M4A"))
                    .foregroundStyle(Theme.textMuted)
            }
        } header: {
            Text(L("Video indirme", "Video downloads"))
        } footer: {
            Footnote(L("Bir YouTube, X, Instagram, TikTok, Vimeo… bağlantısını başlatıcıya yapıştır ya da kopyalayıp Video indir aracına bas. yt-dlp ile indirilir. Yalnızca indirme hakkın olan içerik için kullan.",
                       "Paste a YouTube, X, Instagram, TikTok, Vimeo… link into the launcher, or copy it and tap the Download tool. yt-dlp does the downloading. Use it only for content you have the right to download."))
        }
    }
}

private struct FocusPage: View {
    @AppStorage(Prefs.pomodoroWork) private var work = 25
    @AppStorage(Prefs.pomodoroShort) private var short = 5
    @AppStorage(Prefs.pomodoroLong) private var long = 15
    @AppStorage(Prefs.pomodoroLongEvery) private var every = 4
    @AppStorage(Prefs.pomodoroAuto) private var auto = true
    @AppStorage(Prefs.pomodoroFocus) private var withFocus = true
    @AppStorage(Prefs.focusHideOthers) private var hideOthers = false
    @AppStorage(Prefs.focusHideDesktop) private var hideDesktop = false
    @AppStorage(Prefs.focusBlocked) private var blocked = ""
    @AppStorage(Prefs.focusShortcutOn) private var shortcutOn = ""
    @AppStorage(Prefs.focusShortcutOff) private var shortcutOff = ""
    private let pomodoro = Pomodoro.shared

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .focus) }
            Section {
                Stepper(L("Odak: \(work) dk", "Focus: \(work) min"), value: $work, in: 5...120, step: 5)
                Stepper(L("Kısa mola: \(short) dk", "Short break: \(short) min"), value: $short, in: 1...30)
                Stepper(L("Uzun mola: \(long) dk", "Long break: \(long) min"), value: $long, in: 5...60, step: 5)
                Stepper(L("Uzun mola her \(every) blokta", "Long break every \(every) blocks"), value: $every, in: 2...8)
                Toggle(L("Sıradaki blok kendiliğinden başlasın", "Start the next block by itself"), isOn: $auto)
                Toggle(L("Odak bloklarında odak modunu aç", "Turn on focus mode during focus blocks"), isOn: $withFocus)
                HStack {
                    Button(pomodoro.isActive ? (pomodoro.isRunning ? L("Duraklat", "Pause") : L("Devam et", "Resume")) : L("Başlat", "Start")) {
                        pomodoro.toggle()
                    }
                    if pomodoro.isActive { Button(L("Bitir", "Stop")) { pomodoro.stop() } }
                    Spacer()
                    Text(L("Bugün \(pomodoro.today.count) blok · \(pomodoro.today.minutes) dk", "Today \(pomodoro.today.count) blocks · \(pomodoro.today.minutes) min"))
                        .foregroundStyle(Theme.textMuted)
                }
            } header: {
                Text("Pomodoro")
            } footer: {
                Footnote(L("Kalan süre menü çubuğunda görünür; her geçişte ses ve bildirim gelir. Başlatıcıda \"pomodoro\" yaz ya da Araçlar'daki Pomodoro'ya bas.",
                           "The time left shows in the menu bar; each change plays a sound and posts a notification. Type \"pomodoro\" in the launcher, or tap Pomodoro in Tools."))
            }
            Section {
                // Only apps on this Mac; the rest of the list waits in case they're installed later.
                ForEach(blockedList.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }, id: \.self) { bundle in
                    HStack {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                            Image(nsImage: AppIndex.shared.icon(url.path)).resizable().frame(width: Theme.menuIcon, height: Theme.menuIcon)
                            Text(verbatim: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                        }
                        Spacer()
                        Button { setBlocked(blockedList.filter { $0 != bundle }) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(TextButtonStyle(color: Theme.textMuted))
                    }
                }
                HStack {
                    Button { addBlocked() } label: { Label(L("Uygulama ekle…", "Add an app…"), systemImage: "plus") }
                    Spacer()
                    Button(L("Varsayılanlar", "Defaults")) { blocked = "" }.disabled(blocked.isEmpty)
                }
                Toggle(L("Başlarken diğer uygulamaları da gizle", "Also hide other apps when it starts"), isOn: $hideOthers)
                Toggle(L("Masaüstü simgelerini gizle", "Hide desktop icons"), isOn: $hideDesktop)
            } header: {
                Text(L("Odak modunda gizlenenler", "Hidden during focus"))
            } footer: {
                Footnote(L("Bu uygulamalar odak boyunca arka planda bekler; öne gelirlerse yeniden gizlenir. Hiçbiri kapatılmaz, mesajların kaybolmaz. Varsayılan liste Slack, Discord, Telegram, WhatsApp, Mesajlar, Messenger, Teams ve Mail'dir; kurulu olanlar görünür.",
                           "These apps wait in the background during focus; if they come forward they're hidden again. Nothing is quit, no messages are lost. The default list is Slack, Discord, Telegram, WhatsApp, Messages, Messenger, Teams and Mail; the installed ones show."))
            }
            Section {
                TextField(L("Açarken çalışacak kestirme", "Shortcut to run when it starts"), text: $shortcutOn, prompt: Text(verbatim: "Odak Aç"))
                TextField(L("Kapatırken çalışacak kestirme", "Shortcut to run when it ends"), text: $shortcutOff, prompt: Text(verbatim: "Odak Kapat"))
            } header: {
                Text(L("macOS Odak (isteğe bağlı)", "macOS Focus (optional)"))
            } footer: {
                Footnote(L("macOS'un Rahatsız Etme / Odak modunu açmak için Kestirmeler'de \"Odak Ayarla\" eylemiyle iki kestirme yap ve adlarını buraya yaz.",
                           "To switch macOS Do Not Disturb / Focus too, make two shortcuts with the \"Set Focus\" action in Shortcuts and enter their names here."))
            }
        }
        .formStyle(.grouped)
    }

    private var blockedList: [String] {
        blocked.isEmpty ? FocusMode.defaultBlocked : blocked.split(separator: ",").map(String.init)
    }

    private func setBlocked(_ list: [String]) { blocked = list.joined(separator: ",") }

    private func addBlocked() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        let bundles = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        setBlocked(Array(Set(blockedList + bundles)).sorted())
    }
}

private struct QuicklinkRow: View {
    let link: Quicklink
    private let store = LauncherStore.shared

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            TextField(L("Kısaltma", "Keyword"), text: binding(\.keyword)).frame(width: 64)
            TextField(L("Ad", "Name"), text: binding(\.name)).frame(width: 110)
            TextField("https://…{query}", text: binding(\.url))
            Button { store.remove(quicklink: link) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(TextButtonStyle(color: Theme.textMuted))
                .help(L("Sil", "Delete"))
        }
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
    }

    private func binding(_ path: WritableKeyPath<Quicklink, String>) -> Binding<String> {
        Binding(get: { link[keyPath: path] }, set: { value in
            var copy = link
            copy[keyPath: path] = value
            store.save(quicklink: copy)
        })
    }
}

private struct ClipboardPage: View {
    @AppStorage(Prefs.clipboardEnabled) private var enabled = true
    @AppStorage(Prefs.clipboardHotkey) private var hotkey = true
    @AppStorage(Prefs.clipboardSave) private var save = true
    @AppStorage(Prefs.clipboardLimit) private var limit = 200
    @AppStorage(Prefs.clipboardDays) private var days = 30
    @AppStorage(Prefs.clipboardExcluded) private var excluded = ""
    @AppStorage(Prefs.autoPaste) private var autoPaste = true
    private let history = ClipboardHistory.shared

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .clipboard) }
            Section {
                Toggle(L("Pano geçmişini tut", "Keep clipboard history"), isOn: $enabled)
                Toggle(L("⌃⌥V ile aç", "Open with ⌃⌥V"), isOn: $hotkey).disabled(!enabled)
                Toggle(L("Yeniden başlatınca da hatırla", "Remember after a restart"), isOn: Binding(get: { save }, set: { on in
                    save = on
                    history.save()
                }))
                .disabled(!enabled)
                Picker(L("En fazla", "Keep up to"), selection: $limit) {
                    ForEach([50, 100, 200, 500, 1000], id: \.self) { Text(L("\($0) öğe", "\($0) items")).tag($0) }
                }
                .disabled(!enabled)
                Picker(L("Silinme süresi", "Forget after"), selection: $days) {
                    Text(L("1 gün", "1 day")).tag(1)
                    Text(L("7 gün", "7 days")).tag(7)
                    Text(L("30 gün", "30 days")).tag(30)
                    Text(L("90 gün", "90 days")).tag(90)
                    Text(L("Hiç", "Never")).tag(0)
                }
                .disabled(!enabled)
            } footer: {
                Footnote(L("Metin, bağlantı, renk kodu, dosya ve 3 MB'a kadar görseller tutulur; sabitlenenler hiç silinmez. Şifre yöneticilerinin gizli işaretlediği kopyalar ve aşağıdaki uygulamalardan kopyalananlar hiç kaydedilmez. Her şey yalnızca bu Mac'te kalır.",
                           "Text, links, colour codes, files and images up to 3 MB are kept; pinned items are never removed. Copies password managers mark as secret, and anything copied in the apps below, are never saved. Everything stays on this Mac."))
            }
            Section {
                Toggle(L("↩ ile yapıştır", "Paste with ↩"), isOn: $autoPaste)
                AccessibilityRow()
            } header: {
                Text(L("Yapıştırma", "Pasting"))
            } footer: {
                Footnote(L("Seçtiğini, imlecin olduğu uygulamaya doğrudan yapıştırır. Bunun için macOS'in Erişilebilirlik izni gerekir; izin yoksa yalnızca kopyalanır.",
                           "Pastes what you pick straight into the app with the cursor. macOS needs Accessibility permission for this; without it, the item is only copied."))
            }
            Section {
                ForEach(customExcluded, id: \.self) { bundle in
                    HStack {
                        Text(verbatim: appName(bundle))
                        Spacer()
                        Button { setExcluded(customExcluded.filter { $0 != bundle }) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(TextButtonStyle(color: Theme.textMuted))
                    }
                }
                Button { addExcluded() } label: { Label(L("Uygulama ekle…", "Add an app…"), systemImage: "plus") }
            } header: {
                Text(L("Kaydedilmeyen uygulamalar", "Apps never recorded"))
            } footer: {
                Footnote(L("Her zaman hariç: 1Password, Bitwarden, LastPass, Dashlane, KeePassXC, Anahtar Zinciri ve Parolalar.",
                           "Always left out: 1Password, Bitwarden, LastPass, Dashlane, KeePassXC, Keychain Access and Passwords."))
            }
            Section {
                Button(L("Geçmişi temizle (\(history.items.filter { !$0.pinned }.count))…", "Clear history (\(history.items.filter { !$0.pinned }.count))…"),
                       role: .destructive) { clear() }
                    .disabled(history.items.allSatisfy(\.pinned))
            }
        }
        .formStyle(.grouped)
    }

    private var customExcluded: [String] { excluded.split(separator: ",").map(String.init) }

    private func setExcluded(_ list: [String]) { excluded = list.joined(separator: ",") }

    private func appName(_ bundle: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundle
    }

    private func addExcluded() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        let bundles = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        setExcluded(Array(Set(customExcluded + bundles)).sorted())
    }

    private func clear() {
        let alert = NSAlert()
        alert.messageText = L("Pano geçmişi temizlensin mi?", "Clear the clipboard history?")
        alert.informativeText = L("Sabitlenenler dışındaki her şey silinir. Bu geri alınamaz.", "Everything except pinned items is deleted. This can't be undone.")
        alert.addButton(withTitle: L("Temizle", "Clear"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        history.clear()
    }
}

/// Whether macOS lets Nabız paste and move windows, with a button to ask. Checked every two seconds while shown.
private struct AccessibilityRow: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            LabeledContent(L("Erişilebilirlik izni", "Accessibility permission")) {
                if Paster.isTrusted {
                    Label(L("Verildi", "Granted"), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.green.mark)
                } else {
                    HStack(spacing: Theme.Spacing.m) {
                        Text(L("Gerekli", "Needed")).foregroundStyle(Theme.warning.mark)
                        Button(L("İzin ver…", "Allow…")) {
                            Paster.requestTrust()
                            Paster.openAccessibilitySettings()
                        }
                    }
                }
            }
        }
    }
}

private struct SnippetsPage: View {
    private let store = LauncherStore.shared

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .snippets) }
            Section {
                if store.snippets.isEmpty {
                    Text(L("Henüz parçacık yok.", "No snippets yet.")).foregroundStyle(Theme.textMuted)
                }
                ForEach(store.snippets) { SnippetRow(snippet: $0) }
                Button {
                    store.save(snippet: Snippet(keyword: "", name: L("Yeni parçacık", "New snippet"), text: ""))
                } label: { Label(L("Parçacık ekle", "Add a snippet"), systemImage: "plus") }
            } footer: {
                Footnote(L("Başlatıcıda kısaltmayı ya da adını yaz, ↩ ile yapıştır. Metinde {date} bugünün tarihi, {time} saat, {clipboard} panodaki metin olur. Örnek: imza, adres, IBAN açıklaması, sık yazdığın yanıtlar.",
                           "Type the keyword or name in the launcher and press ↩ to paste. In the text, {date} becomes today's date, {time} the time and {clipboard} what's on the clipboard. Good for a signature, an address, replies you write often."))
            }
        }
        .formStyle(.grouped)
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    private let store = LauncherStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                TextField(L("Kısaltma", "Keyword"), text: binding(\.keyword)).frame(width: 90)
                TextField(L("Ad", "Name"), text: binding(\.name))
                Button { store.remove(snippet: snippet) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(TextButtonStyle(color: Theme.textMuted))
                    .help(L("Sil", "Delete"))
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            TextEditor(text: binding(\.text))
                .font(Theme.body)
                .frame(minHeight: Theme.launcherRow * 2)
                .scrollContentBackground(.hidden)
                .padding(Theme.Spacing.xs)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func binding(_ path: WritableKeyPath<Snippet, String>) -> Binding<String> {
        Binding(get: { snippet[keyPath: path] }, set: { value in
            var copy = snippet
            copy[keyPath: path] = value
            store.save(snippet: copy)
        })
    }
}

private struct WindowsPage: View {
    @AppStorage(Prefs.windowHotkeys) private var hotkeys = false

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .windows) }
            Section {
                Toggle(L("Pencere kısayolları", "Window shortcuts"), isOn: Binding(get: { hotkeys }, set: { on in
                    hotkeys = on
                    if on && !Paster.isTrusted { Paster.requestTrust() }
                }))
                AccessibilityRow()
            } footer: {
                Footnote(L("Öndeki pencereyi taşır ve boyutlandırır. Bunun için Erişilebilirlik izni gerekir. Kısayolları kapalı olsa da başlatıcıda \"sol yarı\", \"ortala\" yazarak kullanabilirsin.",
                           "Moves and resizes the front window. This needs Accessibility permission. With shortcuts off you can still type \"left half\" or \"center\" in the launcher."))
            }
            Section(L("Yerleşimler", "Layouts")) {
                ForEach(WindowAction.allCases) { action in
                    LabeledContent {
                        Text(verbatim: action.shortcut ?? L("Başlatıcıdan", "From the launcher"))
                            .monospacedDigit().foregroundStyle(Theme.textMuted)
                    } label: {
                        Label(action.title, systemImage: action.symbol)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// One global shortcut: on/off, and a button that records a new key combination.
private struct HotKeyRow: View {
    let title: String
    let shortcut: HotKey.Shortcut
    @Binding var enabled: Bool
    @State private var recording = false
    @State private var label = ""
    @State private var monitor: Any?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: Theme.Spacing.m) {
                Button { recording ? stop() : start() } label: {
                    Text(verbatim: recording ? L("Tuşlara bas…", "Press keys…") : label)
                        .font(Theme.bodyStrong).monospacedDigit()
                        .foregroundStyle(recording ? Theme.accent : Theme.text)
                        .frame(minWidth: 96)
                }
                .disabled(!enabled)
                Toggle(title, isOn: $enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
        .onAppear { label = HotKey.label(shortcut) }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKey.suspend(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = Int(event.keyCode), flags = event.modifierFlags, characters = event.charactersIgnoringModifiers
            let done = MainActor.assumeIsolated { record(keyCode, flags, characters) }
            return done ? nil : event
        }
    }

    private func record(_ keyCode: Int, _ flags: NSEvent.ModifierFlags, _ characters: String?) -> Bool {
        if keyCode == 53 { stop(); return true }
        if keyCode == 51 && HotKey.modifiers(flags).carbon == 0 {
            HotKey.set(shortcut, nil)
            label = HotKey.label(shortcut)
            stop()
            return true
        }
        let modifiers = HotKey.modifiers(flags)
        // A plain letter would fire while typing anywhere; it needs ⌘, ⌃ or ⌥ (F-keys may stand alone).
        let isFunctionKey = (96...122).contains(keyCode)
        guard modifiers.carbon & (cmdKey | controlKey | optionKey) != 0 || isFunctionKey else {
            NSSound.beep()
            return true
        }
        let combo = HotKey.Combo(keyCode: keyCode, modifiers: modifiers.carbon,
                                 label: modifiers.symbols + HotKey.keyName(keyCode, characters))
        HotKey.set(shortcut, combo)
        label = combo.label
        stop()
        return true
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        HotKey.suspend(false)
    }
}
