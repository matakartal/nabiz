// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Observation
import ServiceManagement
import Carbon.HIToolbox
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general, appearance, shortcuts, maintenance
    case menuBar, panel, advice
    case ai, aiChat, dictation, aiLimits, mcp
    case launcher, extensions, developer, clipboard, snippets, windows, screenshot, focus, schedules
    case calendar, weather, markets, currency
    case about

    var id: String { rawValue }

    var title: String { L(names.tr, names.en) }

    var names: (tr: String, en: String) {
        switch self {
        case .general: ("Genel", "General")
        case .appearance: ("Görünüm", "Appearance")
        case .shortcuts: ("Kısayollar", "Shortcuts")
        case .maintenance: ("Yedek ve bakım", "Backup & Upkeep")
        case .menuBar: ("Menü çubuğu", "Menu Bar")
        case .panel: ("Panel", "Panel")
        case .advice: ("Öneriler", "Suggestions")
        case .ai: ("AI'a sor", "Ask AI")
        case .aiChat: ("Sohbet", "Chat")
        case .dictation: ("Dikte", "Dictation")
        case .aiLimits: ("AI limitleri", "AI Limits")
        case .mcp: ("MCP", "MCP")
        case .launcher: ("Başlatıcı", "Launcher")
        case .extensions: ("Uzantılar", "Extensions")
        case .developer: ("Geliştirici", "Developer")
        case .clipboard: ("Pano", "Clipboard")
        case .snippets: ("Parçacıklar", "Snippets")
        case .windows: ("Pencereler", "Windows")
        case .screenshot: ("Görüntü ve kayıt", "Screenshots & Recording")
        case .focus: ("Odak", "Focus")
        case .schedules: ("Görevler", "Schedules")
        case .calendar: ("Takvim", "Calendar")
        case .weather: ("Hava durumu", "Weather")
        case .markets: ("Piyasalar", "Markets")
        case .currency: ("Döviz", "Currency")
        case .about: ("Hakkında", "About")
        }
    }

    var subtitle: String {
        switch self {
        case .general: L("Dil, açılış, yenileme, notlar ve bildirimler.", "Language, startup, refresh, notes and notifications.")
        case .appearance: L("Renk, tema, yazı tipi, boyut ve sıklık.", "Colour, theme, typeface, size and density.")
        case .shortcuts: L("Her aracı açan genel kısayollar.", "The global shortcuts that open each tool.")
        case .maintenance: L("Yedekleme, otomatik temizlik ve sıfırlama.", "Backups, automatic clean-up and reset.")
        case .menuBar: L("Menü çubuğunda ne ve nasıl görüneceği.", "What the menu bar shows, and how.")
        case .panel: L("Paneldeki bölümler, sıraları, katlama ve araçlar.", "The panel's sections, their order, folding and tools.")
        case .advice: L("Hangi durumlarda öneri görüneceği.", "Which situations bring up a suggestion.")
        case .ai: L("Hızlı soru, kim cevaplasın, model ve kendi AI komutların.", "Quick questions, who answers, the model and your own AI commands.")
        case .aiChat: L("Sohbet penceresi ve sohbet geçmişi.", "The chat window and its history.")
        case .dictation: L("Konuş, imlecin olduğu yere yazılsın.", "Speak, and it's typed where the cursor is.")
        case .aiLimits: L("Claude, Codex ve Gemini abonelik limitleri.", "Claude, Codex and Gemini subscription limits.")
        case .mcp: L("Claude Code, Claude Desktop ve diğer AI uygulamaları Nabız'ı kullansın.", "Let Claude Code, Claude Desktop and other AI apps use Nabız.")
        case .launcher: L("Uygulama, komut, hesap ve web araması tek yerde.", "Apps, commands, maths and web search in one place.")
        case .extensions: L("Dosyalar, kestirmeler, betikler ve video indirme.", "Files, Shortcuts, scripts and video downloads.")
        case .developer: L("Projeler, portlar, Docker, geliştirici temizliği ve notarize takibi.", "Projects, ports, Docker, developer clean-up and notarization.")
        case .clipboard: L("Kopyaladıklarının geçmişi ve yapıştırma.", "The history of what you copied, and pasting.")
        case .snippets: L("Kısa bir kelimeyle yapıştırılan hazır metinler.", "Saved text you paste with a short keyword.")
        case .windows: L("Öndeki pencereyi kısayolla yerleştir.", "Place the front window with a shortcut.")
        case .screenshot: L("Ekran görüntüsü ve ekran kaydı kısayolları, sonrasında ne olacağı.", "Screenshot and screen recording shortcuts, and what happens next.")
        case .focus: L("Pomodoro süreleri ve odakta gizlenecek uygulamalar.", "Pomodoro lengths, and the apps focus mode hides.")
        case .schedules: L("Belirli gün ve saatlerde kendiliğinden yapılacak işler.", "Things done on their own at set days and times.")
        case .calendar: L("Bugünkü toplantılar, hatırlatma ve tek tıkla katılma.", "Today's meetings, a heads-up and one-click join.")
        case .weather: L("Şehir, birim ve menü çubuğunda sıcaklık.", "Your city, the unit and the temperature in the menu bar.")
        case .markets: L("Hyperliquid'den izlenecek piyasalar.", "The Hyperliquid markets to watch.")
        case .currency: L("Ana para birimi ve izlenen kurlar.", "Your main currency and the rates you watch.")
        case .about: ""
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintpalette.fill"
        case .shortcuts: "command"
        case .maintenance: "archivebox.fill"
        case .menuBar: "menubar.rectangle"
        case .panel: "list.bullet.rectangle.fill"
        case .advice: "lightbulb.fill"
        case .ai: "sparkles"
        case .aiChat: "bubble.left.and.bubble.right.fill"
        case .dictation: "mic.fill"
        case .aiLimits: "gauge.with.dots.needle.67percent"
        case .mcp: "point.3.connected.trianglepath.dotted"
        case .launcher: "magnifyingglass"
        case .extensions: "puzzlepiece.extension.fill"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .clipboard: "doc.on.clipboard.fill"
        case .snippets: "text.quote"
        case .windows: "rectangle.split.2x1.fill"
        case .screenshot: "camera.viewfinder"
        case .focus: "brain.head.profile"
        case .schedules: "calendar.badge.clock"
        case .calendar: "calendar"
        case .weather: "cloud.sun"
        case .markets: "chart.line.uptrend.xyaxis"
        case .currency: "dollarsign.arrow.circlepath"
        case .about: "info.circle.fill"
        }
    }
}

@MainActor
@Observable
final class SettingsSelection {
    var page: SettingsPage? = .general
    /// The section a search result points at; the page scrolls to it and lights it up briefly.
    var anchor: String?
    var flash: String?
    /// Bumped on every jump, so picking the same result twice still scrolls.
    var jump = 0

    func go(_ target: SettingsTarget) {
        page = target.page
        anchor = target.anchor
        if target.anchor != nil { jump += 1 }
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    private static let selection = SettingsSelection()
    /// The live monitor, for the menu bar preview.
    static weak var monitor: Monitor?

    static func show(_ page: SettingsPage?, anchor: String? = nil) {
        if let page { selection.go(SettingsTarget(page: page, anchor: anchor)) }
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(selection: selection))
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            WindowChrome.apply(window)
            window.isReleasedWhenClosed = false
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
        // AppKit gives the first text field focus on open; the search field should wait for a click or ⌘F.
        DispatchQueue.main.async { window?.makeFirstResponder(nil) }
    }
}

/// Settings in the System Settings shape: a sidebar of pages, a grouped form on the right. Opaque throughout.
struct SettingsView: View {
    @Bindable var selection: SettingsSelection
    @AppStorage(Prefs.language) private var language = "system"
    @AppStorage("settingsSidebarWidth") private var sidebarWidth = 220.0
    @State private var query = ""

    init(selection: SettingsSelection = SettingsSelection(), query: String = "") {
        self.selection = selection
        _query = State(initialValue: query)
    }

