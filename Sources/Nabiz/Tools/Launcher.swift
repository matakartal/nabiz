// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Observation

/// One row in the launcher: an app, a command, a snippet, a clipboard item, a calculation or a web search.
struct LauncherItem: Identifiable {
    enum Icon {
        case symbol(String)
        case app(String)
        case clip(ClipItem)
        case emoji(String)
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
    enum Mode { case all, clipboard, ai }

    var mode: Mode = .all
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            clearSelection()
            // "?" at the start switches to asking AI.
            if mode == .all, text.hasPrefix("?"), Prefs.bool(Prefs.aiAsk) {
                mode = .ai
                ai = nil
                text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
                return
            }
            // "gh" then Space: GitHub takes the field and what follows is the search.
            if mode == .all, argument == nil,
               let link = Self.quicklink(forSpaceAfter: text, in: LauncherStore.shared.quicklinks, translating: Prefs.bool(Prefs.aiAsk)) {
                argument = LauncherArgument(target: .quicklink(link))
                text = ""
                return
            }
            FileSearch.shared.search(fileTerm)
        }
    }

    /// What to look for in files: everything after "/", or a normal search of three letters or more.
    private var fileTerm: String {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard argument == nil else { return "" }
        if query.hasPrefix("/") { return String(query.dropFirst()) }
        guard Prefs.bool(Prefs.launcherFiles), mode == .all, query.count >= 3,
              let first = query.first, !"=>:?".contains(first), Downloader.videoURL(query) == nil else { return "" }
        return query
    }
    /// The row picked with the arrows or the pointer, by id: rows arriving later (files, AI) move the others, and
    /// Return must still run the one that was highlighted.
    var selectedID: String?
    /// Until a row is picked, the first row shown for this text stays the highlighted one.
    @ObservationIgnored private var anchorID: String?

    private func clearSelection() {
        selectedID = nil
        anchorID = nil
    }

    /// The highlighted row's id in this list: the picked one, else the first row shown since the text changed.
    func resolvedSelection(_ items: [LauncherItem]) -> String? {
        if let selectedID, items.contains(where: { $0.id == selectedID }) { return selectedID }
        if let anchorID, items.contains(where: { $0.id == anchorID }) { return anchorID }
        anchorID = items.first?.id
        return anchorID
    }
    /// The ⌘K actions palette for the selected row.
    var paletteOpen = false {
        didSet { paletteQuery = ""; paletteSelection = 0 }
    }
    var paletteQuery = "" {
        didSet { if paletteQuery != oldValue { paletteSelection = 0 } }
    }
    var paletteSelection = 0
    /// The chat shown while `mode` is `.ai`; nil shows what can be asked (tasks, recent chats).
    var ai: AIConversation?
    /// What was typed before asking, so Escape can go back to it.
    var aiReturnText = ""
    /// A follow-up typed while the answer is still being written; it is sent when that answer ends.
    var queuedFollowUp: String?
    /// A quicklink or script waiting for its query or values (Tab, or Space after a keyword).
    var argument: LauncherArgument?
    /// Text selected in the app in front when the launcher opened.
    var selectedText: String?
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
        paletteOpen = false
        argument = nil
        self.mode = mode
        self.text = text
        clearSelection()
        PortCache.shared.refresh()
        ProjectStore.shared.refresh()
    }

    var sections: [LauncherSection] {
        switch mode {
        case .clipboard: clipboardSections()
        case .all: (argument.map(argumentSections) ?? allSections()).map { section in
            var section = section
            section.items = section.items.map(withBinding)
            return section
        }
        case .ai: ai == nil ? aiSections(text.trimmingCharacters(in: .whitespaces)) : []
        }
    }

    /// A row with its own shortcut shows it on the right, like the built-in ones.
    private func withBinding(_ item: LauncherItem) -> LauncherItem {
        guard let binding = ItemBindings.shared.binding(item.id) else { return item }
        var item = item
        if let label = binding.combo?.label { item.accessory = label } else if let alias = binding.alias { item.accessory = alias }
        return item
    }

    /// One of the user's own AI commands, on the given text, else the selected one, else the last text copied.
    func runAICommand(_ command: AICommand, on given: String?) {
        let copied = ClipboardHistory.shared.items.first { $0.kind == .text && $0.text != nil }?.text ?? NSPasteboard.general.string(forType: .string)
        guard let text = (given ?? selectedText ?? copied)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            Monitor.panelActions.flash(L("Önce bir metin seç ya da kopyala", "Select or copy some text first"))
            return
        }
        guard !SecretText.looksSecret(text) else {
            Monitor.panelActions.flash(L("Bu bir şifreye benziyor; AI'a gönderilmedi", "That looks like a password; not sent to AI"))
            return
        }
        ai = nil
        mode = .ai
        ask(command.name, attachment: text, prompt: command.fullPrompt(text))
    }

    /// Every command the launcher can run, for MCP.
    func commandList() -> [(id: String, title: String)] { commandItems().map { ($0.id, $0.title) } }

    /// An app, command or quicklink by its id, for its own shortcut (the launcher may be closed).
    func item(id: String) -> LauncherItem? {
        if id.hasPrefix("proj:") { return ProjectStore.shared.project(String(id.dropFirst(5))).map(projectItem) }
        if id.hasPrefix("app:") {
            let path = String(id.dropFirst(4))
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let app = AppIndex.shared.apps.first { $0.path == path }
            let name = app?.name ?? FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
            return LauncherItem(id: id, icon: .app(path), title: name, primaryTitle: L("Aç", "Open"), primary: { [weak self] in
                self?.close()
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
            })
        }
        if id.hasPrefix("link:") {
            return LauncherStore.shared.quicklinks.first { "link:\($0.keyword)" == id }.map { searchItem($0, "") }
        }
        if id.hasPrefix("bt:") {
            return BluetoothDevices.devices(for: "bluetooth").first { "bt:\($0.id)" == id }.map(bluetoothItem)
        }
        return commandItems().first { $0.id == id }
    }

    var items: [LauncherItem] { sections.flatMap(\.items) }

    var selected: LauncherItem? {
        let items = items
        let id = resolvedSelection(items)
        return items.first { $0.id == id }
    }

    func move(_ offset: Int) {
        let items = items
        let count = items.count
        guard count > 0 else { return }
        let id = resolvedSelection(items)
        let index = items.firstIndex { $0.id == id } ?? 0
        selectedID = items[(index + offset + count) % count].id
    }

    /// After the selected row goes away, its neighbour below (or above, at the end) takes over.
    func selectNeighbour(of id: String, in before: [LauncherItem]) {
        guard let index = before.firstIndex(where: { $0.id == id }) else { return }
        let rest = before.filter { $0.id != id }
        selectedID = rest.isEmpty ? nil : rest[min(index, rest.count - 1)].id
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

    /// Pastes text where the cursor was and gives the user's clipboard back afterwards; without permission it is
    /// only copied. Either way it stays out of the clipboard history.
    func paste(text: String, cursorBack: Int = 0) {
        close()
        if Paster.canPaste {
            Paster.paste(text, cursorBack: cursorBack)
        } else {
            ClipboardHistory.shared.writeOwn(text)
            Monitor.panelActions.flash(L("Kopyalandı", "Copied"))
        }
    }

    func togglePinSelected() {
        guard let clip = selected?.clip else { return }
        ClipboardHistory.shared.togglePin(clip)
    }

    func deleteSelected() {
        let before = items
        guard let item = before.first(where: { $0.id == resolvedSelection(before) }), let clip = item.clip else { return }
        selectNeighbour(of: item.id, in: before)
        ClipboardHistory.shared.delete(clip)
    }

    // MARK: Everything

    private func allSections() -> [LauncherSection] {
        let query = text.trimmingCharacters(in: .whitespaces)
        var sections: [LauncherSection] = []
        let commands = commandItems()
        let running = Dictionary(NSWorkspace.shared.runningApplications.compactMap { app in app.bundleURL.map { ($0.path, app) } },
                                 uniquingKeysWith: { first, _ in first })
        let apps = Prefs.bool(Prefs.launcherApps) ? AppIndex.shared.apps.map { appItem($0, running: running[$0.path]) } : []

        // ":heart", ":kalp": emoji.
        if query.hasPrefix(":"), Ports.query(query) == nil {
            let found = EmojiIndex.search(String(query.dropFirst())).prefix(60).map(emojiItem)
            return [LauncherSection(id: "emoji", title: "Emoji", items: Array(found))].filter { !$0.items.isEmpty }
        }

        // "? what is…": ask an AI.
        // "/report": files only.
        if query.hasPrefix("/") {
            let search = FileSearch.shared
            let rest = query.dropFirst().trimmingCharacters(in: .whitespaces)
            let done = search.term == rest && !search.searching
            let files = search.term == rest ? search.results.map(fileItem) : []
            // Finished with nothing found: the empty state says so instead of a bare heading.
            if rest.count >= 2 && done && files.isEmpty { return [] }
            let title = rest.count < 2 ? L("Dosya adı yaz", "Type a file name") : !done && files.isEmpty ? L("Aranıyor…", "Searching…") : L("Dosyalar", "Files")
            return [LauncherSection(id: "files", title: title, items: files)]
        }

        // "=": the calculator alone; with nothing after it, the last calculations.
        if query.hasPrefix("=") {
            let rest = query.dropFirst().trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                let history = CalcHistory.entries.enumerated().map { historyItem($1, index: $0) }
                return [LauncherSection(id: "history", title: L("Hesap geçmişi", "Calculation history"), items: history)].filter { !$0.items.isEmpty }
            }
            let results = Calculator.evaluateAll(rest)
            return [LauncherSection(id: "calc", title: L("Hesap", "Calculator"),
                                    items: results.enumerated().map { calcItem($1, index: $0, expression: rest) })].filter { !$0.items.isEmpty }
        }

        // "> lock": commands only, like an editor's command palette.
        if query.hasPrefix(">") {
            let rest = query.dropFirst().trimmingCharacters(in: .whitespaces)
            let list = rest.isEmpty ? commands : commands.compactMap { item -> (Int, LauncherItem)? in
                let best = [Fuzzy.score(rest, item.title), Fuzzy.keyword(rest, Self.keywords[item.id] ?? item.id)].compactMap { $0 }.max()
                return best.map { ($0, item) }
            }.sorted { $0.0 > $1.0 }.map(\.1)
            return [LauncherSection(id: "commands", title: L("Komutlar", "Commands"), items: list)].filter { !$0.items.isEmpty }
        }

        if query.isEmpty {
            let all = commands + apps + LauncherStore.shared.quicklinks.map { searchItem($0, "") } + ProjectStore.shared.projects.map(projectItem)
            let favorites = Favorites.ids.compactMap { id in all.first { $0.id == id } }
            sections.append(LauncherSection(id: "favorites", title: L("Favoriler", "Favourites"), items: favorites))
            if Prefs.bool(Prefs.aiAsk), let selectedText {
                sections.append(LauncherSection(id: "selection", title: L("Seçili metin", "Selected text"), items: aiTaskItems(selectedText, source: "sel")))
            }
            let recents = Recents.ids.compactMap { id in all.first { $0.id == id } }.filter { item in !favorites.contains { $0.id == item.id } }
            sections.append(LauncherSection(id: "recents", title: L("Son kullanılanlar", "Recent"), items: recents))
            if Prefs.bool(Prefs.clipboardEnabled) && Prefs.bool(Prefs.launcherClipboard) {
                let clips = ClipboardHistory.shared.items.prefix(3).map(clipRow)
                sections.append(LauncherSection(id: "clips", title: L("Son kopyalananlar", "Recently copied"), items: Array(clips)))
            }
            let downloads = Downloader.shared.jobs.prefix(3).map(jobItem)
            sections.append(LauncherSection(id: "downloads", title: L("İndirilenler", "Downloads"), items: Array(downloads)))
            let suggested = ["cmd:ai-chat", "cmd:clipboard", "cmd:note", "cmd:pomodoro", "cmd:focus-25", "cmd:capture-area", "sys:lock", "win:leftHalf"]
            let suggestions = suggested.compactMap { id in commands.first { $0.id == id } }
                .filter { item in !recents.contains { $0.id == item.id } && !favorites.contains { $0.id == item.id } }
            sections.append(LauncherSection(id: "suggestions", title: L("Öneriler", "Suggestions"), items: suggestions))
            return sections.filter { !$0.items.isEmpty }
        }

        // An alias typed alone puts its row first.
        var aliased: String?
        if let id = ItemBindings.shared.id(forAlias: query),
           let hit = (commands + apps).first(where: { $0.id == id }) ?? item(id: id) {
            aliased = hit.id
            sections.append(LauncherSection(id: "alias", title: L("Takma ad", "Alias"), items: [hit]))
        }

        // ":3000", "jwt eyJ…", "1732636800", "sha256 text": developer answers.
        let dev = devSections(query)
        sections += dev
        // A port, token, time or colour answered: asking AI or the web about it is noise.
        let devAnswered = dev.contains { $0.id != "projects" }

        // Maths, money, units, time zones and dates first.
        let results = Calculator.evaluateAll(query)
        if !results.isEmpty {
            sections.append(LauncherSection(id: "calc", title: L("Hesap", "Calculator"),
                                            items: results.enumerated().map { calcItem($1, index: $0, expression: query) }))
        }

        if Prefs.bool(Prefs.calendarEnabled) && CalendarAgenda.shared.authorized && query.count >= 3 {
            let word = Fuzzy.fold(query)
            if ["takvim", "calendar", "toplanti", "ajanda", "agenda", "meeting", "etkinlik", "bugun", "today"].contains(where: { $0.hasPrefix(word) }) {
                let events = CalendarAgenda.shared.upcoming.prefix(8).map(eventItem)
                sections.append(LauncherSection(id: "calendar", title: L("Takvim", "Calendar"), items: Array(events)))
            }
        }

        if query.count >= 3, Prefs.bool(Prefs.showWeather) || Prefs.bool(Prefs.barWeather), let report = WeatherStore.shared.report {
            let word = Fuzzy.fold(query)
            let words = ["hava", "hava durumu", "weather", "sicaklik", "temperature", "yagmur", "rain", "forecast", "tahmin"]
            if words.contains(where: { $0.hasPrefix(word) }) || ["hava ", "weather "].contains(where: { word.hasPrefix($0) }) {
                var items = [LauncherItem(id: "weather:now", icon: .symbol(WeatherCode.symbol(report.code, day: report.isDay)),
                                          title: "\(report.place.name) \(Format.degrees(report.temperature))",
                                          subtitle: "\(WeatherCode.title(report.code)) · \(L("hissedilen", "feels like")) \(Format.degrees(report.feelsLike))",
                                          accessory: L("Hava", "Weather"), primaryTitle: L("Hava'da aç", "Open in Weather"),
                                          primary: { WeatherStore.openWeatherApp() }, remember: false)]
                for (index, day) in report.upcomingDays.prefix(4).enumerated() where index > 0 {
                    items.append(LauncherItem(id: "weather:\(index)", icon: .symbol(WeatherCode.symbol(day.code)),
                                              title: report.dayName(day.date),
                                              subtitle: WeatherCode.title(day.code),
                                              accessory: "\(Format.degrees(day.high)) / \(Format.degrees(day.low))",
                                              primaryTitle: L("Hava'da aç", "Open in Weather"),
                                              primary: { WeatherStore.openWeatherApp() }, remember: false))
                }
                sections.append(LauncherSection(id: "weather", title: L("Hava durumu", "Weather"), items: items))
            }
        }

        if Prefs.bool(Prefs.aiAsk), let phrase = TranslateQuery.text(in: query) {
            let task = TranslateQuery.task(for: phrase)
            sections.append(LauncherSection(id: "translate", title: L("Çeviri", "Translate"), items: [
                LauncherItem(id: "translate", icon: .symbol("character.bubble"), title: "\(task.title): \(phrase)",
                             accessory: "AI", primaryTitle: L("Çevir", "Translate"),
                             primary: { [weak self] in self?.runAI(task, on: phrase) }, remember: false),
            ]))
        }

        if let volume = volumeItem(query) {
            sections.append(LauncherSection(id: "volume", title: L("Ses", "Sound"), items: [volume]))
        }

        if let url = Downloader.videoURL(query) {
            sections.append(LauncherSection(id: "download", title: L("İndir", "Download"), items: downloadItems(url)))
        }

        // "gh nabiz": a quicklink keyword followed by a search.
        let words = query.split(separator: " ", maxSplits: 1).map(String.init)
        if words.count == 2, let link = LauncherStore.shared.quicklinks.first(where: { $0.keyword.lowercased() == words[0].lowercased() }) {
            sections.append(LauncherSection(id: "search", title: L("Ara", "Search"), items: [searchItem(link, words[1])]))
        }

        func ranked(_ items: [LauncherItem], keywords: (LauncherItem) -> String, limit: Int) -> [LauncherItem] {
            items.compactMap { item -> (Int, LauncherItem)? in
                let best = [Fuzzy.score(query, item.title), Fuzzy.keyword(query, keywords(item))].compactMap { $0 }.max()
                return best.map { ($0 + (Recents.ids.contains(item.id) ? 50 : 0) + (Favorites.ids.contains(item.id) ? 100 : 0), item) }
            }
            .sorted { $0.0 > $1.0 }
            .prefix(limit)
            .map(\.1)
        }

        sections.append(LauncherSection(id: "apps", title: L("Uygulamalar", "Apps"),
                                        items: ranked(apps, keywords: { $0.subtitle ?? "" }, limit: 6)))
        sections.append(LauncherSection(id: "commands", title: L("Komutlar", "Commands"),
                                        items: ranked(commands + timerItems(query) + soundItems(query), keywords: { item in
                                            if item.id.hasPrefix("shortcut:") { return "shortcut kestirme" }
                                            if item.id.hasPrefix("aicmd:") { return "ai yapay zeka komut command prompt" }
                                            if item.id.hasPrefix("layout") { return "pencere window layout yerleşim düzen set" }
                                            if item.id.hasPrefix("audio:") { return "ses çıkış output sound speaker hoparlör kulaklık headphones" }
                                            if item.id.hasPrefix("bt:") { return "bluetooth bt bağlan connect disconnect kes kulaklık" }
                                            if item.id.hasPrefix("script:") { return "script betik" }
                                            if item.id.hasPrefix("cmd:port-") { return "port dev server sunucu durdur stop kill \(item.subtitle ?? "")" }
                                            return Self.keywords[item.id] ?? item.id.split(separator: ":").last.map(String.init) ?? ""
                                        }, limit: 8)))

        let notes = NoteStore.shared.sorted.filter { !$0.isEmpty && (Fuzzy.score(query, $0.title) != nil || Fuzzy.contains(query, $0.text)) }
        sections.append(LauncherSection(id: "notes", title: L("Notlar", "Notes"), items: notes.prefix(4).map(noteItem)))

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

        if FileSearch.shared.term == query && !FileSearch.shared.results.isEmpty {
            sections.append(LauncherSection(id: "files", title: L("Dosyalar", "Files"), items: FileSearch.shared.results.prefix(5).map(fileItem)))
        }

        // Asking AI comes before the web. A question ("…?", or a sentence of four words or more) or a query nothing
        // else matched puts it first, so ↩ asks.
        // A token or key typed here is never sent to AI or a search engine.
        let secret = devAnswered || SecretText.looksSecret(query)
        if Prefs.bool(Prefs.aiAsk) && query.count >= 3 && !secret {
            let ask = LauncherSection(id: "ai", title: "AI", items: [askItem(query)])
            let words = query.split(whereSeparator: \.isWhitespace).count
            let question = query.hasSuffix("?") || words >= 4
            if question || sections.allSatisfy({ $0.items.isEmpty }) { sections.insert(ask, at: 0) } else { sections.append(ask) }
        }
        // Nothing else fits: search the web for it.
        // Not when a quicklink search ("gh nabiz") is already there: both rows would share the id "search".
        if !secret, let web = LauncherStore.shared.webSearch, !sections.contains(where: { $0.id == "search" }) {
            sections.append(LauncherSection(id: "web", title: L("Web", "Web"), items: [searchItem(web, query)]))
        }
        if let aliased {
            for index in sections.indices where sections[index].id != "alias" { sections[index].items.removeAll { $0.id == aliased } }
        }
        return sections.filter { !$0.items.isEmpty }
    }

    func searchItem(_ link: Quicklink, _ query: String) -> LauncherItem {
        let title = query.isEmpty ? link.name : L("\(link.name) ile ara: \(query)", "Search \(link.name) for \(query)")
        // A search link with nothing to search yet asks for it in the field instead of opening an empty search.
        let asks = query.isEmpty && link.takesQuery
        return LauncherItem(id: query.isEmpty ? "link:\(link.keyword)" : "search", icon: .symbol(query.isEmpty ? "link" : "magnifyingglass"),
                            title: title, subtitle: query.isEmpty ? link.keyword : nil,
                            accessory: query.isEmpty ? L("Bağlantı", "Quicklink") : link.keyword,
                            primaryTitle: asks ? L("Ara…", "Search…") : L("Aç", "Open"),
                            primary: { [weak self] in
                                if asks {
                                    self?.enterArgument(.quicklink(link))
                                    return
                                }
                                self?.close()
                                if let url = link.url(for: query) { NSWorkspace.shared.open(url) }
                            },
                            remember: query.isEmpty)
    }

    private func emojiItem(_ emoji: EmojiIndex.Emoji) -> LauncherItem {
        LauncherItem(id: "emoji:\(emoji.character)", icon: .emoji(emoji.character), title: emoji.name.capitalized,
                     primaryTitle: Paster.canPaste ? L("Yapıştır", "Paste") : L("Kopyala", "Copy"),
                     primary: { [weak self] in
                         EmojiIndex.used(emoji.character)
                         self?.paste(text: emoji.character)
                     },
                     secondaryTitle: L("Kopyala", "Copy"),
                     secondary: { [weak self] in
                         EmojiIndex.used(emoji.character)
                         NSPasteboard.general.clearContents()
                         NSPasteboard.general.setString(emoji.character, forType: .string)
                         self?.close()
                         Monitor.panelActions.flash(L("Kopyalandı", "Copied"))
                     },
                     remember: false)
    }

    private func fileItem(_ url: URL) -> LauncherItem {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folder = url.deletingLastPathComponent().path.replacingOccurrences(of: home, with: "~")
        return LauncherItem(id: "file:\(url.path)", icon: .app(url.path), title: url.lastPathComponent, subtitle: folder,
                            primaryTitle: L("Aç", "Open"),
                            primary: { [weak self] in
                                self?.close()
                                NSWorkspace.shared.open(url)
                            },
                            secondaryTitle: L("Finder'da göster", "Show in Finder"),
                            secondary: { [weak self] in
                                self?.close()
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            },
                            remember: false)
    }

    private func downloadItems(_ url: URL) -> [LauncherItem] {
        let downloader = Downloader.shared
        guard downloader.ytdlp != nil else {
            return [LauncherItem(id: "dl-install", icon: .symbol("arrow.down.circle"),
                                 title: downloader.installing ? L("yt-dlp kuruluyor…", "Installing yt-dlp…") : L("Video indirmek için yt-dlp'yi kur", "Install yt-dlp to download videos"),
                                 subtitle: downloader.brew != nil ? "Homebrew" : nil, primaryTitle: L("Kur", "Install"),
                                 primary: { [weak self] in
                                     self?.close()
                                     downloader.install()
                                 }, remember: false)]
        }
        let quality = switch Prefs.string(Prefs.downloadQuality) {
        case "1080": "1080p"
        case "720": "720p"
        default: L("en iyi", "best")
        }
        return [
            LauncherItem(id: "dl-video", icon: .symbol("film"), title: L("Videoyu indir", "Download the video"),
                         subtitle: url.host, accessory: "MP4 · \(quality)", primaryTitle: L("İndir", "Download"),
                         primary: { [weak self] in
                             self?.close()
                             downloader.download(url.absoluteString, kind: .video)
                             Monitor.panelActions.flash(L("İndiriliyor…", "Downloading…"))
                         }, remember: false),
            LauncherItem(id: "dl-audio", icon: .symbol("music.note"), title: L("Yalnızca sesi indir", "Download the sound only"),
                         subtitle: url.host, accessory: downloader.ffmpeg != nil ? "MP3" : "M4A", primaryTitle: L("İndir", "Download"),
                         primary: { [weak self] in
                             self?.close()
                             downloader.download(url.absoluteString, kind: .audio)
                             Monitor.panelActions.flash(L("İndiriliyor…", "Downloading…"))
                         }, remember: false),
        ]
    }

    private func jobItem(_ job: Downloader.Job) -> LauncherItem {
        let downloader = Downloader.shared
        let status: String = switch job.status {
        case .running: job.progress.map { Format.percent($0) + (job.eta.map { " · \($0)" } ?? "") } ?? L("başlıyor", "starting")
        case .done: L("bitti", "done")
        case .failed: L("hata", "failed")
        }
        var subtitle: String?
        if case .failed(let message) = job.status { subtitle = message }
        return LauncherItem(id: "job:\(job.id)", icon: .symbol(job.kind == .audio ? "music.note" : "film"), title: job.title,
                            subtitle: subtitle, accessory: status,
                            primaryTitle: job.status == .done ? L("Finder'da göster", "Show in Finder") : job.status == .running ? L("Klasörü aç", "Open folder") : L("Tekrar dene", "Try again"),
                            primary: { [weak self] in
                                self?.close()
                                if case .failed = job.status { downloader.retry(job) } else { downloader.reveal(job) }
                            },
                            secondaryTitle: job.status == .running ? L("İptal et", "Cancel") : L("Listeden kaldır", "Remove"),
                            secondary: { downloader.cancel(job.id) },
                            remember: false)
    }

    private func calcItem(_ result: Calculator.Result, index: Int, expression: String) -> LauncherItem {
        let usable = !result.copy.isEmpty
        var item = LauncherItem(id: "calc:\(index)", icon: .symbol(index == 0 ? "equal.circle.fill" : "equal"),
                                title: result.text, subtitle: index == 0 ? expression : nil, accessory: result.note,
                                primaryTitle: L("Kopyala", "Copy"),
                                primary: { [weak self] in
                                    guard usable else { return }
                                    CalcHistory.add(expression, result)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(result.copy, forType: .string)
                                    self?.close()
                                    Monitor.panelActions.flash(L("Kopyalandı", "Copied"))
                                },
                                remember: false)
        if Paster.canPaste && usable {
            item.secondaryTitle = L("Yapıştır", "Paste")
            item.secondary = { [weak self] in
                CalcHistory.add(expression, result)
                self?.paste(text: result.copy)
            }
        }
        return item
    }

    private func historyItem(_ entry: CalcHistory.Entry, index: Int) -> LauncherItem {
        LauncherItem(id: "calchist:\(index)", icon: .symbol("clock.arrow.circlepath"), title: entry.text, subtitle: entry.expression,
                     accessory: entry.date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated).locale(Format.locale)),
                     primaryTitle: L("Kopyala", "Copy"),
                     primary: { [weak self] in
                         NSPasteboard.general.clearContents()
                         NSPasteboard.general.setString(entry.copy, forType: .string)
                         self?.close()
                         Monitor.panelActions.flash(L("Kopyalandı", "Copied"))
                     },
                     secondaryTitle: L("Yeniden hesapla", "Edit"),
                     secondary: { [weak self] in self?.text = "= " + entry.expression },
                     remember: false)
    }

    private func noteItem(_ note: Note) -> LauncherItem {
        LauncherItem(id: "note:\(note.id)", icon: .symbol("note.text"), title: note.title, subtitle: note.preview,
                     accessory: note.modified.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated).locale(Format.locale)),
                     primaryTitle: L("Aç", "Open"),
                     primary: { [weak self] in
                         self?.close()
                         NoteWindow.show(note.id)
                     },
                     secondaryTitle: L("Kopyala", "Copy"),
                     secondary: { [weak self] in
                         NSPasteboard.general.clearContents()
                         NSPasteboard.general.setString(note.text, forType: .string)
                         self?.close()
                         Monitor.panelActions.flash(L("Kopyalandı", "Copied"))
                     },
                     remember: false)
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

    private func appItem(_ app: AppIndex.App, running: NSRunningApplication?) -> LauncherItem {
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
    /// "bluetooth", "airpods": the paired devices.
    private func soundItems(_ query: String) -> [LauncherItem] {
        BluetoothDevices.devices(for: query).map(bluetoothItem)
    }

    /// "ses 40", "volume 40": that volume, as its own answer above the rest.
    private func volumeItem(_ query: String) -> LauncherItem? {
        SoundOutput.level(in: query).map { level in
            LauncherItem(id: "volume-set", icon: .symbol("speaker.wave.2"), title: L("Ses: %\(level)", "Volume: \(level)%"),
                                      accessory: L("Ses", "Sound"), primaryTitle: L("Ayarla", "Set"),
                                      primary: { [weak self] in
                                          self?.close()
                                          SoundOutput.setVolume(level)
                                      }, remember: false)
        }
    }

    private func eventItem(_ event: CalendarAgenda.Event) -> LauncherItem {
        let close: @MainActor () -> Void = { [weak self] in self?.close() }
        var item = LauncherItem(id: "event:\(event.id)", icon: .symbol(event.meetingURL != nil ? "video" : "calendar"), title: event.title,
                                subtitle: event.location ?? event.calendar, accessory: CalendarAgenda.timeText(event),
                                primaryTitle: event.meetingURL != nil ? L("Katıl", "Join") : L("Takvimde aç", "Open Calendar"),
                                primary: {
                                    close()
                                    if event.meetingURL != nil { CalendarAgenda.shared.join(event) } else { CalendarAgenda.shared.openInCalendar() }
                                },
                                remember: false)
        if let url = event.meetingURL {
            item.secondaryTitle = L("Bağlantıyı kopyala", "Copy link")
            item.secondary = {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                close()
                Monitor.panelActions.flash(L("Kopyalandı", "Copied"))
            }
        }
        return item
    }

    private func bluetoothItem(_ device: BluetoothDevices.Device) -> LauncherItem {
        LauncherItem(id: "bt:\(device.id)", icon: .symbol(device.name.lowercased().contains("airpods") ? "airpods" : "dot.radiowaves.left.and.right"),
                     title: device.connected ? L("Bağlantıyı kes: \(device.name)", "Disconnect \(device.name)") : L("Bağlan: \(device.name)", "Connect \(device.name)"),
                     accessory: device.connected ? L("Bağlı", "Connected") : "Bluetooth", primaryTitle: device.connected ? L("Kes", "Disconnect") : L("Bağlan", "Connect"),
                     primary: { [weak self] in
                         self?.close()
                         BluetoothDevices.toggle(device)
                     })
    }

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
        "cmd:history": "history geçmiş grafik chart",
        "cmd:ai-chat": "ai chat sohbet claude codex gemini apple yapay zeka gpt", "cmd:ai-ask": "ai ask sor soru claude codex gemini yapay zeka", "cmd:clipboard": "clipboard pano history geçmiş kopyala",
        "cmd:note": "note not notes notlar yüzen floating", "cmd:note-new": "note not new yeni", "cmd:schedules": "schedule görev zamanla tasks",
        "cmd:dictation": "dikte dictate dictation ses voice konuş speak yaz type", "cmd:calendar-join": "join katıl toplantı meeting zoom meet teams call", "cmd:calendar": "calendar takvim ajanda agenda toplantı meeting",
        "cmd:volume-mute": "ses sound mute sustur kapat aç volume", "cmd:volume-up": "ses artır yükselt volume up louder",
        "cmd:volume-down": "ses azalt kıs volume down quieter",
        "sys:lock": "lock kilitle", "sys:sleep": "sleep uyut uyku", "sys:displayOff": "display ekran kapat",
        "sys:hideOthers": "hide gizle", "sys:quitAll": "quit çık kapat all tüm", "sys:emptyTrash": "trash çöp boşalt",
        "sys:restart": "restart yeniden başlat reboot", "sys:shutDown": "shutdown kapat power", "sys:logOut": "logout oturum",
        "cmd:keepAwake-60": "caffeinate awake uyanık kahve", "cmd:keepAwake-0": "caffeinate awake uyanık kahve",
        "cmd:keepAwake-off": "caffeinate awake uyanık", "cmd:timer-5": "timer zamanlayıcı", "cmd:timer-25": "timer zamanlayıcı pomodoro",
        "cmd:timer-off": "timer zamanlayıcı stop durdur",
        "cmd:pomodoro": "pomodoro odak focus domates tomato", "cmd:pomodoro-toggle": "pomodoro pause duraklat devam resume",
        "cmd:pomodoro-skip": "pomodoro skip atla", "cmd:pomodoro-stop": "pomodoro stop bitir",
        "cmd:focus-25": "focus odak dnd rahatsiz", "cmd:focus-60": "focus odak dnd", "cmd:focus-120": "focus odak dnd",
        "cmd:focus-on": "focus odak dnd", "cmd:focus-off": "focus odak kapat",
        "cmd:capture-area": "screenshot ekran goruntusu capture ss alan", "cmd:capture-window": "screenshot ekran pencere window",
        "cmd:capture-screen": "screenshot ekran tum", "cmd:capture-areaFile": "screenshot ekran dosya file",
        "cmd:capture-screenFile": "screenshot ekran dosya file", "cmd:capture-timed": "screenshot ekran timer zamanli",
        "cmd:capture-toolbar": "macos sistem system screenshot app uygulama araç",
        "cmd:rec-start": "kayıt kayit kaydet record recording video ekran screen studio film çek", "cmd:rec-latest": "kayıt kayit video son last recording düzenle edit film", "cmd:capture-text": "ocr text metin qr oku read",
        "cmd:download": "download indir video youtube yt mp3 ses", "cmd:qr": "qr kod code", "cmd:mic": "mic mikrofon mute sessiz",
        "cmd:sleep-15": "sleep uyut uyku timer", "cmd:sleep-30": "sleep uyut uyku", "cmd:sleep-60": "sleep uyut uyku",
        "cmd:sleep-90": "sleep uyut uyku", "cmd:sleep-off": "sleep uyku iptal",
        "cmd:menubar-hider": "menü çubuğu menu bar gizle hide simge icon sadeleştir tidy bartender ice",
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
            command("clipboard", "doc.on.clipboard", L("Pano geçmişi", "Clipboard history"), accessory: HotKey.label(.clipboard), keepOpen: true) { [weak self] in
                self?.cameFromLauncher = true
                self?.reset(mode: .clipboard)
            },
            command("note", "note.text", L("Notlar", "Notes"), accessory: HotKey.label(.note)) { NoteWindow.show() },
            command("note-new", "square.and.pencil", L("Yeni not", "New note")) {
                if Prefs.string(Prefs.notesApp) == "apple" { AppleNotes.create("") } else { NoteWindow.show(NoteStore.shared.create()) }
            },
            command("panel", "menubar.rectangle", L("Paneli aç", "Open the panel"), accessory: HotKey.label(.panel)) { HotKey.togglePanel() },
            command("history", "chart.xyaxis.line", L("Geçmiş grafikleri", "History charts")) { HistoryWindow.show() },
            command("settings", "gearshape", L("Nabız ayarları", "Nabız settings"), accessory: "⌘,") { SettingsWindow.show(nil) },
            command("schedules", "calendar.badge.clock", L("Zamanlanmış görevler", "Scheduled tasks")) { SettingsWindow.show(.schedules) },
        ]
        if Prefs.bool(Prefs.aiAsk) {
            items.append(command("ai-chat", "sparkles", L("AI sohbet", "AI chat")) { AIChatWindow.show() })
            items.append(command("ai-ask", "sparkles", L("AI'a sor", "Ask AI"), accessory: HotKey.label(.ai), keepOpen: true) { [weak self] in
                self?.reset(mode: .ai)
            })
        }
        for minutes in [5, 10, 25, 60] {
            items.append(command("timer-\(minutes)", "timer", L("Zamanlayıcı: \(minutes) dk", "Timer: \(minutes) min")) {
                CountdownTimer.shared.start(minutes: minutes)
            })
        }
        if CountdownTimer.shared.isRunning {
            items.append(command("timer-off", "timer", L("Zamanlayıcıyı durdur", "Stop the timer")) { CountdownTimer.shared.stop() })
        }
        items.append(command("menubar-hider", "menubar.arrow.up.rectangle",
                             Prefs.bool(Prefs.menuBarHider) ? (MenuBarHider.shared.folded ? L("Gizli simgeleri göster", "Show hidden menu bar icons")
                                                                                          : L("Menü çubuğu simgelerini gizle", "Hide menu bar icons"))
                                                            : L("Menü çubuğunu sadeleştir", "Tidy the menu bar")) {
            if Prefs.bool(Prefs.menuBarHider) { MenuBarHider.shared.toggle() } else { UserDefaults.standard.set(true, forKey: Prefs.menuBarHider) }
        })
        // Each dev server, by project and port: typing "port", "3000" or the project's name finds it.
        for server in PortCache.shared.servers {
            let pid = server.pid
            items.append(command("port-\(pid)", "stop.circle", L("Sunucuyu durdur: \(server.projectName)", "Stop server: \(server.projectName)"),
                                 subtitle: "\(server.tool) · port \(server.ports.map(String.init).joined(separator: ", "))",
                                 accessory: L("Dev sunucusu", "Dev server"), remember: false) {
                PortCache.shared.forget(pid: pid)
                Task.detached(priority: .userInitiated) { DevServers.stop(pid) }
            })
        }
        let pomodoro = Pomodoro.shared
        if pomodoro.isActive {
            items.append(command("pomodoro-toggle", pomodoro.isRunning ? "pause.circle" : "play.circle",
                                 pomodoro.isRunning ? L("Pomodoro'yu duraklat", "Pause the Pomodoro") : L("Pomodoro'ya devam et", "Resume the Pomodoro"),
                                 accessory: pomodoro.remainingText) { pomodoro.toggle() })
            items.append(command("pomodoro-skip", "forward.end", L("Pomodoro: sıradakine geç", "Pomodoro: skip to next")) { pomodoro.skip() })
            items.append(command("pomodoro-stop", "stop.circle", L("Pomodoro'yu bitir", "Stop the Pomodoro")) { pomodoro.stop() })
        } else {
            items.append(command("pomodoro", "brain.head.profile", L("Pomodoro başlat (\(pomodoro.minutes(.work)) dk)", "Start a Pomodoro (\(pomodoro.minutes(.work)) min)"),
                                 accessory: pomodoro.today.count > 0 ? L("bugün \(pomodoro.today.count)", "\(pomodoro.today.count) today") : nil) {
                pomodoro.start()
            })
        }
        let focus = FocusMode.shared
        if focus.isOn {
            items.append(command("focus-off", "moon.circle.fill", L("Odak modunu kapat", "Turn focus mode off"), accessory: focus.remainingText) { focus.stop() })
        }
        for (minutes, label) in [(25, L("25 dk", "25 min")), (60, L("1 saat", "1 hour")), (120, L("2 saat", "2 hours"))] {
            items.append(command("focus-\(minutes)", "moon.circle", L("Odak modu: \(label)", "Focus mode: \(label)")) { focus.start(minutes: minutes) })
        }
        items.append(command("focus-on", "moon.circle", L("Odak modu: süresiz", "Focus mode: until I stop it")) { focus.start(minutes: nil) })
        for mode in CaptureMode.allCases {
            items.append(command("capture-\(mode.rawValue)", mode.symbol, L("Ekran görüntüsü: ", "Screenshot: ") + mode.title,
                                 accessory: mode == .area && Prefs.bool(Prefs.shotHotkey) ? HotKey.label(.screenshot) : nil) { Capture.run(mode) })
        }
        if NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil) {
            items.append(command("shot-clipboard", "pencil.tip.crop.circle", L("Panodaki resmi düzenle", "Mark up the copied image")) { ShotEditor.showClipboard() })
        }
        items.append(command("shot-open", "photo.badge.plus", L("Resim dosyasını düzenle…", "Mark up an image file…")) { ShotEditor.choose() })
        items.append(command("rec-start", RecRecorder.shared.isRecording ? "stop.circle" : "record.circle",
                             RecRecorder.shared.isRecording ? L("Ekran kaydını durdur", "Stop the screen recording") : L("Ekranı kaydet", "Record the screen"),
                             accessory: Prefs.bool(Prefs.recHotkey) ? HotKey.label(.record) : nil) { RecControl.toggle() })
        items.append(command("rec-latest", "film", L("Son ekran kaydını aç", "Open the last screen recording")) { RecEditor.showLatest() })
        items.append(command("download", "arrow.down.circle", L("Video indir (panodaki bağlantı)", "Download video (copied link)"), keepOpen: true) { [weak self] in
            if let url = NSPasteboard.general.string(forType: .string).flatMap(Downloader.videoURL) {
                self?.text = url.absoluteString
            } else {
                Monitor.panelActions.flash(L("Önce bir video bağlantısı kopyala", "Copy a video link first"))
            }
        })
        if let copied = NSPasteboard.general.string(forType: .string), !copied.isEmpty, copied.count < 2000 {
            items.append(command("qr", "qrcode", L("Panodaki metinden QR kodu", "QR code from the clipboard")) { Capture.copyQR(copied) })
        }
        let muted = Toolbox.shared.micMuted
        items.append(command("mic", muted ? "mic" : "mic.slash", muted ? L("Mikrofonu aç", "Unmute the mic") : L("Mikrofonu kapat", "Mute the mic")) {
            Microphone.toggle()
            Toolbox.shared.refreshMic()
        })
        items.append(command("dictation", "mic.badge.plus", Dictation.shared.isListening ? L("Dikteyi bitir", "Finish dictation") : L("Dikte et", "Dictate"),
                             accessory: Prefs.bool(Prefs.dictationHotkey) ? HotKey.label(.dictation) : nil) { Dictation.shared.toggle() })
        if Prefs.bool(Prefs.aiAsk) {
            for aiCommand in AICommandStore.shared.commands {
                items.append(LauncherItem(id: aiCommand.commandID, icon: .symbol("sparkles"), title: "AI: \(aiCommand.name)",
                                          subtitle: L("seçili ya da kopyalanan metinle", "on the selected or copied text"),
                                          accessory: "AI", primaryTitle: L("Çalıştır", "Run"),
                                          primary: { [weak self] in self?.runAICommand(aiCommand, on: nil) }))
            }
        }
        let agenda = CalendarAgenda.shared
        if Prefs.bool(Prefs.calendarEnabled) && agenda.authorized {
            if let next = agenda.upcoming.first(where: { $0.meetingURL != nil && !$0.allDay && $0.end > Date() }) {
                items.append(command("calendar-join", "video", L("Toplantıya katıl: \(next.title)", "Join: \(next.title)"),
                                     accessory: CalendarAgenda.untilText(next)) { agenda.join(next) })
            }
            items.append(command("calendar", "calendar", L("Takvim", "Calendar"),
                                 accessory: agenda.next.map { CalendarAgenda.untilText($0) }) { agenda.openInCalendar() })
        }
        let soundMuted = SoundOutput.isMuted
        items.append(command("volume-mute", soundMuted ? "speaker.wave.2" : "speaker.slash", soundMuted ? L("Sesi aç", "Unmute the sound") : L("Sesi kapat", "Mute the sound")) {
            SoundOutput.toggleMute()
        })
        items.append(command("volume-up", "speaker.plus", L("Sesi artır", "Volume up"), accessory: SoundOutput.volume.map { L("%\($0)", "\($0)%") }) { SoundOutput.change(by: 10) })
        items.append(command("volume-down", "speaker.minus", L("Sesi azalt", "Volume down"), accessory: SoundOutput.volume.map { L("%\($0)", "\($0)%") }) { SoundOutput.change(by: -10) })
        let current = SoundOutput.currentOutput
        for device in SoundOutput.outputs {
            items.append(LauncherItem(id: "audio:\(device.uid)", icon: .symbol(device.name.lowercased().contains("airpods") ? "airpods" : "hifispeaker"),
                                      title: L("Ses çıkışı: \(device.name)", "Sound output: \(device.name)"),
                                      accessory: device.id == current ? L("Şu an", "Current") : L("Ses", "Sound"), primaryTitle: L("Seç", "Select"),
                                      primary: { [weak self] in
                                          self?.close()
                                          SoundOutput.select(device)
                                      }))
        }
        if let at = SleepTimer.shared.at {
            items.append(command("sleep-off", "moon.zzz", L("Uyku zamanlayıcısını iptal et", "Cancel the sleep timer"),
                                 accessory: at.formatted(date: .omitted, time: .shortened)) { SleepTimer.shared.cancel() })
        }
        for minutes in [15, 30, 60, 90] {
            items.append(command("sleep-\(minutes)", "powersleep", L("\(minutes) dk sonra uyut", "Sleep in \(minutes) min")) { SleepTimer.shared.start(minutes: minutes) })
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
        for layout in WindowLayouts.shared.layouts {
            items.append(LauncherItem(id: layout.commandID, icon: .symbol("macwindow"),
                                      title: layout.appName.map { "\(layout.name) · \($0)" } ?? layout.name,
                                      accessory: L("Pencere", "Window"), primaryTitle: L("Uygula", "Apply"),
                                      primary: { [weak self] in
                                          self?.close()
                                          WindowLayouts.shared.apply(layout)
                                      }))
        }
        for name in WindowLayouts.shared.sets {
            items.append(LauncherItem(id: "layoutset:\(name)", icon: .symbol("rectangle.3.group"), title: L("Düzen: \(name)", "Set: \(name)"),
                                      accessory: L("Pencere", "Window"), primaryTitle: L("Uygula", "Apply"),
                                      primary: { [weak self] in
                                          self?.close()
                                          WindowLayouts.shared.applySet(name)
                                      }))
        }
        // These already exist as commands above (or open the launcher itself).
        for script in Extensions.shared.scripts {
            items.append(LauncherItem(id: "script:\(script.path)", icon: script.icon.map { .emoji($0) } ?? .symbol("terminal"),
                                      title: script.title, accessory: L("Betik", "Script"),
                                      primaryTitle: script.arguments.isEmpty ? L("Çalıştır", "Run") : L("Çalıştır…", "Run…"),
                                      primary: { [weak self] in
                                          if script.arguments.isEmpty { self?.runScript(script) } else { self?.enterArgument(.script(script)) }
                                      }))
        }
        for name in Extensions.shared.shortcuts {
            items.append(LauncherItem(id: "shortcut:\(name)", icon: .symbol("square.2.layers.3d"), title: name,
                                      accessory: L("Kestirme", "Shortcut"), primaryTitle: L("Çalıştır", "Run"),
                                      primary: { [weak self] in
                                          self?.close()
                                          Extensions.shared.runShortcut(name)
                                      }))
        }
        items.append(command("help", "questionmark.circle", L("Neler yapabilir?", "What can Nabız do?")) { HelpWindow.show() })
        let skip: Set<ToolKind> = [.aiChat, .calculator, .keepAwake, .timer, .clipboard, .note, .displayOff, .pomodoro, .focus, .screenshot,
                                   .readText, .download, .mic, .sleepTimer]
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

/// Apps, commands and quicklinks starred with ⇧⌘F; they head the launcher and rank higher in searches.
@MainActor
enum Favorites {
    private static let key = "launcherFavorites"

    static var ids: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func toggle(_ id: String) {
        var list = ids
        if let index = list.firstIndex(of: id) { list.remove(at: index) } else { list.append(id) }
        UserDefaults.standard.set(list, forKey: key)
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
        // Letters in order, starting at the start of a word ("sfr" finds Safari, "saf" doesn't find "display off").
        guard q.count >= 3, let first = q.first, let start = words.first(where: { $0.first == first })?.startIndex else { return nil }
        var rest = t[start...]
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

    /// A 40 px copy of the icon: the full one holds every size up to 1024 px, megabytes for a long list.
    func icon(_ path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let full = NSWorkspace.shared.icon(forFile: path)
        let size = NSSize(width: 20, height: 20)
        let small = NSImage(size: size, flipped: false) { rect in
            full.draw(in: rect)
            return true
        }
        // Draw once into a bitmap so the big original can go.
        let icon: NSImage
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            small.draw(in: NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            icon = NSImage(size: size)
            icon.addRepresentation(rep)
        } else {
            icon = small
        }
        if icons.count > 400 { icons.removeAll() }
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

// MARK: - Actions palette (⌘K)

/// One thing the palette can do with the selected row.
struct LauncherAction: Identifiable {
    let id: String
    var title: String
    var symbol: String
    var shortcut: String?
    /// Heading the action sits under; consecutive actions with the same one share it.
    var group = ""
    var destructive = false
    var run: @MainActor () -> Void
}

extension LauncherModel {
    var paletteActions: [LauncherAction] {
        let all: [LauncherAction]
        if mode == .ai && ai != nil {
            all = aiActions()
        } else {
            guard let item = selected else { return [] }
            all = actions(for: item)
        }
        let query = paletteQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { Fuzzy.score(query, $0.title) != nil || Fuzzy.keyword(query, $0.group) != nil }
    }

    func togglePalette() {
        paletteOpen = !paletteOpen && (selected != nil || (mode == .ai && ai != nil))
    }

    func movePalette(_ offset: Int) {
        let count = paletteActions.count
        guard count > 0 else { return }
        paletteSelection = (min(paletteSelection, count - 1) + offset + count) % count
    }

    func runPaletteAction(_ chosen: LauncherAction? = nil) {
        let actions = paletteActions
        guard let action = chosen ?? (actions.isEmpty ? nil : actions[min(paletteSelection, actions.count - 1)]) else { return }
        paletteOpen = false
        guard let item = selected else { action.run(); return }
        if item.remember && (action.id == "primary" || action.id == "secondary") { Recents.add(item.id) }
        action.run()
    }

    func toggleFavoriteSelected() {
        guard let item = selected, item.remember else { return }
        Favorites.toggle(item.id)
    }

    /// Everything that can be done with a row: its two main actions, then what fits its kind.
    func actions(for item: LauncherItem) -> [LauncherAction] {
        let main = L("Eylemler", "Actions")
        var list = [LauncherAction(id: "primary", title: item.primaryTitle, symbol: "return", shortcut: "↩", group: main, run: item.primary)]
        if let title = item.secondaryTitle, let secondary = item.secondary {
            list.append(LauncherAction(id: "secondary", title: title, symbol: "command", shortcut: "⌘↩", group: main, run: secondary))
        }
        let copyText: (String, String) -> Void = { [weak self] text, message in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            self?.close()
            Monitor.panelActions.flash(message)
        }
        list += devActions(for: item, group: main)

        if item.id.hasPrefix("app:") {
            let path = String(item.id.dropFirst(4))
            let running = NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == path }
            if let running {
                list.append(LauncherAction(id: "hide", title: L("Gizle", "Hide"), symbol: "eye.slash", group: main) { [weak self] in
                    self?.close()
                    running.hide()
                })
                list.append(LauncherAction(id: "finder", title: L("Finder'da göster", "Show in Finder"), symbol: "folder", group: main) { [weak self] in
                    self?.close()
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                })
                list.append(LauncherAction(id: "forceQuit", title: L("Zorla kapat…", "Force quit…"), symbol: "xmark.octagon", group: main,
                                           destructive: true) { [weak self] in
                    self?.close()
                    let alert = NSAlert()
                    alert.messageText = L("\(item.title) zorla kapatılsın mı?", "Force quit \(item.title)?")
                    alert.informativeText = L("Kaydedilmemiş değişiklikler kaybolur.", "Unsaved changes will be lost.")
                    alert.addButton(withTitle: L("Zorla kapat", "Force Quit"))
                    alert.addButton(withTitle: L("Vazgeç", "Cancel"))
                    alert.buttons.first?.hasDestructiveAction = true
                    NSApp.activate()
                    if alert.runModal() == .alertFirstButtonReturn { running.forceTerminate() }
                })
            }
            list.append(LauncherAction(id: "copyPath", title: L("Yolunu kopyala", "Copy path"), symbol: "doc.on.doc", group: main) {
                copyText(path, L("Kopyalandı", "Copied"))
            })
        }

        if let clip = item.clip {
            let current = ClipboardHistory.shared.items.first { $0.id == clip.id } ?? clip
            list.append(LauncherAction(id: "pin", title: current.pinned ? L("Sabitlemeyi kaldır", "Unpin") : L("Sabitle", "Pin"),
                                       symbol: current.pinned ? "pin.slash" : "pin", shortcut: "⌘P", group: main) {
                ClipboardHistory.shared.togglePin(current)
            })
            if let text = clip.text {
                if clip.kind == .link, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    list.append(LauncherAction(id: "open", title: L("Tarayıcıda aç", "Open in browser"), symbol: "safari", group: main) { [weak self] in
                        self?.close()
                        NSWorkspace.shared.open(url)
                    })
                }
                if let url = Downloader.videoURL(text) {
                    list.append(LauncherAction(id: "dlVideo", title: L("Videoyu indir", "Download the video"), symbol: "film", group: main) { [weak self] in
                        self?.close()
                        Downloader.shared.download(url.absoluteString, kind: .video)
                    })
                    list.append(LauncherAction(id: "dlAudio", title: L("Sesi indir", "Download the sound"), symbol: "music.note", group: main) { [weak self] in
                        self?.close()
                        Downloader.shared.download(url.absoluteString, kind: .audio)
                    })
                }
                if text.count < 2000 {
                    list.append(LauncherAction(id: "qr", title: L("QR kodu oluştur", "Make a QR code"), symbol: "qrcode", group: main) { [weak self] in
                        self?.close()
                        Capture.copyQR(text)
                    })
                }
                list.append(LauncherAction(id: "toNote", title: L("Not olarak kaydet", "Save as note"), symbol: "note.text.badge.plus", group: main) { [weak self] in
                    self?.close()
                    if Prefs.string(Prefs.notesApp) == "apple" { AppleNotes.create(text) } else { NoteWindow.show(NoteStore.shared.create(text)) }
                })
                list.append(LauncherAction(id: "toSnippet", title: L("Parçacık olarak kaydet", "Save as snippet"), symbol: "text.quote", group: main) { [weak self] in
                    self?.close()
                    let name = String(clip.preview.prefix(40))
                    LauncherStore.shared.save(snippet: Snippet(keyword: "", name: name, text: text))
                    SettingsWindow.show(.snippets)
                })
                if Prefs.bool(Prefs.aiAsk) {
                    for task in AITextTask.allCases {
                        list.append(LauncherAction(id: "ai-\(task.rawValue)", title: task.title, symbol: task.symbol, group: "AI") { [weak self] in
                            self?.runAI(task, on: text)
                        })
                    }
                    for command in AICommandStore.shared.commands {
                        list.append(LauncherAction(id: "aicmd-\(command.id)", title: command.name, symbol: "sparkles", group: "AI") { [weak self] in
                            self?.runAICommand(command, on: text)
                        })
                    }
                }
                let transform = L("Dönüştür ve yapıştır", "Transform and paste")
                for change in TextTransform.allCases {
                    guard let result = change.apply(text) else { continue }
                    list.append(LauncherAction(id: "t-\(change.rawValue)", title: change.title, symbol: change.symbol, group: transform) { [weak self] in
                        self?.paste(text: result)
                    })
                }
            }
            if clip.kind == .files, let files = clip.files {
                list.append(LauncherAction(id: "finder", title: L("Finder'da göster", "Show in Finder"), symbol: "folder", group: main) { [weak self] in
                    self?.close()
                    NSWorkspace.shared.activateFileViewerSelecting(files.map { URL(fileURLWithPath: $0) })
                })
            }
            list.append(LauncherAction(id: "delete", title: L("Geçmişten sil", "Delete from history"), symbol: "trash", shortcut: "⌘⌫",
                                       group: main, destructive: true) { [weak self] in
                if let self { selectNeighbour(of: item.id, in: items) }
                ClipboardHistory.shared.delete(current)
            })
        }

        if item.id.hasPrefix("note:"), let id = UUID(uuidString: String(item.id.dropFirst(5))),
           let note = NoteStore.shared.notes.first(where: { $0.id == id }) {
            list.append(LauncherAction(id: "pasteNote", title: L("Yapıştır", "Paste"), symbol: "doc.on.clipboard", group: main) { [weak self] in
                self?.paste(text: note.text)
            })
            list.append(LauncherAction(id: "deleteNote", title: L("Notu sil…", "Delete note…"), symbol: "trash", group: main, destructive: true) { [weak self] in
                self?.close()
                NoteWindow.delete(note)
            })
        }

        if item.id.hasPrefix("calc:"), let index = Int(item.id.dropFirst(5)) {
            let expression = text.trimmingCharacters(in: .whitespaces).hasPrefix("=")
                ? String(text.trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)
                : text.trimmingCharacters(in: .whitespaces)
            let results = Calculator.evaluateAll(expression)
            if results.indices.contains(index), !results[index].copy.isEmpty {
                let result = results[index]
                if let raw = result.raw, raw != result.copy {
                    list.append(LauncherAction(id: "copyRaw", title: L("Ham sayıyı kopyala (\(raw))", "Copy raw number (\(raw))"),
                                               symbol: "number", group: main) {
                        CalcHistory.add(expression, result)
                        copyText(raw, L("Kopyalandı", "Copied"))
                    })
                }
                list.append(LauncherAction(id: "copyAll", title: L("İşlemle birlikte kopyala", "Copy with the sum"), symbol: "text.append",
                                           group: main) {
                    CalcHistory.add(expression, result)
                    copyText(result.text.hasPrefix("= ") ? "\(expression) \(result.text)" : result.text, L("Kopyalandı", "Copied"))
                })
                if !Paster.canPaste {
                    list.append(LauncherAction(id: "allowPaste", title: L("Yapıştırmaya izin ver…", "Allow pasting…"), symbol: "hand.raised",
                                               group: main) { Paster.requestTrust() })
                }
            }
            list.append(LauncherAction(id: "history", title: L("Hesap geçmişi", "Calculation history"), symbol: "clock.arrow.circlepath",
                                       shortcut: "=", group: main) { [weak self] in self?.text = "=" })
        }

        if item.id.hasPrefix("calchist:") {
            list.append(LauncherAction(id: "clearHistory", title: L("Geçmişi temizle", "Clear history"), symbol: "trash", group: main,
                                       destructive: true) { [weak self] in
                CalcHistory.clear()
                self?.text = ""
            })
        }

        if item.id.hasPrefix("file:") {
            let url = URL(fileURLWithPath: String(item.id.dropFirst(5)))
            list.append(LauncherAction(id: "quickLook", title: L("Hızlı bakış", "Quick Look"), symbol: "eye", group: main) {
                Task { _ = await Toolbox.run("/usr/bin/qlmanage", ["-p", url.path]) }
            })
            list.append(LauncherAction(id: "copyFile", title: L("Dosyayı kopyala", "Copy the file"), symbol: "doc.on.doc", group: main) { [weak self] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
                self?.close()
                Monitor.panelActions.flash(L("Dosya kopyalandı", "File copied"))
            })
            list.append(LauncherAction(id: "copyPath", title: L("Yolunu kopyala", "Copy path"), symbol: "text.cursor", group: main) {
                copyText(url.path, L("Kopyalandı", "Copied"))
            })
            list.append(LauncherAction(id: "trash", title: L("Çöp Sepeti'ne taşı", "Move to Trash"), symbol: "trash", group: main,
                                       destructive: true) { [weak self] in
                NSWorkspace.shared.recycle([url]) { _, error in
                    MainActor.assumeIsolated {
                        Monitor.panelActions.flash(error == nil ? L("Çöpe taşındı", "Moved to Trash") : L("Taşınamadı", "Couldn't move"))
                    }
                }
                self?.close()
            })
        }

        if item.id.hasPrefix("snippet:") {
            list.append(LauncherAction(id: "editSnippet", title: L("Parçacıkları düzenle", "Edit snippets"), symbol: "pencil", group: main) { [weak self] in
                self?.close()
                SettingsWindow.show(.snippets)
            })
        }

        if item.id.hasPrefix("link:") || item.id == "search" {
            let words = text.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init)
            let links = LauncherStore.shared.quicklinks
            let typed = text.trimmingCharacters(in: .whitespaces)
            var pair: (Quicklink, String)? = item.id.hasPrefix("link:")
                ? links.first { "link:\($0.keyword)" == item.id }.map { ($0, "") }
                : words.count == 2 ? links.first { $0.keyword.lowercased() == words[0].lowercased() }.map { ($0, words[1]) }
                    ?? LauncherStore.shared.webSearch.map { ($0, typed) }
                : LauncherStore.shared.webSearch.map { ($0, typed) }
            if let argument, case .quicklink(let link) = argument.target { pair = (link, typed) }
            if let (link, query) = pair, let url = link.url(for: query) {
                list.append(LauncherAction(id: "copyLink", title: L("Bağlantıyı kopyala", "Copy link"), symbol: "link", group: main) {
                    copyText(url.absoluteString, L("Kopyalandı", "Copied"))
                })
            }
            list.append(LauncherAction(id: "editLinks", title: L("Bağlantıları düzenle", "Edit quicklinks"), symbol: "pencil", group: main) { [weak self] in
                self?.close()
                SettingsWindow.show(.launcher)
            })
        }

        if item.remember && (item.id.hasPrefix("app:") || item.id.hasPrefix("cmd:") || item.id.hasPrefix("sys:") || item.id.hasPrefix("win:") || item.id.hasPrefix("layout") || item.id.hasPrefix("aicmd:")
                             || item.id.hasPrefix("tool:") || item.id.hasPrefix("link:") || item.id.hasPrefix("script:")
                             || item.id.hasPrefix("shortcut:") || item.id.hasPrefix("audio:") || item.id.hasPrefix("bt:") || item.id.hasPrefix("proj:")) {
            let launcher = L("Başlatıcı", "Launcher")
            let binding = ItemBindings.shared.binding(item.id)
            let title = item.title
            list.append(LauncherAction(id: "bindKey", title: binding?.combo.map { L("Kısayolu değiştir (\($0.label))…", "Change shortcut (\($0.label))…") }
                                           ?? L("Kısayol ata…", "Set a shortcut…"),
                                       symbol: "keyboard", group: launcher) { [weak self] in
                self?.close()
                ItemBindings.shared.askCombo(id: item.id, title: title)
            })
            list.append(LauncherAction(id: "bindAlias", title: binding?.alias.map { L("Takma adı değiştir (\($0))…", "Change alias (\($0))…") }
                                           ?? L("Takma ad ver…", "Set an alias…"),
                                       symbol: "character.cursor.ibeam", group: launcher) { [weak self] in
                self?.close()
                ItemBindings.shared.askAlias(id: item.id, title: title)
            })
        }

        if item.remember {
            let starred = Favorites.ids.contains(item.id)
            list.append(LauncherAction(id: "favorite", title: starred ? L("Favorilerden çıkar", "Remove from favourites") : L("Favorilere ekle", "Add to favourites"),
                                       symbol: starred ? "star.slash" : "star", shortcut: "⇧⌘F", group: L("Başlatıcı", "Launcher")) {
                Favorites.toggle(item.id)
            })
        }
        return list
    }
}
