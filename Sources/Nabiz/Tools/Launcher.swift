import AppKit
import Observation

/// One row in the launcher: an app, a command, a snippet, a clipboard item, a calculation or a web search.
struct LauncherItem: Identifiable {
    enum Icon {
        case symbol(String)
        case app(String)
        case clip(ClipItem)
    }

    /// Stable across searches, so recents can find the same item again ("app:/Applications/Safari.app", "cmd:lock").
    let id: String
    var icon: Icon
    var title: String
    var subtitle: String?
    /// Right-hand note: the kind, a shortcut, a time.
    var accessory: String?
    var primaryTitle: String
    var primary: @MainActor () -> Void
    var secondaryTitle: String?
    var secondary: (@MainActor () -> Void)?
    var clip: ClipItem?
    /// Recents only remember apps and commands, not one-off results.
    var remember = true
}

struct LauncherSection: Identifiable {
    let id: String
    let title: String
    var items: [LauncherItem]
}

/// What the launcher shows for the text typed: built fresh on every read so it follows clipboard, rates and apps live.
@MainActor
@Observable
final class LauncherModel {
    enum Mode { case all, clipboard }

    var mode: Mode = .all
    var text = "" {
        didSet { if text != oldValue { selection = 0 } }
    }
    var selection = 0
    /// The clipboard list was opened from the launcher, so Escape goes back to it instead of closing.
    var cameFromLauncher = false
    @ObservationIgnored private var lastPointer: CGPoint?

    /// True when the mouse is somewhere new since the last call (screen coordinates).
    func pointerMoved() -> Bool {
        let now = NSEvent.mouseLocation
        defer { lastPointer = now }
        guard let lastPointer else { return false }
        return lastPointer != now
    }

    /// Closes the launcher; set by the panel.
    @ObservationIgnored var close: () -> Void = {}

    func reset(mode: Mode, text: String = "") {
        lastPointer = NSEvent.mouseLocation
        self.mode = mode
        self.text = text
        selection = 0
    }

    var sections: [LauncherSection] {
        switch mode {
        case .clipboard: clipboardSections()
        case .all: allSections()
        }
    }

    var items: [LauncherItem] { sections.flatMap(\.items) }

    var selected: LauncherItem? {
        let items = items
        return items.isEmpty ? nil : items[min(selection, items.count - 1)]
    }

    func move(_ offset: Int) {
        let count = items.count
        guard count > 0 else { return }
        selection = (min(selection, count - 1) + offset + count) % count
    }

    func runPrimary() {
        guard let item = selected else { return }
        run(item, item.primary)
    }

    func runSecondary() {
        guard let item = selected, let secondary = item.secondary else { return }
        run(item, secondary)
    }

    func run(_ item: LauncherItem, _ action: @MainActor () -> Void) {
        if item.remember { Recents.add(item.id) }
        action()
    }

    // MARK: Clipboard mode

    private func clipboardSections() -> [LauncherSection] {
        let query = text.trimmingCharacters(in: .whitespaces)
        let history = ClipboardHistory.shared.items
        let matches = query.isEmpty ? history : history.filter { item in
            Fuzzy.contains(query, item.preview) || (item.app.map { Fuzzy.contains(query, $0) } ?? false)
        }
        let pinned = matches.filter(\.pinned).map(clipRow)
        let rest = matches.filter { !$0.pinned }.map(clipRow)
        return [
            LauncherSection(id: "pinned", title: L("Sabitlenenler", "Pinned"), items: pinned),
            LauncherSection(id: "clips", title: L("Pano geçmişi", "Clipboard history"), items: rest),
        ].filter { !$0.items.isEmpty }
    }