    var body: some View {
        // One bar along the top, level with the window buttons and split like the window below it (as in the AI window).
        UnifiedSplitView(sidebarVisible: .constant(true), sidebarWidth: $sidebarWidth, minWidth: 200, maxWidth: 300) {
            VStack(spacing: 0) {
                SidebarSearchField(text: $query, onMove: move) { if let first = hits.first { open(first) } }
                    .padding(.horizontal, Theme.sidebarInset)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.s)
                sidebarList
            }
        } detail: {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    switch selection.page ?? .general {
                    case .general: GeneralPage()
                    case .appearance: AppearancePage()
                    case .shortcuts: ShortcutsPage()
                    case .maintenance: MaintenancePage()
                    case .menuBar: MenuBarPage()
                    case .panel: PanelPage()
                    case .advice: AdvicePage()
                    case .ai: AIPage()
                    case .aiChat: AIChatPage()
                    case .dictation: DictationPage()
                    case .aiLimits: AILimitsPage()
                    case .mcp: MCPPage()
                    case .launcher: LauncherPage()
                    case .extensions: ExtensionsPage()
                    case .developer: DeveloperPage()
                    case .clipboard: ClipboardPage()
                    case .snippets: SnippetsPage()
                    case .windows: WindowsPage()
                    case .screenshot: ScreenshotPage()
                    case .focus: FocusPage()
                    case .schedules: SchedulesPage()
                    case .calendar: CalendarPage()
                    case .weather: WeatherPage()
                    case .markets: MarketsPage()
                    case .currency: CurrencyPage()
                    case .about: AboutPage()
                    }
                }
                .environment(\.settingsFlash, selection.flash)
                .onAppear { if selection.anchor != nil { reveal(proxy) } }
                .onChange(of: selection.jump) { reveal(proxy) }
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .background(HiddenScrollers().id(selection.page))
        } sidebarBar: {
            EmptyView()
        } detailBar: {
            HStack(spacing: Theme.Spacing.s) {
                Text(verbatim: (selection.page ?? .general).title).font(Theme.bodyStrong).foregroundStyle(Theme.text)
                    .contentTransition(.opacity)
                Spacer()
            }
        }
        .frame(minWidth: 640, minHeight: 460)
        .background(MenuMaterial().ignoresSafeArea())
        .appearanceRoot(opaqueFill: Theme.surface)
        .onChange(of: query) { _, new in
            if new.trimmingCharacters(in: .whitespaces).isEmpty { selection.anchor = nil }
        }
    }

    private var hits: [SettingsHit] { SettingsIndex.search(query) }

    private var current: SettingsTarget {
        SettingsTarget(page: selection.page ?? .general, anchor: selection.anchor)
    }

    private func open(_ hit: SettingsHit) { selection.go(hit.target) }

    /// ↑↓ in the search field walk the results and open each one as they go.
    private func move(_ step: Int) {
        let list = hits
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.target == current }.map { $0 + step } ?? (step > 0 ? 0 : list.count - 1)
        open(list[min(max(index, 0), list.count - 1)])
    }

    /// Waits for the page to lay out, scrolls the section to the top and lights it up for a moment.
    private func reveal(_ proxy: ScrollViewProxy) {
        guard let anchor = selection.anchor else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(anchor, anchor: .top) }
            withAnimation(.easeOut(duration: 0.2)) { selection.flash = anchor }
            try? await Task.sleep(for: .seconds(1.6))
            if selection.flash == anchor { withAnimation(.easeOut(duration: 0.6)) { selection.flash = nil } }
        }
    }

    /// Grouped with small headings while browsing; while searching, pages first and then the settings themselves.
    private var sidebarList: some View {
        List(selection: Binding(get: { current }, set: { if let target = $0 { selection.go(target) } })) {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ForEach(SettingsGroup.allCases) { group in
                    Section {
                        ForEach(group.pages) { SidebarRow(page: $0) }
                    } header: {
                        if let title = group.title {
                            Text(verbatim: title).font(Theme.smallStrong).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            } else {
                let list = hits
                let pages = list.filter { $0.target.anchor == nil }
                let items = list.filter { $0.target.anchor != nil }
                if list.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(L("Sonuç yok", "No results")).font(Theme.body).foregroundStyle(Theme.text)
                        Text(L("Başka bir kelime dene: \"koyu\", \"kısayol\", \"yedek\"…", "Try another word: \"dark\", \"shortcut\", \"backup\"…"))
                            .font(Theme.small).foregroundStyle(Theme.textMuted)
                    }
                    .selectionDisabled()
                }
                if !pages.isEmpty {
                    Section {
                        ForEach(pages) { SidebarRow(page: $0.target.page) }
                    } header: {
                        Text(L("Sayfalar", "Pages")).font(Theme.smallStrong).foregroundStyle(Theme.textMuted)
                    }
                }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { SettingsHitRow(hit: $0, query: query) }
                    } header: {
                        Text(L("Ayarlar · \(items.count)", "Settings · \(items.count)")).font(Theme.smallStrong).foregroundStyle(Theme.textMuted)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollIndicators(.never)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Sidebar

/// The sidebar's groups, each under a small heading; About sits alone at the end, like a footer.
enum SettingsGroup: String, CaseIterable, Identifiable {
    case app, bar, ai, tools, tracking, about

    var id: String { rawValue }

    var title: String? {
        switch self {
        case .app: L("Uygulama", "App")
        case .bar: L("Menü çubuğu ve panel", "Menu Bar & Panel")
        case .ai: L("Yapay zekâ", "AI")
        case .tools: L("Araçlar", "Tools")
        case .tracking: L("Takip", "Tracking")
        case .about: nil
        }
    }

    var pages: [SettingsPage] {
        switch self {
        case .app: [.general, .appearance, .shortcuts, .maintenance]
        case .bar: [.menuBar, .panel, .advice]
        case .ai: [.ai, .aiChat, .dictation, .aiLimits, .mcp]
        case .tools: [.launcher, .extensions, .developer, .clipboard, .snippets, .windows, .screenshot, .focus, .schedules]
        case .tracking: [.calendar, .weather, .markets, .currency]
        case .about: [.about]
        }
    }
}

private struct SidebarRow: View {
    let page: SettingsPage

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: page.symbol)
                .font(Theme.small)
                .foregroundStyle(.white)
                .frame(width: Theme.settingsIcon, height: Theme.settingsIcon)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            Text(page.title).font(Theme.body).lineLimit(1).minimumScaleFactor(0.85)
        }
        .tag(SettingsTarget(page: page, anchor: nil))
    }
}

/// A single setting found by search: its name with the typed letters in bold, and the page it lives on.
private struct SettingsHitRow: View {
    let hit: SettingsHit
    let query: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: hit.target.page.symbol)
                .font(Theme.small)
                .foregroundStyle(Theme.accent)
                .frame(width: Theme.settingsIcon, height: Theme.settingsIcon)
            VStack(alignment: .leading, spacing: 1) {
                Text(SettingsIndex.highlighted(hit.title, query)).font(Theme.body).lineLimit(1)
                Text(verbatim: hit.target.page.title).font(Theme.small).foregroundStyle(Theme.textMuted).lineLimit(1)
            }
        }
        .tag(hit.target)
    }
}

/// A flat search field for the sidebar: a quiet fill, no shadow or border, lined up with the selection highlight.
/// ⌘F focuses it, ⎋ clears it, ↩ opens the first match, ↑↓ walk the results when `onMove` is given.
struct SidebarSearchField: View {
    @Binding var text: String
    var onMove: ((Int) -> Void)? = nil
    /// Bumped to put the cursor here (⌘K in the AI chat).
    var focusTrigger = 0
    let onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textMuted)
            TextField(L("Ara", "Search"), text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(onSubmit)
                .onExitCommand { text = "" }
                .onChange(of: focusTrigger) { _, _ in focused = true }
                .onKeyPress(.downArrow) {
                    guard let onMove, !text.isEmpty else { return .ignored }
                    onMove(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard let onMove, !text.isEmpty else { return .ignored }
                    onMove(-1)
                    return .handled
                }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textMuted) }
                    .buttonStyle(.plain)
                    .help(L("Temizle", "Clear"))
            }
        }
        .font(Theme.body)
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: Theme.sidebarSearch)
        .background(Theme.track, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                .strokeBorder(Theme.accent.opacity(focused ? 0.6 : 0), lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.15), value: focused)
        .background {
            Button("") { focused = true }.keyboardShortcut("f", modifiers: .command).hidden()
        }
    }
}

/// A form section a search result can point at: it carries the result's id for scrolling and lights up when opened.
struct SettingsSection<Content: View, Header: View, Footer: View>: View {
    let id: String
    let content: Content
    let header: Header
    let footer: Footer
    @Environment(\.settingsFlash) private var flash

    init(id: String, content: Content, header: Header, footer: Footer) {
        self.id = id
        self.content = content
        self.header = header
        self.footer = footer
    }

    var body: some View {
        Section {
            // Grouped forms ignore row backgrounds on macOS, so the glow is drawn under each row, out to the card's edges
            // and to the separators, so the rows join into one block. While lit, short rows (a button) span the width.
            content
                .frame(maxWidth: flash == id ? .infinity : nil, alignment: .leading)
                .background {
                    Theme.accent.opacity(flash == id ? 0.2 : 0)
                        .padding(.horizontal, -Theme.Spacing.l)
                        .padding(.vertical, -10.5)
                        .allowsHitTesting(false)
                }
        } header: { header } footer: { footer }
            .id(id)
    }
}

extension SettingsSection where Header == EmptyView, Footer == EmptyView {
    init(_ id: String, @ViewBuilder content: () -> Content) {
        self.init(id: id, content: content(), header: EmptyView(), footer: EmptyView())
    }
}

extension SettingsSection where Footer == EmptyView {
    init(_ id: String, @ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.init(id: id, content: content(), header: header(), footer: EmptyView())
    }
}

extension SettingsSection where Header == EmptyView {
    init(_ id: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(id: id, content: content(), header: EmptyView(), footer: footer())
    }
}

extension SettingsSection {
    init(_ id: String, @ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.init(id: id, content: content(), header: header(), footer: footer())
    }
}

extension SettingsSection where Header == Text, Footer == EmptyView {
    init(_ id: String, title: String, @ViewBuilder content: () -> Content) {
        self.init(id: id, content: content(), header: Text(verbatim: title), footer: EmptyView())
    }
}

extension EnvironmentValues {
    @Entry var settingsFlash: String? = nil
}

// MARK: - Pages

