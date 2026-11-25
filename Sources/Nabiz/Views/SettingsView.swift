import AppKit
import Observation
import ServiceManagement
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general, menuBar, panel, markets, currency, ai, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L("Genel", "General")
        case .menuBar: L("Menü çubuğu", "Menu Bar")
        case .panel: L("Panel", "Panel")
        case .markets: L("Piyasalar", "Markets")
        case .currency: L("Döviz", "Currency")
        case .ai: L("AI limitleri", "AI Limits")
        case .about: L("Hakkında", "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .menuBar: "menubar.rectangle"
        case .panel: "list.bullet.rectangle.fill"
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
            window.backgroundColor = NSColor(Theme.surface)
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
                    Text(page.title).font(Theme.body)
                }
                .tag(page)
            }
            .listStyle(.sidebar)
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)
            .background(Theme.surfaceRaised)
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selection.page ?? .general {
                case .general: GeneralPage()
                case .menuBar: MenuBarPage()
                case .panel: PanelPage()
                case .markets: MarketsPage()
                case .currency: CurrencyPage()
                case .ai: AIPage()
                case .about: AboutPage()
                }
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .background(Theme.surface)
            .background(HiddenScrollers().id(selection.page))
            .navigationTitle(selection.page?.title ?? "")
        }
        .frame(minWidth: 640, minHeight: 460)
        .id(language)
    }
}

// MARK: - Pages

private struct GeneralPage: View {
    @AppStorage(Prefs.language) private var language = "system"
    @AppStorage(Prefs.refreshSeconds) private var refresh = 5
    @AppStorage(Prefs.hotkey) private var hotkey = true
    @State private var login = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
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
                Toggle(L("Hızlı hesap kısayolu: ⌃⌥Boşluk", "Quick calculator shortcut: ⌃⌥Space"), isOn: $hotkey)
            } footer: {
                Footnote(L("Her yerden hesap makinesini ve döviz çeviriciyi açar.", "Opens the calculator and currency converter from anywhere."))
            }
        }
        .formStyle(.grouped)
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
            HStack(spacing: Theme.Spacing.xs) {
                if stacked {
                    let icon = (showIcon || parts.isEmpty) ? NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: nil) : nil
                    Image(nsImage: MenuBarText.image(parts: parts, icon: icon, height: NSStatusBar.system.thickness))
                        .renderingMode(.template)
                } else {
                    if showIcon || text.isEmpty { Image(systemName: "gauge.with.dots.needle.33percent") }
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

    var body: some View {
        Form {
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
                ForEach(PanelSection.allCases) { SectionSettingRow(section: $0, collapsible: collapsible) }
            } header: {
                Text(L("Bölümler", "Sections"))
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

/// "Simulators   ☑ Open   [on]": whether the section shows, and whether it starts open.
private struct SectionSettingRow: View {
    let section: PanelSection
    let collapsible: Bool
    @AppStorage private var shown: Bool
    @AppStorage private var expanded: Bool

    init(section: PanelSection, collapsible: Bool) {
        self.section = section
        self.collapsible = collapsible
        _shown = AppStorage(wrappedValue: true, section.showKey)
        _expanded = AppStorage(wrappedValue: true, section.expandedKey)
    }

    var body: some View {
        LabeledContent(section.title) {
            HStack(spacing: Theme.Spacing.l) {
                Toggle(L("Açık", "Open"), isOn: Binding(get: { expanded }, set: { section.setExpanded($0) }))
                    .toggleStyle(.checkbox)
                    .disabled(!shown || !collapsible)
                Toggle(section.title, isOn: $shown).labelsHidden()
            }
        }
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
                Footnote(L("Örnek: haftalık limitin %94'ü kullanıldıysa \"%6 kaldı\" ya da \"%94\" yazar. Çubuk her zaman kullanılan kısmı doldurur.",
                           "Example: with 94% of the weekly limit used it reads \"6% left\" or \"94%\". The bar always fills with what is used."))
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
            Text(L("Mac'inin nabzını menü çubuğunda tutar. Açık kaynak, MIT lisansı.",
                   "Keeps your Mac's pulse in the menu bar. Open source, MIT license."))
                .font(Theme.body).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            Text(L("Ölçümler Mac'inde yapılır. Döviz kurları Avrupa Merkez Bankası'ndan (frankfurter.dev) gelir; AI limitleri yalnızca açtığın sağlayıcıların kendi sunucularından okunur.",
                   "Everything is measured on your Mac. Rates come from the European Central Bank (frankfurter.dev); AI limits are read only from the providers you turn on, from their own servers."))
                .font(Theme.small).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center)
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