    private func clipRow(_ clip: ClipItem) -> LauncherItem {
        LauncherItem(id: "clip:\(clip.id)", icon: .clip(clip), title: clip.preview,
                     accessory: clip.date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated).locale(Format.locale)),
                     primaryTitle: Paster.canPaste ? L("Yapıştır", "Paste") : L("Kopyala", "Copy"),
                     primary: { [weak self] in self?.paste(clip) },
                     secondaryTitle: L("Kopyala", "Copy"),
                     secondary: { [weak self] in
                         ClipboardHistory.shared.copy(clip)
                         self?.close()
                         Monitor.panelActions.flash(L("Kopyalandı", "Copied"))
                     },
                     clip: clip, remember: false)
    }

    private func paste(_ clip: ClipItem) {
        ClipboardHistory.shared.copy(clip)
        close()
        if Paster.canPaste { Paster.paste() } else { Monitor.panelActions.flash(L("Kopyalandı", "Copied")) }
    }

    /// Puts text on the clipboard and pastes it where the cursor was, or only copies it without permission.
    private func paste(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        close()
        if Paster.canPaste { Paster.paste() } else { Monitor.panelActions.flash(L("Kopyalandı", "Copied")) }
    }

    func togglePinSelected() {
        guard let clip = selected?.clip else { return }
        ClipboardHistory.shared.togglePin(clip)
    }

    func deleteSelected() {
        guard let clip = selected?.clip else { return }
        ClipboardHistory.shared.delete(clip)
        selection = min(selection, max(items.count - 1, 0))
    }

    // MARK: Everything

    private func allSections() -> [LauncherSection] {
        let query = text.trimmingCharacters(in: .whitespaces)
        var sections: [LauncherSection] = []
        let commands = commandItems()
        let apps = Prefs.bool(Prefs.launcherApps) ? AppIndex.shared.apps.map(appItem) : []

        if query.isEmpty {
            let all = commands + apps
            let recents = Recents.ids.compactMap { id in all.first { $0.id == id } }
            sections.append(LauncherSection(id: "recents", title: L("Son kullanılanlar", "Recent"), items: recents))
            if Prefs.bool(Prefs.clipboardEnabled) && Prefs.bool(Prefs.launcherClipboard) {
                let clips = ClipboardHistory.shared.items.prefix(3).map(clipRow)
                sections.append(LauncherSection(id: "clips", title: L("Son kopyalananlar", "Recently copied"), items: Array(clips)))
            }
            let suggested = ["cmd:clipboard", "cmd:note", "cmd:timer-25", "cmd:keepAwake-60", "sys:lock", "win:leftHalf", "win:maximize"]
            let suggestions = suggested.compactMap { id in commands.first { $0.id == id } }.filter { item in !recents.contains { $0.id == item.id } }
            sections.append(LauncherSection(id: "suggestions", title: L("Öneriler", "Suggestions"), items: suggestions))
            return sections.filter { !$0.items.isEmpty }
        }

        // Maths, currency and units first: the old quick calculator lives here.
        if let result = Calculator.evaluate(query) {
            let copy = result.copy
            let primary: @MainActor () -> Void = { [weak self] in
                guard !copy.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copy, forType: .string)
                self?.close()
                Monitor.panelActions.flash(L("Kopyalandı", "Copied"))
            }
            var item = LauncherItem(id: "calc", icon: .symbol("equal.circle.fill"), title: result.text, subtitle: query,
                                    primaryTitle: L("Kopyala", "Copy"), primary: primary, remember: false)
            if Paster.canPaste && !copy.isEmpty {
                item.secondaryTitle = L("Yapıştır", "Paste")
                item.secondary = { [weak self] in self?.paste(text: copy) }
            }
            sections.append(LauncherSection(id: "calc", title: L("Hesap", "Calculator"), items: [item]))
        }

        // "gh nabiz": a quicklink keyword followed by a search.
        let words = query.split(separator: " ", maxSplits: 1).map(String.init)
        if words.count == 2, let link = LauncherStore.shared.quicklinks.first(where: { $0.keyword.lowercased() == words[0].lowercased() }) {
            sections.append(LauncherSection(id: "search", title: L("Ara", "Search"), items: [searchItem(link, words[1])]))
        }

        func ranked(_ items: [LauncherItem], keywords: (LauncherItem) -> String, limit: Int) -> [LauncherItem] {
            items.compactMap { item -> (Int, LauncherItem)? in
                let best = [Fuzzy.score(query, item.title), Fuzzy.keyword(query, keywords(item))].compactMap { $0 }.max()
                return best.map { ($0 + (Recents.ids.contains(item.id) ? 50 : 0), item) }
            }
            .sorted { $0.0 > $1.0 }
            .prefix(limit)
            .map(\.1)
        }

        sections.append(LauncherSection(id: "apps", title: L("Uygulamalar", "Apps"),
                                        items: ranked(apps, keywords: { $0.subtitle ?? "" }, limit: 6)))
        sections.append(LauncherSection(id: "commands", title: L("Komutlar", "Commands"),
                                        items: ranked(commands + timerItems(query), keywords: { Self.keywords[$0.id] ?? $0.id.split(separator: ":").last.map(String.init) ?? "" }, limit: 8)))

        let snippets = LauncherStore.shared.snippets.filter { snippet in
            snippet.keyword.lowercased().hasPrefix(query.lowercased()) || Fuzzy.score(query, snippet.name) != nil
        }
        sections.append(LauncherSection(id: "snippets", title: L("Parçacıklar", "Snippets"), items: snippets.map(snippetItem)))

        let links = LauncherStore.shared.quicklinks.filter { link in
            words.count == 1 && (link.keyword.lowercased() == query.lowercased() || Fuzzy.score(query, link.name) != nil)
        }
        sections.append(LauncherSection(id: "links", title: L("Bağlantılar", "Quicklinks"), items: links.map { searchItem($0, "") }))

        if Prefs.bool(Prefs.clipboardEnabled) && Prefs.bool(Prefs.launcherClipboard) {
            let clips = ClipboardHistory.shared.items.filter { Fuzzy.contains(query, $0.preview) }.prefix(4).map(clipRow)
            sections.append(LauncherSection(id: "clips", title: L("Pano", "Clipboard"), items: Array(clips)))
        }

        // Nothing else fits: search the web for it.
        if let web = LauncherStore.shared.quicklinks.first {
            sections.append(LauncherSection(id: "web", title: L("Web", "Web"), items: [searchItem(web, query)]))
        }
        return sections.filter { !$0.items.isEmpty }
    }

    private func searchItem(_ link: Quicklink, _ query: String) -> LauncherItem {
        let title = query.isEmpty ? link.name : L("\(link.name) ile ara: \(query)", "Search \(link.name) for \(query)")
        return LauncherItem(id: query.isEmpty ? "link:\(link.keyword)" : "search", icon: .symbol(query.isEmpty ? "link" : "magnifyingglass"),
                            title: title, subtitle: query.isEmpty ? link.keyword : nil,
                            accessory: query.isEmpty ? L("Bağlantı", "Quicklink") : link.keyword,
                            primaryTitle: L("Aç", "Open"),
                            primary: { [weak self] in
                                self?.close()
                                if let url = link.url(for: query) { NSWorkspace.shared.open(url) }
                            },
                            remember: query.isEmpty)
    }

    private func snippetItem(_ snippet: Snippet) -> LauncherItem {
        LauncherItem(id: "snippet:\(snippet.id)", icon: .symbol("text.quote"), title: snippet.name,
                     subtitle: snippet.text.replacingOccurrences(of: "\n", with: " "), accessory: snippet.keyword,
                     primaryTitle: Paster.canPaste ? L("Yapıştır", "Paste") : L("Kopyala", "Copy"),
                     primary: { [weak self] in self?.paste(text: snippet.expanded) },
                     secondaryTitle: L("Kopyala", "Copy"),
                     secondary: { [weak self] in
                         NSPasteboard.general.clearContents()
                         NSPasteboard.general.setString(snippet.expanded, forType: .string)
                         self?.close()
                         Monitor.panelActions.flash(L("Kopyalandı", "Copied"))
                     },
                     remember: false)
    }

    private func appItem(_ app: AppIndex.App) -> LauncherItem {
        let running = NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == app.path }
        return LauncherItem(id: "app:\(app.path)", icon: .app(app.path), title: app.name,
                            subtitle: app.name == app.fileName ? nil : app.fileName,
                            accessory: running == nil ? L("Uygulama", "App") : L("Açık", "Running"),
                            primaryTitle: L("Aç", "Open"),
                            primary: { [weak self] in
                                self?.close()
                                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: NSWorkspace.OpenConfiguration())
                            },
                            secondaryTitle: running == nil ? L("Finder'da göster", "Show in Finder") : L("Çık", "Quit"),
                            secondary: { [weak self] in
                                self?.close()
                                if let running { running.terminate() } else {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
                                }
                            })
    }

    /// "25 dk", "timer 10", "zamanlayıcı 5": a timer for that many minutes.
    private func timerItems(_ query: String) -> [LauncherItem] {
        let pattern = #"^(?:timer|zamanlayıcı|zamanlayici|sayaç|sayac)?\s*(\d{1,3})\s*(?:dk|dakika|min|m)?$"#
        guard let match = query.lowercased().firstMatch(of: try! Regex(pattern)), let range = match.output[1].range,
              let minutes = Int(query.lowercased()[range]), minutes > 0, minutes <= 600,
              query.rangeOfCharacter(from: .letters) != nil else { return [] }
        return [command("timer-custom", "timer", L("\(minutes) dakikalık zamanlayıcı", "\(minutes)-minute timer"), remember: false) {
            CountdownTimer.shared.start(minutes: minutes)
        }]
    }

    // MARK: Commands

    /// Extra words each command answers to, in both languages, so "kilit" and "lock" both find "Lock screen".
    private static let keywords: [String: String] = [
        "cmd:panel": "panel nabız nabiz menu", "cmd:settings": "settings ayarlar preferences",
        "cmd:history": "history geçmiş grafik chart", "cmd:clipboard": "clipboard pano history geçmiş kopyala",
        "cmd:note": "note not notes yüzen floating", "cmd:schedules": "schedule görev zamanla tasks",
        "sys:lock": "lock kilitle", "sys:sleep": "sleep uyut uyku", "sys:displayOff": "display ekran kapat",
        "sys:hideOthers": "hide gizle", "sys:quitAll": "quit çık kapat all tüm", "sys:emptyTrash": "trash çöp boşalt",
        "sys:restart": "restart yeniden başlat reboot", "sys:shutDown": "shutdown kapat power", "sys:logOut": "logout oturum",
        "cmd:keepAwake-60": "caffeinate awake uyanık kahve", "cmd:keepAwake-0": "caffeinate awake uyanık kahve",
        "cmd:keepAwake-off": "caffeinate awake uyanık", "cmd:timer-5": "timer zamanlayıcı", "cmd:timer-25": "timer zamanlayıcı pomodoro",
        "cmd:timer-off": "timer zamanlayıcı stop durdur",
    ]

    private func command(_ id: String, _ symbol: String, _ title: String, subtitle: String? = nil, accessory: String? = nil,
                         remember: Bool = true, keepOpen: Bool = false, _ action: @escaping @MainActor () -> Void) -> LauncherItem {
        LauncherItem(id: "cmd:\(id)", icon: .symbol(symbol), title: title, subtitle: subtitle, accessory: accessory ?? L("Komut", "Command"),
                     primaryTitle: L("Çalıştır", "Run"),
                     primary: { [weak self] in
                         if !keepOpen { self?.close() }
                         action()
                     },
                     remember: remember)
    }

    private func commandItems() -> [LauncherItem] {
        var items: [LauncherItem] = [
            command("clipboard", "doc.on.clipboard", L("Pano geçmişi", "Clipboard history"), accessory: "⌃⌥V", keepOpen: true) { [weak self] in
                self?.cameFromLauncher = true
                self?.reset(mode: .clipboard)
            },
            command("note", "note.text", L("Yüzen not", "Floating note")) { NoteWindow.toggle() },
            command("panel", "menubar.rectangle", L("Paneli aç", "Open the panel"), accessory: "⌃⌥N") { HotKey.togglePanel() },
            command("history", "chart.xyaxis.line", L("Geçmiş grafikleri", "History charts")) { HistoryWindow.show() },
            command("settings", "gearshape", L("Nabız ayarları", "Nabız settings"), accessory: "⌘,") { SettingsWindow.show(nil) },
            command("schedules", "calendar.badge.clock", L("Zamanlanmış görevler", "Scheduled tasks")) { SettingsWindow.show(.schedules) },
        ]
        for minutes in [5, 10, 25, 60] {
            items.append(command("timer-\(minutes)", "timer", L("Zamanlayıcı: \(minutes) dk", "Timer: \(minutes) min")) {
                CountdownTimer.shared.start(minutes: minutes)
            })
        }
        if CountdownTimer.shared.isRunning {
            items.append(command("timer-off", "timer", L("Zamanlayıcıyı durdur", "Stop the timer")) { CountdownTimer.shared.stop() })
        }
        items.append(command("keepAwake-60", "cup.and.saucer", L("Uyanık kal: 1 saat", "Keep awake: 1 hour")) { KeepAwake.shared.start(minutes: 60) })
        items.append(command("keepAwake-0", "cup.and.saucer.fill", L("Uyanık kal: süresiz", "Keep awake: indefinitely")) { KeepAwake.shared.start(minutes: nil) })
        if KeepAwake.shared.isOn {
            items.append(command("keepAwake-off", "cup.and.saucer", L("Uyanık kalmayı kapat", "Stop keeping awake")) { KeepAwake.shared.stop() })
        }
        for system in SystemCommand.allCases {
            items.append(LauncherItem(id: "sys:\(system.rawValue)", icon: .symbol(system.symbol), title: system.title,
                                      accessory: L("Sistem", "System"), primaryTitle: L("Çalıştır", "Run"),
                                      primary: { [weak self] in
                                          self?.close()
                                          system.run()
                                      }))
        }
        for action in WindowAction.allCases {
            items.append(LauncherItem(id: "win:\(action.rawValue)", icon: .symbol(action.symbol), title: action.title,
                                      accessory: action.shortcut ?? L("Pencere", "Window"), primaryTitle: L("Uygula", "Apply"),
                                      primary: { [weak self] in
                                          self?.close()
                                          action.run()
                                      }))
        }
        let skip: Set<ToolKind> = [.calculator, .keepAwake, .timer, .clipboard, .note]
        for tool in ToolKind.allCases where !skip.contains(tool) {
            items.append(LauncherItem(id: "tool:\(tool.rawValue)", icon: .symbol(tool.symbol), title: tool.title, subtitle: tool.help,
                                      accessory: L("Araç", "Tool"), primaryTitle: L("Çalıştır", "Run"),
                                      primary: { [weak self] in
                                          self?.close()
                                          guard let monitor = SettingsWindow.monitor else { return }
                                          Toolbox.shared.refresh()
                                          Toolbox.shared.run(tool, actions: Monitor.panelActions, monitor: monitor)
                                      }))
        }
        return items
    }
}