private struct GeneralPage: View {
    @AppStorage(Prefs.language) private var language = "system"
    @AppStorage(Prefs.refreshSeconds) private var refresh = 5
    @AppStorage(Prefs.notesApp) private var notesApp = "nabiz"
    @AppStorage(Prefs.notifications) private var notifications = false
    @AppStorage(Prefs.showInDock) private var dock = false
    @State private var login = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .general) }
            SettingsSection("general.language") {
                Picker(L("Dil", "Language"), selection: $language) {
                    Text(L("Sistem", "System")).tag("system")
                    Text(verbatim: "Türkçe").tag("tr")
                    Text(verbatim: "English").tag("en")
                }
                Toggle(L("Girişte aç", "Open at login"), isOn: Binding(get: { login }, set: { setLogin($0) }))
                Toggle(L("Dock'ta göster", "Show in Dock"), isOn: $dock)
            } footer: {
                Footnote(L("Dock'ta gösterince Nabız ⌘⇥ listesinde ve menü çubuğunda da kendi menüsüyle çıkar. Dock simgesine tıklamak paneli açar, sağ tıklamak kısayolları gösterir.",
                           "In the Dock, Nabız also shows in ⌘⇥ and gets its own menus in the menu bar. Clicking its icon opens the panel; right-clicking lists the shortcuts."))
            }
            SettingsSection("general.refresh") {
                Picker(L("Arka planda yenile", "Refresh in background"), selection: $refresh) {
                    ForEach([1, 2, 5, 10, 30], id: \.self) { Text(L("\($0) saniyede bir", "every \($0) s")).tag($0) }
                }
            } footer: {
                Footnote(L("Panel açıkken her 2 saniyede bir yenilenir. Seyrek yenileme pili korur.",
                       "While the panel is open it refreshes every 2 seconds. Slower refresh saves battery."))
            }
            SettingsSection("general.notes") {
                Picker(L("Notlar için", "For notes"), selection: $notesApp) {
                    Text(L("Nabız notları", "Nabız notes")).tag("nabiz")
                    Text(L("Apple Notlar", "Apple Notes")).tag("apple")
                }
            } footer: {
                Footnote(L("Not kısayolu, Notlar aracı ve \"Not olarak kaydet\" seçtiğin uygulamayı kullanır. Apple Notlar için macOS bir kez izin ister.",
                           "The notes shortcut, the Notes tool and \"Save as note\" use the app you pick. For Apple Notes, macOS asks once for permission."))
            }
            SettingsSection("general.notifications") {
                Toggle(L("Bildirimler", "Notifications"), isOn: Binding(get: { notifications }, set: { on in
                    notifications = on
                    if on { Notifier.shared.requestPermission() }
                }))
            } footer: {
                Footnote(L("Bellek kritikleşince, işlemci 3 dakika %90'ın üstünde kalınca, disk 10 GB'ın altına inince, pil %10'a düşünce ve açık bir AI limiti hızlı bitince ya da kullanılmadan sıfırlanacakken haber verir. Her durum için bir kez.",
                           "Tells you when memory turns critical, the CPU stays above 90% for 3 minutes, the disk drops under 10 GB, the battery reaches 10%, and an AI limit you turned on burns fast or is about to reset unused. Once each time."))

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

private struct ShortcutsPage: View {
    @AppStorage(Prefs.hotkey) private var hotkey = true
    @AppStorage(Prefs.panelHotkey) private var panelHotkey = true
    @AppStorage(Prefs.clipboardHotkey) private var clipboardHotkey = true
    @AppStorage(Prefs.noteHotkey) private var noteHotkey = true
    @AppStorage(Prefs.dictationHotkey) private var dictationHotkey = false
    @AppStorage(Prefs.shotHotkey) private var shotHotkey = true
    @AppStorage(Prefs.recHotkey) private var recHotkey = true
    @AppStorage(Prefs.aiHotkey) private var aiHotkey = true
    @AppStorage(Prefs.aiChatHotkey) private var aiChatHotkey = true
    @AppStorage(Prefs.brightnessKeys) private var brightnessKeys = false

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .shortcuts) }
            SettingsSection("shortcuts.keys") {
                HotKeyRow(title: L("Başlatıcı", "Launcher"), shortcut: .launcher, enabled: $hotkey)
                HotKeyRow(title: L("Pano geçmişi", "Clipboard history"), shortcut: .clipboard, enabled: $clipboardHotkey)
                HotKeyRow(title: L("Notlar", "Notes"), shortcut: .note, enabled: $noteHotkey)
                HotKeyRow(title: L("AI sohbet", "AI chat"), shortcut: .aiChat, enabled: $aiChatHotkey)
                HotKeyRow(title: L("AI'a sor", "Ask AI"), shortcut: .ai, enabled: $aiHotkey)
                HotKeyRow(title: L("Panel", "Panel"), shortcut: .panel, enabled: $panelHotkey)
                HotKeyRow(title: L("Dikte", "Dictation"), shortcut: .dictation, enabled: $dictationHotkey)
                HotKeyRow(title: L("Ekran görüntüsü", "Screenshot"), shortcut: .screenshot, enabled: $shotHotkey)
                HotKeyRow(title: L("Ekran kaydı", "Screen recording"), shortcut: .record, enabled: $recHotkey)
                Button(L("Neler yapabilir?", "What can it do?")) { HelpWindow.show() }
            } header: {
                Text(L("Kısayollar", "Shortcuts"))
            } footer: {
                Footnote(L("Değiştirmek için kısayola tıkla ve yeni tuşlara bas (en az bir ⌘, ⌃ ya da ⌥ ile). ⎋ vazgeçer, ⌫ varsayılana döndürür. Pencere kısayolları Pencereler sayfasında; ekran görüntüsü ayarları kendi sayfasında. Dikte: kısayola bas, konuş, yeniden bas; söylediklerin imlecin olduğu yere yazılır.",
                           "Click a shortcut and press the new keys (with at least ⌘, ⌃ or ⌥). ⎋ cancels, ⌫ goes back to the default. Window shortcuts are on the Windows page; screenshot options have their own page. Dictation: press the shortcut, speak, press it again; your words land where the cursor is."))
            }
            SettingsSection("shortcuts.brightness") {
                Toggle(L("Parlaklık tuşları harici ekranı da ayarlasın", "Brightness keys work on external displays"), isOn: $brightnessKeys)
                    .onChange(of: brightnessKeys) { _, on in
                        if on && !Paster.isTrusted { Paster.requestTrust() }
                        Brightness.shared.refresh()
                    }
                if brightnessKeys { AccessibilityRow() }
                LabeledContent(L("Bulunan harici ekran", "External displays found")) {
                    let names = Brightness.shared.displays.filter { !$0.builtIn }.map(\.name)
                    Text(verbatim: names.isEmpty ? L("Yok", "None") : names.joined(separator: ", ")).foregroundStyle(Theme.textMuted)
                }
            } header: {
                Text(L("Ekran parlaklığı", "Display brightness"))
            } footer: {
                Footnote(L("Fare hangi ekrandaysa tuşlar onu ayarlar; yerleşik ekranda her zamanki gibi çalışır. ⇧⌥ ile daha ince adımlar. Harici ekranın kendi menüsünde DDC/CI açık olmalı. Panelde Ekranlar bölümü de her ekran için bir sürgü gösterir.",
                           "The keys change the display the pointer is on; on the built-in display they work as always. ⇧⌥ gives finer steps. The display's own menu must have DDC/CI on. The panel's Displays section also shows a slider for each display."))
            }
        }
        .formStyle(.grouped)
    }
}

private struct ScreenshotPage: View {
    @AppStorage(Prefs.shotHotkey) private var shotHotkey = true
    @AppStorage(Prefs.shotAfter) private var shotAfter = "preview"
    @AppStorage(Prefs.recHotkey) private var recHotkey = true

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .screenshot) }
            SettingsSection("screenshot.keys") {
                HotKeyRow(title: L("Ekran görüntüsü", "Screenshot"), shortcut: .screenshot, enabled: $shotHotkey)
                Picker(L("Ekran görüntüsünden sonra", "After a screenshot"), selection: $shotAfter) {
                    Text(L("Köşede önizleme", "Thumbnail in the corner")).tag("preview")
                    Text(L("Düzenleyiciyi aç", "Open the editor")).tag("editor")
                    Text(L("Hiçbir şey", "Nothing")).tag("none")
                }
            } footer: {
                Footnote(L("Kısayola bas, alanı seç: önizlemeden düzenleyiciyi açar, ok, metin, bulanıklık ve çerçeve eklersin.",
                           "Press the shortcut and pick an area: from the thumbnail open the editor to add arrows, text, blur and a frame."))
            }
            SettingsSection("screenshot.record") {
                HotKeyRow(title: L("Ekran kaydı", "Screen recording"), shortcut: .record, enabled: $recHotkey)
                Button(L("Son kaydı aç", "Open the last recording")) { RecEditor.showLatest() }
            } header: {
                SectionTitle(L("Ekran kaydı", "Screen recording"))
            } footer: {
                Footnote(L("Kısayola bas: tüm ekran, pencere ya da alan ve ses seç, kayda başla. Bitirmek için menü çubuğundaki kırmızı noktaya ya da kısayola yeniden bas. Düzenleyici tıkladığın yerlere kendiliğinden yakınlaşır, imleci pürüzsüz ve büyük çizer; arka plan, kırpma ve MP4/GIF dışa aktarma orada.",
                           "Press the shortcut, pick the whole screen, a window or an area and the sound, and record. To stop, click the red dot in the menu bar or press the shortcut again. The editor zooms in where you clicked and draws the pointer smooth and large; background, trimming and MP4/GIF export are there."))
            }
        }
        .formStyle(.grouped)
    }
}

private struct MaintenancePage: View {
    @AppStorage(Prefs.autoBackup) private var autoBackup = false
    @AppStorage(Prefs.rustAutoClean) private var rustAutoClean = false
    @AppStorage(Prefs.rustAutoCleanDays) private var rustDays = 14

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .maintenance) }
            SettingsSection("maintenance.rust") {
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
            SettingsSection("maintenance.backup") {
                HStack {
                    Button(L("Yedekle…", "Back up…")) { Backup.saveAs() }
                    Button(L("Yedekten yükle…", "Load a backup…")) { Backup.restore() }
                }
                Toggle(L("Her gün iCloud Drive'a yedekle", "Back up to iCloud Drive every day"), isOn: $autoBackup)
                    .disabled(Backup.iCloudFolder == nil)
                if autoBackup, let folder = Backup.iCloudFolder {
                    LabeledContent(Backup.lastAutoBackup.map { L("Son yedek: ", "Last backup: ") + $0.formatted(.relative(presentation: .named).locale(Format.locale)) }
                                   ?? L("Henüz yedek yok", "No backup yet")) {
                        Button(L("Klasörü göster", "Show folder")) {
                            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(folder)
                        }
                    }
                }
            } header: {
                Text(L("Yedek", "Backup"))
            } footer: {
                Footnote(L("Tek dosyada ayarlar, parçacıklar, bağlantılar, kendi kısayolların, pencere yerleşimleri, AI komutları, görevler ve notlar. Başka bir Mac'te \"Yedekten yükle\" ile aynı Nabız'a kavuşursun. Pano geçmişi ve oturum bilgileri hiç yedeklenmez. iCloud Drive'da son 10 yedek tutulur.",
                           "One file with settings, snippets, quicklinks, your shortcuts, window layouts, AI commands, schedules and notes. On another Mac, \"Load a backup\" gives you the same Nabız. The clipboard history and sign-ins are never included. iCloud Drive keeps the last 10."))
            }
            SettingsSection("maintenance.reset") {
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
    @AppStorage(Prefs.menuBarHider) private var hider = false
    @AppStorage(Prefs.menuBarHiderDelay) private var hiderDelay = 10

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .menuBar) }
            SettingsSection("menuBar.preview") {
                MenuBarPreview(showIcon: icon, stacked: style != "line")
                Picker(L("Yerleşim", "Layout"), selection: $style) {
                    Text(L("İki satır", "Two lines")).tag("stacked")
                    Text(L("Tek satır", "One line")).tag("line")
                }
                .pickerStyle(.segmented)
            } header: {
                SectionTitle(L("Önizleme", "Preview"))
            }
            SettingsSection("menuBar.system", title: L("Sistem", "System")) {
                ForEach([MenuBarItem.cpu, .ram, .gpu, .swap, .network, .disk, .battery]) { BarToggle(item: $0) }
            }
            SettingsSection("menuBar.other") {
                BarToggle(item: .ai)
                BarToggle(item: .market)
                if marketOn && !watchedMarkets.isEmpty {
                    Picker(L("Gösterilecek piyasa", "Market to show"), selection: $barMarketID) {
                        Text(L("İlk izlenen", "First watched")).tag("")
                        ForEach(watchedMarkets, id: \.self) { Text(verbatim: $0).tag($0) }
                    }
                }
                BarToggle(item: .currency)
                BarToggle(item: .weather)
            } header: {
                Text(L("Diğer", "Other"))
            } footer: {
                Footnote(claude || codex || gemini
                    ? L("AI limiti, açık sağlayıcılar arasında en çok dolmuş olanı gösterir. Döviz kuru, izlenen ilk kuru gösterir.",
                        "AI limit shows the fullest window among the providers you turned on. Exchange rate shows the first watched rate.")
                    : L("AI limitini göstermek için önce AI limitleri sayfasından bir sağlayıcı aç.",
                        "To show an AI limit, first turn on a provider on the AI Limits page."))
            }
            SettingsSection("menuBar.hider") {
                Toggle(L("Kalabalık simgeleri gizle", "Hide crowded icons"), isOn: $hider)
                Picker(L("Kendiliğinden gizle", "Hide again"), selection: $hiderDelay) {
                    Text(L("5 saniye sonra", "After 5 seconds")).tag(5)
                    Text(L("10 saniye sonra", "After 10 seconds")).tag(10)
                    Text(L("30 saniye sonra", "After 30 seconds")).tag(30)
                    Text(L("1 dakika sonra", "After 1 minute")).tag(60)
                    Text(L("Hiç", "Never")).tag(0)
                }
                .disabled(!hider)
                Button(L("Nasıl kullanılır?", "How does it work?")) { MenuBarHider.shared.showHint() }
                    .disabled(!hider)
            } header: {
                Text(L("Simgeleri gizle", "Hide icons"))
            } footer: {
                Footnote(L("Nabız'ın soluna bir ok ve ince bir çizgi gelir. ⌘ basılı tutup gizlemek istediğin simgeleri çizginin soluna sürükle; oka tıklayınca gizlenir ve geri gelir. Kapatınca her simge yerinde kalır.",
                           "An arrow and a thin line appear left of Nabız. Hold ⌘ and drag the icons you want to hide to the left of the line; clicking the arrow hides them and brings them back. Turning it off leaves every icon where it was."))
            }
            SettingsSection("menuBar.icon") {
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
            SettingsSection("panel.folding") {
                Toggle(L("Bölümler katlanabilsin", "Collapsible sections"), isOn: $collapsible)
                Toggle(L("Akordeon: aynı anda tek bölüm açık", "Accordion: one section open at a time"), isOn: $accordion)
                    .disabled(!collapsible)
            } header: {
                SectionTitle(L("Katlama", "Folding"))
            } footer: {
                Footnote(L("Paneldeki bir başlığa tıklayınca o bölüm açılır ya da kapanır. Kapalı bölümün başlığında kısa bir özet görünür.",
                           "Click a heading in the panel to open or close its section. A closed section shows a short summary in its heading."))
            }
            SettingsSection("panel.sections") {
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
            SettingsSection("panel.tools") {
                ForEach(ToolKind.allCases) { ToolSettingRow(kind: $0) }
            } header: {
                Text(L("Araçlar", "Tools"))
            } footer: {
                Footnote(L("Kapattığın araçlar paneldeki ızgaradan kalkar.", "Tools you turn off leave the panel's grid."))
            }
            SettingsSection("panel.apps", title: L("Uygulama listesi", "App list")) {
                ValueStepper(L("Bellekte", "By memory"), L("ilk \(memoryCount)", "top \(memoryCount)"), value: $memoryCount, in: 1...10)
                ValueStepper(L("İşlemcide", "By CPU"), L("ilk \(cpuCount)", "top \(cpuCount)"), value: $cpuCount, in: 1...10)
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

private struct AdvicePage: View {
    @AppStorage(Prefs.showAdvice) private var showAdvice = true
    @State private var hidden = AdviceSnooze.count

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .advice) }
            SettingsSection("advice.show") {
                Toggle(L("Panelde önerileri göster", "Show suggestions in the panel"), isOn: $showAdvice)
            } footer: {
                Footnote(L("Paneldeki bir öneriye sağ tıklayınca onu bir günlüğüne, bir haftalığına ya da tamamen gizleyebilirsin. Gizlenen öneri daha ciddileşirse yine görünür.",
                           "Right-click a suggestion in the panel to hide it for a day, a week or for good. A hidden suggestion shows again if it gets more serious."))
            }
            SettingsSection("advice.kinds") {
                ForEach(AdviceKind.allCases) { AdviceKindRow(kind: $0) }
            } header: {
                Text(L("Ne zaman öneri gelsin", "When to suggest"))
            }
            .disabled(!showAdvice)
            SettingsSection("advice.security") {
                ForEach(SecurityCheck.Kind.allCases, id: \.self) { SecurityWatchRow(kind: $0) }
            } header: {
                Text(L("Güvenlik kontrolleri", "Security checks"))
            } footer: {
                Footnote(L("Güvenlik duvarı macOS'ta zaten kapalı gelir; evde modemin arkasında çoğu zaman gerekmez. Ortak Wi‑Fi'da sık çalışıyorsan aç.",
                           "The firewall ships off on macOS and is rarely needed behind a home router. Turn it on here if you often work on public Wi‑Fi."))
            }
            .disabled(!showAdvice || !AdviceKind.security.isOn)
            SettingsSection("advice.hidden") {
                HStack {
                    Text(hidden == 0 ? L("Gizlenen öneri yok", "No hidden suggestions") : L("\(hidden) öneri gizli", "\(hidden) hidden"))
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    Button(L("Hepsini geri getir", "Show them again")) {
                        AdviceSnooze.clear()
                        hidden = 0
                        SettingsWindow.monitor?.adviceSettingsChanged()
                    }
                    .disabled(hidden == 0)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { hidden = AdviceSnooze.count }
    }
}

private struct AdviceKindRow: View {
    let kind: AdviceKind
    @AppStorage private var on: Bool

    init(kind: AdviceKind) {
        self.kind = kind
        _on = AppStorage(wrappedValue: true, kind.prefKey)
    }

    var body: some View {
        Toggle(isOn: Binding(get: { on }, set: { on = $0; SettingsWindow.monitor?.adviceSettingsChanged() })) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(verbatim: kind.title)
                Text(verbatim: kind.detail).font(Theme.small).foregroundStyle(Theme.textMuted)
            }
        }
    }
}

private struct SecurityWatchRow: View {
    let kind: SecurityCheck.Kind
    @AppStorage private var on: Bool

    init(kind: SecurityCheck.Kind) {
        self.kind = kind
        _on = AppStorage(wrappedValue: kind.watchedByDefault, kind.prefKey)
    }

    var body: some View {
        let state = SettingsWindow.monitor?.security.first { $0.kind == kind }
        Toggle(isOn: Binding(get: { on }, set: { on = $0; SettingsWindow.monitor?.adviceSettingsChanged() })) {
            HStack {
                Text(verbatim: SecurityCheck(kind: kind, on: true).title)
                Spacer()
                if let state {
                    Text(state.on ? L("açık", "on") : L("kapalı", "off"))
                        .font(Theme.small).foregroundStyle(state.on ? Theme.textMuted : Theme.warning.mark)
                }
            }
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
            SettingsSection("markets.panel") {
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
                SectionTitle(L("Panelde", "In the panel"))
            }

            PriceAlertsSection(watched: watchedIDs)

            SettingsSection("markets.catalog") {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textMuted)
                    TextField(L("Ara", "Search"), text: $query, prompt: Text(L("Ara: BTC, TSLA, GOLD…", "Search: BTC, TSLA, GOLD…")))
                        .textFieldStyle(.plain)
                        .labelsHidden()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textMuted) }
                            .buttonStyle(.plain)
                    }
                }
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

private struct WeatherPage: View {
    @AppStorage(Prefs.showWeather) private var show = true
    @AppStorage(Prefs.barWeather) private var bar = false
    @AppStorage(Prefs.weatherUnit) private var unit = "system"
    @AppStorage(Prefs.weatherDetails) private var details = false
    @AppStorage(Prefs.weatherPlace) private var placeData = Data()
    @State private var query = ""
    @State private var results: [WeatherStore.Place] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    private let store = WeatherStore.shared