/// The last apps and commands run from the launcher, newest first.
@MainActor
enum Recents {
    private static let key = "launcherRecents"

    static var ids: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func add(_ id: String) {
        var list = ids.filter { $0 != id }
        list.insert(id, at: 0)
        UserDefaults.standard.set(Array(list.prefix(6)), forKey: key)
    }
}

/// Typo-tolerant matching for the launcher: exact > prefix > word prefix > initials > substring > letters in order.
enum Fuzzy {
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).replacingOccurrences(of: "ı", with: "i")
    }

    /// Higher is better; nil when it doesn't match at all.
    static func score(_ query: String, _ target: String) -> Int? {
        let q = fold(query), t = fold(target)
        guard !q.isEmpty, !t.isEmpty else { return nil }
        if t == q { return 1000 }
        if t.hasPrefix(q) { return 900 - t.count }
        let words = t.split { !$0.isLetter && !$0.isNumber }
        if words.contains(where: { $0.hasPrefix(q) }) { return 800 - t.count }
        if q.count >= 2, String(words.compactMap(\.first)).hasPrefix(q) { return 700 }
        if t.contains(q) { return 600 - t.count }
        guard q.count >= 3 else { return nil }
        var rest = Substring(t)
        for character in q {
            guard let index = rest.firstIndex(of: character) else { return nil }
            rest = rest[rest.index(after: index)...]
        }
        return 300 - t.count
    }

    /// Extra words (aliases, the English file name) only count when one of them starts with the query.
    static func keyword(_ query: String, _ words: String) -> Int? {
        let q = fold(query)
        guard q.count >= 2 else { return nil }
        let list = fold(words).split { !$0.isLetter && !$0.isNumber }
        if list.contains(where: { $0 == q }) { return 850 }
        return list.contains { $0.hasPrefix(q) } ? 750 : nil
    }

    static func contains(_ query: String, _ target: String) -> Bool {
        fold(target).contains(fold(query))
    }
}