    var body: some View {
        let place = WeatherStore.place
        Form {
            Section {} header: { PageHeader(page: .weather) }
            SettingsSection("weather.main") {
                Toggle(L("Panelde göster", "Show in the panel"), isOn: $show)
                Toggle(L("Nem ve rüzgâr satırı", "Humidity and wind row"), isOn: $details)
                Toggle(L("Menü çubuğunda sıcaklık", "Temperature in the menu bar"), isOn: $bar)
                Picker(L("Birim", "Unit"), selection: $unit) {
                    Text(L("Sistem", "System")).tag("system")
                    Text(verbatim: "°C").tag("c")
                    Text(verbatim: "°F").tag("f")
                }
            }
            SettingsSection("weather.city") {
                LabeledContent(L("Şu an", "Now")) {
                    if let report = store.report, report.place == place {
                        Text(verbatim: "\(report.place.name) · \(Format.degrees(report.temperature)) · \(WeatherCode.title(report.code))")
                            .foregroundStyle(Theme.textMuted)
                    } else {
                        Text(verbatim: place?.name ?? L("Saat diliminden bulunuyor…", "Finding it from your time zone…"))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                TextField(L("Şehir ara", "Search for a city"), text: $query)
                    .onChange(of: query) { _, text in search(text) }
                if searching {
                    ProgressView().controlSize(.small)
                }
                ForEach(results) { result in
                    Button {
                        WeatherStore.choose(result)
                        query = ""
                        results = []
                    } label: {
                        LabeledContent {
                            if result == place { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        } label: {
                            Text(verbatim: result.name)
                            if !result.detail.isEmpty { Text(verbatim: result.detail) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if place != nil {
                    Button(L("Saat dilimindeki şehri kullan", "Use the city of my time zone")) { WeatherStore.choose(nil) }
                }
            } header: {
                SectionTitle(L("Şehir", "City"))
            } footer: {
                Footnote(L("Konum izni istenmez: hava durumu seçtiğin şehrin koordinatlarıyla Open-Meteo'dan (ücretsiz, hesapsız) alınır. Panelde bir satıra tıklamak Hava uygulamasını açar.",
                           "No location permission: the forecast comes from Open-Meteo (free, no account) for the coordinates of the city you pick. Clicking a row in the panel opens the Weather app."))
            }
        }
        .formStyle(.grouped)
        .onAppear { store.refreshIfNeeded() }
        .onChange(of: unit) { _, _ in store.refreshIfNeeded() }
        .onChange(of: placeData) { _, _ in store.refreshIfNeeded() }
    }

    /// Waits for a pause in typing, then looks the name up.
    private func search(_ text: String) {
        searchTask?.cancel()
        guard text.trimmingCharacters(in: .whitespaces).count >= 2 else { results = []; searching = false; return }
        searching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let found = await WeatherStore.search(text)
            guard !Task.isCancelled else { return }
            results = found
            searching = false
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
            SettingsSection("currency.base") {
                Picker(L("Ana para birimi", "Main currency"), selection: $base) {
                    ForEach(codes, id: \.self) { Text(verbatim: label(for: $0)).tag($0) }
                }
            } footer: {
                Footnote(L("Kurlar bu para biriminde gösterilir; hızlı hesapta hedef yazılmazsa buna çevrilir.",
                       "Rates are shown in this currency; quick conversions go to it when no target is given."))
            }
            SettingsSection("currency.watched", title: L("Panelde izlenenler", "Watched in the panel")) {
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
    @AppStorage(Prefs.aiAsk) private var ask = true
    @AppStorage(Prefs.aiEngine) private var engine = AIEngine.auto.rawValue
    @State private var efforts: [String: String] = [:]
    @AppStorage(Prefs.aiHotkey) private var hotkey = true
    @AppStorage(Prefs.dictationHotkey) private var dictationHotkey = false
    @State private var models: [String: String] = [:]
    private let engines = AIEngines.shared

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .ai) }
            SettingsSection("ai.ask") {
                Toggle(L("Launcher'da AI'a sor", "Ask AI in the launcher"), isOn: $ask)
                Picker(L("Kim cevaplasın", "Who answers"), selection: $engine) {
                    ForEach(AIEngine.allCases) { option in
                        Text(verbatim: label(option)).tag(option.rawValue)
                    }
                }
                .disabled(!ask)
                if let current = engines.resolve(AIEngine(rawValue: engine) ?? .auto) {
                    let options = engines.models(for: current)
                    if options.count > 1 {
                        Picker(L("\(current.title) modeli", "\(current.title) model"), selection: modelBinding(current)) {
                            ForEach(options) { Text(verbatim: $0.title).tag($0.id) }
                        }
                        .disabled(!ask)
                    }
                    let levels = engines.efforts(for: current, model: current.chosenModel)
                    if !levels.isEmpty {
                        Picker(L("Düşünme", "Thinking"), selection: effortBinding(current)) {
                            if !levels.contains(where: \.recommended) { Text(L("Otomatik", "Auto")).tag("") }
                            ForEach(levels) { level in
                                Text(verbatim: level.title + (level.recommended ? L(" (önerilen)", " (recommended)") : "")
                                     + (level.warning.map { " · \($0)" } ?? "")).tag(level.id)
                            }
                        }
                        .disabled(!ask)
                    }
                }
                HotKeyRow(title: L("Hızlı soru", "Quick question"), shortcut: .ai, enabled: $hotkey)
                    .disabled(!ask)
            } header: {
                SectionTitle(L("AI'a sor", "Ask AI"))
            } footer: {
                Footnote(L("Launcher'da ? yaz ya da \(HotKey.label(.ai)) tuşla ve sor; seçili ya da kopyalanan metni özetle, çevir, düzelt. Claude, Codex ve Gemini bu Mac'te kurulu CLI'leri üzerinden, kendi aboneliğinle cevaplar; metin o şirkete gider. Cihaz içi model ücretsizdir ve metin bu Mac'ten çıkmaz. Daha uzun düşünme daha iyi ama daha yavaş cevaplar ve limitini daha hızlı harcar.",
                           "Type ? in the launcher or press \(HotKey.label(.ai)) and ask; summarise, translate or fix selected or copied text. Claude, Codex and Gemini answer through their CLIs on this Mac, with your own subscription; the text goes to that company. The on-device model is free and the text never leaves this Mac. Longer thinking answers better but slower and uses your limit faster."))
            }
            .onAppear { engines.refreshIfNeeded() }
            AICommandsSection()
        }
        .formStyle(.grouped)
    }

    private func effortBinding(_ engine: AIEngine) -> Binding<String> {
        Binding(get: { efforts[engine.rawValue] ?? engines.effectiveEffort(for: engine, model: engine.chosenModel) }, set: { level in
            engine.setChosenEffort(level)
            efforts[engine.rawValue] = level
        })
    }

    private func modelBinding(_ engine: AIEngine) -> Binding<String> {
        Binding(get: { models[engine.rawValue] ?? engine.chosenModel }, set: { model in
            engine.setChosenModel(model)
            models[engine.rawValue] = model
        })
    }

    private func label(_ option: AIEngine) -> String {
        if option == .auto {
            return engines.resolved.map { "\(option.title) (\($0.title))" } ?? option.title
        }
        guard engines.searched || option == .onDevice, let problem = engines.problem(option) else { return option.title }
        return "\(option.title) — \(problem)"
    }
}

private struct AIChatPage: View {
    @AppStorage(Prefs.aiHistory) private var history = true
    @AppStorage(Prefs.aiChatHotkey) private var chatHotkey = true
    @AppStorage(Prefs.aiClaudeSessions) private var claudeSessions = true
    @AppStorage(Prefs.aiNotify) private var notify = true
    @AppStorage(Prefs.aiSuggest) private var suggest = true
    @State private var confirmClear = false
    private let chats = AIChatStore.shared

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .aiChat) }
            SettingsSection("aiChat.open") {
                HStack {
                    Button { AIChatWindow.show() } label: { Label(L("Sohbet penceresini aç", "Open the chat window"), systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
                HotKeyRow(title: L("Sohbet penceresi", "Chat window"), shortcut: .aiChat, enabled: $chatHotkey)
            } header: {
                SectionTitle(L("Sohbet", "Chat"))
            } footer: {
                Footnote(L("Panelde AI → Sohbet, araçlarda \"AI sohbet\", menü çubuğu simgesine sağ tık ya da başlatıcıda \"sohbet\" ile de açılır.",
                           "Also from the panel (AI → Chat), the \"AI chat\" tool, a right-click on the menu bar item, or \"chat\" in the launcher."))
            }
            SettingsSection("aiChat.answers") {
                Toggle(L("Cevap gelince bildir", "Notify when an answer arrives"), isOn: $notify)
                Toggle(L("Claude sohbeti kendisi hatırlasın", "Let Claude remember the chat itself"), isOn: $claudeSessions)
                Toggle(L("Sonraki mesajı öner (⇥ ile al)", "Suggest the next message (⇥ to take it)"), isOn: $suggest)
                    .disabled(OnDeviceAI.problem != nil)
                    .help(OnDeviceAI.problem ?? L("Apple'ın cihaz içi modeli yazar; ücretsiz, metin bu Mac'ten çıkmaz.",
                                                   "Apple's on-device model writes it; free, and the text stays on this Mac."))
            } header: {
                SectionTitle(L("Cevaplar", "Answers"))
            } footer: {
                Footnote(L("Bildirim yalnızca başka bir uygulamadayken ya da başka bir sohbete bakarken gelir; tıklayınca sohbet açılır. Claude sohbeti hatırlarsa her mesajda yalnızca yeni mesaj gider: daha hızlı ve limitten daha az yer. Bunun için Claude, sohbetin bir kopyasını kendi klasöründe (~/.claude) tutar; kapatırsan her mesajda tüm sohbet yeniden gönderilir.",
                           "The notification comes only while you're in another app or another chat; clicking it opens the chat. When Claude remembers the chat, only your new message goes out each time: faster, and lighter on your limit. For that Claude keeps a copy of the chat in its own folder (~/.claude); turn it off to send the whole chat every time."))
            }
            SettingsSection("aiChat.history") {
                Toggle(L("Sohbetleri sakla", "Keep chats"), isOn: Binding(get: { history }, set: { on in
                    history = on
                    if !on { chats.deleteAll() }
                }))
                HStack {
                    Text(L("\(chats.conversations.filter { !$0.messages.isEmpty }.count) sohbet", "\(chats.conversations.filter { !$0.messages.isEmpty }.count) chats"))
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    Button(L("Tümünü sil…", "Delete all…"), role: .destructive) { confirmClear = true }
                        .disabled(chats.conversations.isEmpty)
                }
            } footer: {
                Footnote(L("Sohbetler bu Mac'te, pano geçmişiyle aynı anahtarla şifreli tutulur. Kapatırsan hepsi silinir.",
                           "Chats are kept on this Mac, encrypted with the same key as the clipboard history. Turning this off deletes them."))
            }
            .onAppear { chats.loadIfNeeded() }
            .confirmationDialog(L("Tüm sohbetler silinsin mi?", "Delete all chats?"), isPresented: $confirmClear) {
                Button(L("Tümünü sil", "Delete all"), role: .destructive) { chats.deleteAll() }
            } message: {
                Text(L("Bu geri alınamaz.", "This can't be undone."))
            }
        }
        .formStyle(.grouped)
    }
}

private struct DictationPage: View {
    @AppStorage(Prefs.dictationHotkey) private var dictationHotkey = false
    @AppStorage(Prefs.dictationLanguage) private var dictationLanguage = "system"

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .dictation) }
            SettingsSection("dictation.main") {
                HotKeyRow(title: L("Dikte", "Dictation"), shortcut: .dictation, enabled: $dictationHotkey)
                Picker(L("Dikte dili", "Dictation language"), selection: $dictationLanguage) {
                    Text(L("Uygulama dili", "App language")).tag("system")
                    Text(verbatim: "Türkçe").tag("tr")
                    Text(verbatim: "English").tag("en")
                }
            } header: {
                SectionTitle(L("Dikte", "Dictation"))
            } footer: {
                Footnote(L("Kısayola bas, konuş, yine bas: söylediklerin imlecin olduğu yere yazılır. macOS dili biliyorsa ses bu Mac'ten çıkmaz. Menü çubuğu simgesine sağ tıklayıp \"Dikte et\" de diyebilirsin.",
                           "Press the shortcut, speak, press it again: your words are typed where the cursor is. When macOS knows the language the audio never leaves this Mac. Or right-click the menu bar item → \"Dictate\"."))
            }
        }
        .formStyle(.grouped)
    }
}

private struct AILimitsPage: View {
    @AppStorage("ai.claude") private var claude = false
    @AppStorage("ai.codex") private var codex = false
    @AppStorage("ai.gemini") private var gemini = false
    @AppStorage(Prefs.aiRemaining) private var remaining = true
    @State private var adding: AIProvider?
    @State private var newNickname = ""
    @State private var folderMessage = ""
    private let store = AILimitsStore.shared

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .aiLimits) }
            SettingsSection("aiLimits.providers") {
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
            SettingsSection("aiLimits.accounts") {
                ForEach(store.accounts) { AIAccountRow(account: $0) }
                HStack(spacing: Theme.Spacing.m) {
                    Menu(L("Hesap ekle", "Add an account")) {
                        ForEach(AIProvider.allCases) { provider in
                            Button(provider.name) {
                                newNickname = ""
                                adding = provider
                            }
                        }
                    }
                    .fixedSize()
                    Button(L("Klasör ekle…", "Add a folder…")) { pickFolder() }
                    if !folderMessage.isEmpty {
                        Text(verbatim: folderMessage).font(Theme.small).foregroundStyle(Theme.textMuted)
                    }
                }
            } header: {
                Text(L("Hesaplar", "Accounts"))
            } footer: {
                Footnote(L("Aynı sağlayıcıdan ikinci bir hesap için Hesap ekle'yi seç, takma ad ver ve açılan Terminal'de o hesapla giriş yap; varsayılan oturumun olduğu gibi kalır. Nabız ~/.claude-*, ~/.codex-* ve ~/.gemini-* klasörlerindeki oturumları kendisi bulur, iki yerde açık aynı hesabı bir kez gösterir. Takma ad yoksa panelde e-posta görünür.",
                           "For a second account of the same provider, choose Add an account, give it a nickname and sign in with that account in the Terminal that opens; your default sign-in stays as it is. Nabız finds the sign-ins in ~/.claude-*, ~/.codex-* and ~/.gemini-* folders by itself and shows an account signed in twice only once. Without a nickname the panel shows the e-mail."))
            }
            .alert(L("\(adding?.shortName ?? "") hesabı ekle", "Add a \(adding?.shortName ?? "") account"), isPresented: addingShown) {
                TextField(L("Takma ad (ör. İş)", "Nickname (e.g. Work)"), text: $newNickname)
                Button(L("Terminal'de giriş yap", "Sign in in Terminal")) {
                    if let adding { store.addAccount(adding, nickname: newNickname) }
                }
                Button(L("Vazgeç", "Cancel"), role: .cancel) {}
            } message: {
                Text(L("Terminal açılır, giriş tarayıcıda yapılır. Bitince hesap burada ve panelde görünür.",
                       "Terminal opens and you sign in in the browser. Then the account shows up here and in the panel."))
            }
            SettingsSection("aiLimits.display") {
                Picker(L("Göster", "Show"), selection: $remaining) {
                    Text(L("Kalan", "What's left")).tag(true)
                    Text(L("Kullanılan", "What's used")).tag(false)
                }
                .pickerStyle(.segmented)
            } footer: {
                Footnote(L("Örnek: haftalık limitin %94'ü kullanıldıysa \"%6 kaldı\" ya da \"%94\" yazar. Çubuk da aynısını gösterir; kalanı seçersen harcadıkça kısalır.",
                           "Example: with 94% of the weekly limit used it reads \"6% left\" or \"94%\". The bar shows the same; with what's left it shrinks as you use it."))
            }
            SettingsSection("aiLimits.grok") {
                LabeledContent("Grok") {
                    Text(L("Herkese açık limit verisi yok", "No public limit data")).foregroundStyle(Theme.textMuted)
                }
            } footer: {
                Footnote(L("xAI kullanım limitlerini okuyacak bir yol sunduğunda eklenecek.", "Will be added once xAI offers a way to read usage limits."))
            }
            SettingsSection("aiLimits.refresh") {
                HStack {
                    Button(L("Şimdi yenile", "Refresh now")) { store.refreshIfNeeded(force: true) }
                        .disabled(store.enabled.isEmpty || store.loading)
                    if store.loading { ProgressView().controlSize(.small) }
                }
            }
        }
        .formStyle(.grouped)
        // A sign-in finished in Terminal shows up as soon as you come back.
        .onAppear { store.refreshIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshIfNeeded()
        }
        .onChange(of: [claude, codex, gemini]) { store.refreshIfNeeded() }
    }

    private var addingShown: Binding<Bool> {
        Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.message = L("CLI'nin klasörünü seç (CLAUDE_CONFIG_DIR, CODEX_HOME ya da GEMINI_CLI_HOME).",
                          "Choose the CLI's folder (CLAUDE_CONFIG_DIR, CODEX_HOME or GEMINI_CLI_HOME).")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderMessage = store.addFolder(url.path).map { L("\($0.shortName) hesabı eklendi", "\($0.shortName) account added") }
            ?? L("Bu klasörde oturum yok", "No sign-in in this folder")
    }

    private func binding(_ provider: AIProvider) -> Binding<Bool> {
        switch provider {
        case .claude: $claude
        case .codex: $codex
        case .gemini: $gemini
        }
    }
}

/// One account in Settings: who it is and where it lives, a nickname for the panel, and whether it is shown.
private struct AIAccountRow: View {
    let account: AIAccount
    private let store = AILimitsStore.shared

    var body: some View {
        let status = store.statuses.first { $0.id == account.id }
        LabeledContent {
            HStack(spacing: Theme.Spacing.m) {
                TextField(L("Takma ad", "Nickname"), text: nickname, prompt: Text(L("Takma ad", "Nickname")))
                    .labelsHidden()
                    .frame(width: 120)
                Toggle(L("Göster", "Show"), isOn: shown).labelsHidden().toggleStyle(.switch)
            }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(verbatim: [account.provider.name, status?.plan].compactMap { $0 }.joined(separator: " · "))
                Text(verbatim: store.details(account, email: status?.email))
                    .font(Theme.small).foregroundStyle(Theme.textMuted).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private var nickname: Binding<String> {
        Binding(get: { store.nickname(account) }, set: { store.setNickname($0, for: account) })
    }

    private var shown: Binding<Bool> {
        Binding(get: { store.isShown(account) }, set: { store.setShown($0, account) })
    }
}

/// MCP: AI apps use Nabız's tools through `Nabiz --mcp`.
private struct MCPPage: View {
    @AppStorage(Prefs.mcpEnabled) private var enabled = false
    @AppStorage(Prefs.mcpCommands) private var commands = true
    @AppStorage(Prefs.mcpNotes) private var notes = true
    @AppStorage(Prefs.mcpClipboard) private var clipboard = false
    @State private var message = ""
    @State private var working = false
    private let server = MCPServer.shared

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .mcp) }
            SettingsSection("mcp.server") {
                Toggle(L("MCP sunucusunu aç", "Turn on the MCP server"), isOn: $enabled)
                if enabled {
                    LabeledContent(L("Durum", "Status")) {
                        Text(verbatim: status).foregroundStyle(server.running ? Theme.text : Theme.textMuted)
                    }
                }
            } footer: {
                Footnote(L("Açıkken AI uygulamaları Nabız'a yalnızca bu Mac'te ve senin kullanıcınla bağlanabilir. İnternete hiçbir şey açılmaz.",
                           "While it's on, AI apps can reach Nabız only on this Mac and as your user. Nothing is opened to the internet."))
            }
            SettingsSection("mcp.permissions") {
                LabeledContent(L("Her zaman", "Always")) {
                    Text(L("Sistem durumu, AI limitleri, takvim, hesap, piyasa, kur, bildirim", "System status, AI limits, calendar, maths, markets, rates, notifications"))
                        .foregroundStyle(Theme.textMuted).multilineTextAlignment(.trailing)
                }
                Toggle(L("Mac'te işlem yapsın", "Act on the Mac"), isOn: $commands)
                Toggle(L("Notları ve parçacıkları okuyup yazsın", "Read and write notes and snippets"), isOn: $notes)
                Toggle(L("Pano geçmişini okusun", "Read the clipboard history"), isOn: $clipboard)
            } header: {
                Text(L("Neleri kullanabilsin", "What it may use"))
            } footer: {
                Footnote(L("İşlemler: uygulama açma, pencere yerleştirme, ses, zamanlayıcı, odak modu, kendi komutların ve kestirmelerin. Yeniden başlatma, kapatma, çöpü boşaltma gibi geri alınamayanlar hiçbir zaman çalıştırılmaz. Pano geçmişinde şifre gibi şeyler olabilir; o yüzden kapalı başlar.",
                           "Actions: opening apps, placing windows, sound, timers, focus mode, your own commands and Shortcuts. Things that can't be undone, like restart, shut down or emptying the Trash, are never run. The clipboard history may hold things like passwords, so it starts off."))
            }
            .disabled(!enabled)
            SettingsSection("mcp.connect") {
                HStack {
                    Button(L("Claude Code'a ekle", "Add to Claude Code")) {
                        working = true
                        Task {
                            message = await MCPSetup.addToClaudeCode()
                            working = false
                        }
                    }
                    .disabled(working)
                    Button(L("Claude Desktop'a ekle", "Add to Claude Desktop")) { message = MCPSetup.addToClaudeDesktop() }
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                }
                if !message.isEmpty {
                    Text(verbatim: message).foregroundStyle(Theme.textMuted).textSelection(.enabled)
                }
                LabeledContent(L("Komut", "Command")) {
                    HStack {
                        Text(verbatim: MCPSetup.claudeCodeCommand).font(.system(.caption, design: .monospaced)).lineLimit(2)
                            .textSelection(.enabled).foregroundStyle(Theme.textMuted)
                        Button { copy(MCPSetup.claudeCodeCommand) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(TextButtonStyle(color: Theme.textMuted)).help(L("Kopyala", "Copy"))
                    }
                }
                LabeledContent(L("Diğer uygulamalar (JSON)", "Other apps (JSON)")) {
                    Button(L("JSON'u kopyala", "Copy JSON")) { copy(MCPSetup.desktopJSON) }
                }
            } header: {
                Text(L("Bağla", "Connect"))
            } footer: {
                Footnote(L("Cursor, Windsurf, VS Code gibi uygulamalarda MCP ayarlarına JSON'u yapıştır. Nabız kapalıysa AI uygulaması onu arka planda açar.",
                           "In Cursor, Windsurf, VS Code and others, paste the JSON into their MCP settings. If Nabız isn't running, the AI app starts it in the background."))
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
    }

    private var status: String {
        guard server.running else { return L("Başlatılamadı", "Couldn't start") }
        var parts = [L("Hazır", "Ready")]
        if let client = server.lastClient { parts.append(L("son bağlanan: \(client)", "last connected: \(client)")) }
        if let call = server.lastCall {
            parts.append("\(call.tool) · " + call.at.formatted(.relative(presentation: .named).locale(Format.locale)))
        }
        return parts.joined(separator: " · ")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        message = L("Kopyalandı.", "Copied.")
    }
}

/// The calendar: on/off (macOS asks for access), which calendars, and the heads-up.
private struct CalendarPage: View {
    @AppStorage(Prefs.calendarEnabled) private var enabled = false
    @AppStorage(Prefs.calendarHidden) private var hidden = ""
    @AppStorage(Prefs.calendarAlert) private var alert = true
    private let agenda = CalendarAgenda.shared

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .calendar) }
            SettingsSection("calendar.main") {
                Toggle(L("Takvimi göster", "Show the calendar"), isOn: $enabled)
                if enabled && agenda.denied {
                    HStack {
                        Text(L("Nabız'ın takvim izni kapalı.", "Nabız has no calendar access."))
                        Spacer()
                        Button(L("İzni aç…", "Allow…")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                        }
                    }
                }
                Toggle(L("Toplantıdan 1 dk önce bildir", "Notify 1 min before a meeting"), isOn: $alert).disabled(!enabled)
            } footer: {
                Footnote(L("Panelde bugünün kalan etkinlikleri görünür; görüntülü toplantı bağlantısı (Zoom, Meet, Teams, Webex, FaceTime…) olana tıklayınca katılırsın. Başlatıcıda \"takvim\" ya da \"katıl\" yaz. Takvim yalnızca bu Mac'te okunur.",
                           "The panel shows what's left today; click one with a call link (Zoom, Meet, Teams, Webex, FaceTime…) to join. Type \"calendar\" or \"join\" in the launcher. The calendar is read only on this Mac."))
            }
            if enabled && agenda.authorized {
                SettingsSection("calendar.calendars") {
                    ForEach(agenda.calendars, id: \.id) { calendar in
                        Toggle(isOn: Binding(get: { !hiddenSet.contains(calendar.id) }, set: { show in
                            var set = hiddenSet
                            if show { set.remove(calendar.id) } else { set.insert(calendar.id) }
                            hidden = set.sorted().joined(separator: ",")
                            agenda.reload()
                        })) {
                            HStack(spacing: Theme.Spacing.s) {
                                Circle().fill(calendar.color).frame(width: 8, height: 8)
                                Text(verbatim: calendar.title)
                            }
                        }
                    }
                } header: {
                    Text(L("Takvimler", "Calendars"))
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { agenda.update(); agenda.reload() }
    }

    private var hiddenSet: Set<String> { Set(hidden.split(separator: ",").map(String.init)) }
}