/// Installed apps, found once in the usual folders and refreshed at most every minute.
@MainActor
final class AppIndex {
    static let shared = AppIndex()

    struct App: Sendable {
        /// Localized, as Finder shows it ("Sistem Ayarları").
        let name: String
        /// On disk, usually English ("System Settings").
        let fileName: String
        let path: String
    }

    private(set) var apps: [App] = []
    private var scannedAt: Date?
    private var icons: [String: NSImage] = [:]

    func refreshIfNeeded() {
        if let scannedAt, Date().timeIntervalSince(scannedAt) < 60 { return }
        scannedAt = Date()
        Task {
            apps = await Task.detached(priority: .userInitiated) { Self.scan() }.value
        }
    }

    func icon(_ path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }

    nonisolated static func scan() -> [App] {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser.path
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                     "\(home)/Applications", "/System/Library/CoreServices/Applications"]
        var found: [String: App] = [:]
        func add(_ path: String) {
            let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            var name = manager.displayName(atPath: path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            found[fileName] = found[fileName] ?? App(name: name, fileName: fileName, path: path)
        }
        for root in roots {
            for entry in (try? manager.contentsOfDirectory(atPath: root)) ?? [] where !entry.hasPrefix(".") {
                let path = "\(root)/\(entry)"
                if entry.hasSuffix(".app") {
                    add(path)
                } else if root == "/Applications", entry != "Utilities" {
                    // One folder down: "/Applications/Microsoft Office/…", "/Applications/Setapp/…".
                    for inner in (try? manager.contentsOfDirectory(atPath: path)) ?? [] where inner.hasSuffix(".app") {
                        add("\(path)/\(inner)")
                    }
                }
            }
        }
        add("/System/Library/CoreServices/Finder.app")
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