private struct AboutPage: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
            Text(verbatim: "Nabız").font(Theme.title).foregroundStyle(Theme.text)
            Text(verbatim: L("Sürüm", "Version") + " " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"))
                .font(Theme.small).foregroundStyle(Theme.textMuted)
            UpdateRow()
            Text(L("Mac'inin nabzını menü çubuğunda tutar. Açık kaynak, GPLv3 lisansı.",
                   "Keeps your Mac's pulse in the menu bar. Open source, GPLv3 license."))
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

/// A stepper laid out like System Settings: the name on the left, the value and the arrows on the right.
private struct ValueStepper: View {
    let title: String
    let value: String
    @Binding var number: Int
    let range: ClosedRange<Int>
    let step: Int

    init(_ title: String, _ value: String, value number: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1) {
        self.title = title
        self.value = value
        _number = number
        self.range = range
        self.step = step
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(verbatim: value).monospacedDigit()
                Stepper(title, value: $number, in: range, step: step).labelsHidden()
            }
        }
    }
}

/// The first section heading under a page header. A grouped form draws that one small and grey, unlike the
/// rest, so it is styled by hand to match the other headings.
private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: text).font(Theme.bodyStrong).foregroundStyle(Theme.text)
            .padding(.top, Theme.Spacing.m)
    }
}

/// A form footer, left-aligned like System Settings.
struct Footnote: View {
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
struct PageHeader: View {
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
        SettingsSection("markets.alerts") {
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
    @AppStorage(Prefs.barAnimate) private var barAnimate = true

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .appearance) }
            SettingsSection("appearance.accent") {
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
                SectionTitle(L("Vurgu rengi", "Accent colour"))
            } footer: {
                Footnote(L("Göstergeler, düğmeler, açık araçlar, başlatıcı ve grafikler bu rengi alır. Turuncu ve kırmızı uyarılar için ayrıldı; çok açık bir renk seçersen yazılar zor okunabilir.",
                           "Meters, buttons, active tools, the launcher and charts take this colour. Orange and red are kept for warnings; a very light colour can make text hard to read."))
            }
            SettingsSection("appearance.theme", title: L("Tema", "Theme")) {
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
            SettingsSection("appearance.text", title: L("Yazı", "Text")) {
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
            SettingsSection("appearance.panel", title: L("Panel", "Panel")) {
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
            SettingsSection("appearance.menuBar") {
                Toggle(L("Değerleri renklendir", "Colour the values"), isOn: $barColors)
                Toggle(L("Değişen rakamları kaydır", "Roll changing digits"), isOn: $barAnimate)
            } header: {
                Text(L("Menü çubuğu", "Menu bar"))
            } footer: {
                Footnote(L("Dikkat isteyen değer turuncu ya da kırmızı olur (yoğun CPU, sıkışık bellek, azalan pil, biten AI limiti); bol kalan AI limiti yeşil, piyasalar yükselişte yeşil, düşüşte kırmızı. Her şey yolundaysa menü çubuğu sade kalır. Simge biçimi Menü çubuğu sayfasında.",
                           "A value that needs attention turns orange or red (busy CPU, tight memory, low battery, an AI limit running out); an AI limit with plenty left is green, markets go green when up and red when down. When all is well the menu bar stays plain. The icon style is on the Menu Bar page."))
            }
            SettingsSection("appearance.reset") {
                Button(L("Görünümü sıfırla", "Reset appearance")) {
                    for key in [Prefs.accentColor, Prefs.customAccent, Prefs.panelStyle, Prefs.panelWidth, Prefs.textSize, Prefs.fontDesign,
                                Prefs.density, Prefs.meterStyle, Prefs.appearanceMode, Prefs.barColors, Prefs.barAnimate] {
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
            SettingsSection("schedules.list") {
                if scheduler.tasks.isEmpty {
                    Text(L("Henüz görev yok. Aşağıdan hazır bir tane ekle ya da kendin oluştur.",
                           "No tasks yet. Add a ready-made one below, or make your own."))
                        .foregroundStyle(Theme.textMuted)
                }
                ForEach(scheduler.tasks) { TaskRow(task: $0) }
            } header: {
                SectionTitle(L("Görevler", "Tasks"))
            } footer: {
                Footnote(L("Görev seçtiğin saatte kendiliğinden çalışır ve kısa bir bildirim gönderir. Mac o saatte uykudaysa 6 saat içinde uyanınca telafi edilir; daha geç olursa bir sonraki güne kalır.",
                           "A task runs on its own at the time you set and posts a short notification. If the Mac was asleep, it catches up within 6 hours of waking; later than that it waits for its next day."))
            }
            SettingsSection("schedules.add", title: L("Ekle", "Add")) {
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
            SettingsSection("launcher.main") {
                Toggle(L("⌃⌥Boşluk ile aç", "Open with ⌃⌥Space"), isOn: $hotkey)
                Toggle(L("Uygulamaları ara", "Search apps"), isOn: $apps)
                Toggle(L("Pano öğelerini göster", "Show clipboard items"), isOn: $clips)
                Button(L("Başlatıcıyı aç", "Open the launcher")) { LauncherPanel.shared.show() }
            } footer: {
                Footnote(L("Yaz: uygulama adı, komut (kilitle, uyut, sol yarı…), hesap (12*4, 100 usd, 5 km mi), \"25 dk\" zamanlayıcı ya da \"g kelime\" ile web araması. ↑↓ seç, ↩ çalıştır, ⌘↩ ikinci işlem, esc kapat.",
                           "Type an app name, a command (lock, sleep, left half…), maths (12*4, 100 usd, 5 km mi), \"25 min\" for a timer or \"g words\" to search the web. ↑↓ to pick, ↩ to run, ⌘↩ for the second action, esc to close."))
            }
            SettingsSection("launcher.quicklinks") {
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
            BindingsSection()
            SettingsSection("launcher.aiCommands") {
                HStack {
                    Text(L("Kendi AI komutların", "Your own AI commands"))
                    Spacer()
                    Button(L("Ayarlar → AI'da", "In Settings → AI")) { SettingsWindow.show(.ai) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ExtensionsPage: View {
    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .extensions) }
            ExtensionsSection()
            DownloadSection()
        }
        .formStyle(.grouped)
    }
}

/// Launcher rows given their own shortcut or alias (⌘K in the launcher → Set a shortcut / Set an alias).
private struct BindingsSection: View {
    private let bindings = ItemBindings.shared

    var body: some View {
        SettingsSection("launcher.bindings") {
            if bindings.all.isEmpty {
                Text(L("Henüz yok.", "None yet.")).foregroundStyle(Theme.textMuted)
            }
            ForEach(bindings.all) { binding in
                HStack {
                    Text(verbatim: binding.title).lineLimit(1)
                    Spacer()
                    if let alias = binding.alias {
                        Button(alias) { bindings.askAlias(id: binding.id, title: binding.title) }
                            .buttonStyle(TextButtonStyle(color: Theme.textMuted))
                    }
                    if let combo = binding.combo {
                        Button(combo.label) { bindings.askCombo(id: binding.id, title: binding.title) }
                            .buttonStyle(TextButtonStyle(color: Theme.text)).monospacedDigit()
                    }
                    Button { bindings.remove(binding.id) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(TextButtonStyle(color: Theme.textMuted))
                        .help(L("Kaldır", "Remove"))
                }
            }
        } header: {
            Text(L("Kendi kısayolların ve takma adların", "Your shortcuts and aliases"))
        } footer: {
            Footnote(L("Başlatıcıda bir uygulama ya da komut seç, ⌘K'ya bas, \"Kısayol ata…\" ya da \"Takma ad ver…\" de. Kısayol her uygulamadayken çalışır; takma adı (örn. \"ss\") yazınca o satır en üste çıkar.",
                       "Pick an app or command in the launcher, press ⌘K and choose \"Set a shortcut…\" or \"Set an alias…\". The shortcut works from any app; type the alias (e.g. \"ss\") and that row comes first."))
        }
    }
}

/// The user's own AI prompts, run on the selected or copied text from the launcher or its ⌘K menu.
private struct AICommandsSection: View {
    @AppStorage(Prefs.aiAsk) private var aiAsk = true
    private let store = AICommandStore.shared

    var body: some View {
        SettingsSection("ai.commands") {
            ForEach(store.commands) { command in
                AICommandRow(command: Binding(get: { store.commands.first { $0.id == command.id } ?? command },
                                              set: { new in
                                                  if let index = store.commands.firstIndex(where: { $0.id == command.id }) { store.commands[index] = new }
                                              }))
            }
            HStack {
                Button {
                    store.commands.append(AICommand(name: L("Yeni komut", "New command"), prompt: ""))
                } label: { Label(L("Komut ekle", "Add a command"), systemImage: "plus") }
                Spacer()
                if store.commands.isEmpty {
                    Button(L("Örnekleri ekle", "Add examples")) { store.commands = AICommand.examples }
                }
            }
        } header: {
            Text(L("Kendi AI komutların", "Your own AI commands"))
        } footer: {
            Footnote(aiAsk
                ? L("Seçili metinde (yoksa son kopyaladığında) çalışır. Başlatıcıda \"AI: ad\" olarak ve ⌘K menüsünde çıkar; ⌘K ile kısayol da atayabilirsin. İstemde {text} yazdığın yere metin gelir.",
                    "Runs on the selected text (or the last thing you copied). Shows in the launcher as \"AI: name\" and in the ⌘K menu; give it a shortcut with ⌘K. {text} in the prompt is replaced by the text.")
                : L("AI'a sor kapalı; Ayarlar → AI'dan aç.", "Ask AI is off; turn it on in Settings → AI."))
        }
    }
}

private struct AICommandRow: View {
    @Binding var command: AICommand

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                TextField(L("Ad", "Name"), text: $command.name).labelsHidden()
                Button { AICommandStore.shared.commands.removeAll { $0.id == command.id } } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(TextButtonStyle(color: Theme.textMuted))
            }
            TextField(L("İstem: ne yapsın?", "Prompt: what should it do?"), text: $command.prompt, axis: .vertical)
                .labelsHidden()
                .lineLimit(2...5)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

/// Files, Shortcuts and scripts in the launcher.
private struct ExtensionsSection: View {
    @AppStorage(Prefs.launcherFiles) private var files = true
    @AppStorage(Prefs.launcherShortcuts) private var shortcuts = true
    private let extensions = Extensions.shared

    var body: some View {
        SettingsSection("extensions.files") {
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
        SettingsSection("extensions.downloads") {
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
    @AppStorage(Prefs.focusBlockSites) private var blockSites = false
    @AppStorage(Prefs.focusSites) private var sites = ""
    @State private var newSite = ""
    private let pomodoro = Pomodoro.shared

    private var siteList: [String] { SiteBlocker.shared.sites }

    /// "-" keeps an emptied list empty instead of going back to the defaults.
    private func setSites(_ list: [String]) { sites = list.isEmpty ? "-" : list.joined(separator: ",") }

    private func addSite() {
        guard let host = SiteBlocker.host(of: newSite)?.lowercased() else { return }
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if !siteList.contains(site) { setSites(siteList + [site]) }
        newSite = ""
    }

    var body: some View {
        Form {
            Section {} header: { PageHeader(page: .focus) }
            SettingsSection("focus.pomodoro") {
                ValueStepper(L("Odak", "Focus"), L("\(work) dk", "\(work) min"), value: $work, in: 5...120, step: 5)
                ValueStepper(L("Kısa mola", "Short break"), L("\(short) dk", "\(short) min"), value: $short, in: 1...30)
                ValueStepper(L("Uzun mola", "Long break"), L("\(long) dk", "\(long) min"), value: $long, in: 5...60, step: 5)
                ValueStepper(L("Uzun mola sıklığı", "Long break every"), L("\(every) blokta bir", "\(every) blocks"), value: $every, in: 2...8)
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
                SectionTitle("Pomodoro")
            } footer: {
                Footnote(L("Kalan süre menü çubuğunda görünür; her geçişte ses ve bildirim gelir. Başlatıcıda \"pomodoro\" yaz ya da Araçlar'daki Pomodoro'ya bas.",
                           "The time left shows in the menu bar; each change plays a sound and posts a notification. Type \"pomodoro\" in the launcher, or tap Pomodoro in Tools."))
            }
            SettingsSection("focus.hide") {
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
            SettingsSection("focus.sites") {
                Toggle(L("Odak modunda siteleri engelle", "Block websites during focus"), isOn: $blockSites)
                ForEach(siteList, id: \.self) { site in
                    HStack {
                        Image(systemName: "globe").foregroundStyle(Theme.textMuted).frame(width: Theme.menuIcon)
                        Text(verbatim: site)
                        Spacer()
                        Button { setSites(siteList.filter { $0 != site }) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(TextButtonStyle(color: Theme.textMuted))
                    }
                }
                .disabled(!blockSites)
                HStack {
                    TextField(L("Site ekle", "Add a site"), text: $newSite, prompt: Text(verbatim: "news.ycombinator.com"))
                        .labelsHidden()
                        .onSubmit(addSite)
                    Button(L("Ekle", "Add"), action: addSite).disabled(SiteBlocker.host(of: newSite) == nil || newSite.isEmpty)
                    Button(L("Varsayılanlar", "Defaults")) { sites = "" }.disabled(sites.isEmpty)
                }
                .disabled(!blockSites)
            } header: {
                Text(L("Odak modunda engellenen siteler", "Websites blocked during focus"))
            } footer: {
                Footnote(L("Safari, Chrome, Arc, Brave, Edge ve Vivaldi'de eklenti gerekmeden çalışır: öndeki sekme bu sitelerden biriyse kısa bir \"Odaktasın\" sayfasına döner. macOS her tarayıcı için bir kez izin ister. Alt alan adları da engellenir (youtube.com → m.youtube.com).",
                           "Works in Safari, Chrome, Arc, Brave, Edge and Vivaldi with no extension: if the tab in front is one of these sites it turns into a short \"You're focusing\" page. macOS asks once per browser. Subdomains are blocked too (youtube.com → m.youtube.com)."))
            }
            SettingsSection("focus.macos") {
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
            TextField(L("Ad", "Name"), text: binding(\.name)).frame(width: 88)
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
            SettingsSection("clipboard.history") {
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
            SettingsSection("clipboard.paste") {
                Toggle(L("↩ ile yapıştır", "Paste with ↩"), isOn: $autoPaste)
                AccessibilityRow()
            } header: {
                Text(L("Yapıştırma", "Pasting"))
            } footer: {
                Footnote(L("Seçtiğini, imlecin olduğu uygulamaya doğrudan yapıştırır. Bunun için macOS'in Erişilebilirlik izni gerekir; izin yoksa yalnızca kopyalanır.",
                           "Pastes what you pick straight into the app with the cursor. macOS needs Accessibility permission for this; without it, the item is only copied."))
            }
            SettingsSection("clipboard.excluded") {
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
            SettingsSection("clipboard.clear") {
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
            SettingsSection("snippets.list") {
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
            SettingsSection("windows.shortcuts") {
                Toggle(L("Pencere kısayolları", "Window shortcuts"), isOn: Binding(get: { hotkeys }, set: { on in
                    hotkeys = on
                    if on && !Paster.isTrusted { Paster.requestTrust() }
                }))
                AccessibilityRow()
            } footer: {
                Footnote(L("Öndeki pencereyi taşır ve boyutlandırır. Bunun için Erişilebilirlik izni gerekir. Kısayolları kapalı olsa da başlatıcıda \"sol yarı\", \"ortala\" yazarak kullanabilirsin.",
                           "Moves and resizes the front window. This needs Accessibility permission. With shortcuts off you can still type \"left half\" or \"center\" in the launcher."))
            }
            SettingsSection("windows.layouts", title: L("Yerleşimler", "Layouts")) {
                ForEach(WindowAction.allCases) { action in
                    LabeledContent {
                        Text(verbatim: action.shortcut ?? L("Başlatıcıdan", "From the launcher"))
                            .monospacedDigit().foregroundStyle(Theme.textMuted)
                    } label: {
                        Label(action.title, systemImage: action.symbol)
                    }
                }
            }
            CustomLayoutsSection()
        }
        .formStyle(.grouped)
    }
}

/// The user's own window positions, and sets of them applied together.
private struct CustomLayoutsSection: View {
    private let store = WindowLayouts.shared

    var body: some View {
        SettingsSection("windows.custom") {
            ForEach(store.layouts) { layout in
                WindowLayoutRow(layout: Binding(get: { store.layouts.first { $0.id == layout.id } ?? layout },
                                                set: { new in
                                                    if let index = store.layouts.firstIndex(where: { $0.id == layout.id }) { store.layouts[index] = new }
                                                }))
            }
            HStack {
                Menu {
                    Button(L("Boş yerleşim", "Blank layout")) { store.add(WindowLayout(name: L("Yeni yerleşim", "New layout"))) }
                    Divider()
                    ForEach(WindowLayout.presets) { preset in
                        Button(preset.name) {
                            var copy = preset
                            copy.id = UUID()
                            store.add(copy)
                        }
                    }
                } label: {
                    Label(L("Yerleşim ekle", "Add a layout"), systemImage: "plus")
                }
                .fixedSize()
                Spacer()
            }
        } header: {
            Text(L("Kendi yerleşimlerin", "Your own layouts"))
        } footer: {
            Footnote(L("Ekranın yüzdesiyle: sol ve üstten uzaklık, genişlik ve yükseklik. Bir uygulama seçersen o uygulamanın penceresi yerleşir (kapalıysa açılır). Aynı düzen adını verdiğin yerleşimler \"Düzen: ad\" komutuyla birlikte uygulanır. Hepsi başlatıcıda çıkar; ⌘K ile kısayol atayabilirsin.",
                       "As shares of the screen: distance from the left and top, width and height. Pick an app to place that app's window (it opens if needed). Layouts with the same set name run together as \"Set: name\". All of them show in the launcher; give one a shortcut with ⌘K."))
        }
    }
}

private struct WindowLayoutRow: View {
    @Binding var layout: WindowLayout

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                LayoutPreview(layout: layout)
                TextField(L("Ad", "Name"), text: $layout.name).labelsHidden()
                Button(L("Dene", "Try")) { WindowLayouts.shared.apply(layout) }
                    .help(L("Öndeki pencereye (şu an bu pencere) ya da seçtiğin uygulamaya uygular.", "Applies it to the front window (this one right now) or to the app you picked."))
                Button { WindowLayouts.shared.remove(layout.id) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(TextButtonStyle(color: Theme.textMuted))
            }
            HStack(spacing: Theme.Spacing.m) {
                PercentField(L("Sol", "Left"), value: $layout.x)
                PercentField(L("Üst", "Top"), value: $layout.y)
                PercentField(L("Genişlik", "Width"), value: $layout.width, range: 5...100)
                PercentField(L("Yükseklik", "Height"), value: $layout.height, range: 5...100)
            }
            HStack(spacing: Theme.Spacing.m) {
                Menu(layout.appName ?? L("Öndeki pencere", "Front window")) {
                    Button(L("Öndeki pencere", "Front window")) { layout.app = nil }
                    Divider()
                    ForEach(runningApps, id: \.bundle) { app in Button(app.name) { layout.app = app.bundle } }
                    Divider()
                    Button(L("Başka uygulama…", "Other app…")) { pickApp() }
                }
                .fixedSize()
                TextField(L("Düzen adı (isteğe bağlı)", "Set name (optional)"), text: $layout.set)
                    .labelsHidden()
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var runningApps: [(bundle: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url)?.bundleIdentifier else { return }
        layout.app = bundle
    }
}

/// "Left 0%" with a stepper, 5% at a time.
private struct PercentField: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...95

    init(_ title: String, value: Binding<Int>, range: ClosedRange<Int> = 0...95) {
        self.title = title
        _value = value
        self.range = range
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(verbatim: title).foregroundStyle(Theme.textMuted)
            Stepper(value: $value, in: range, step: 5) {
                Text(verbatim: L("%\(value)", "\(value)%")).monospacedDigit()
            }
        }
        .fixedSize()
    }
}

/// The screen as a small rectangle with the window drawn in it.
private struct LayoutPreview: View {
    let layout: WindowLayout

    var body: some View {
        let size = CGSize(width: 40, height: 26)
        let frame = layout.frame(in: CGRect(origin: .zero, size: size))
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.textMuted.opacity(0.6), lineWidth: 1)
            RoundedRectangle(cornerRadius: 2).fill(Theme.accent)
                .frame(width: max(frame.width - 2, 2), height: max(frame.height - 2, 2))
                .offset(x: frame.minX + 1, y: size.height - frame.maxY + 1)
        }
        .frame(width: size.width, height: size.height)
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
