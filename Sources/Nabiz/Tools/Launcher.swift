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
    /// The ⌘K actions palette for the selected row.
    var paletteOpen = false {
        didSet { paletteQuery = ""; paletteSelection = 0 }
    }
    var paletteQuery = "" {
        didSet { if paletteQuery != oldValue { paletteSelection = 0 } }
    }
    var paletteSelection = 0
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
            let all = commands + apps + LauncherStore.shared.quicklinks.map { searchItem($0, "") }
            let favorites = Favorites.ids.compactMap { id in all.first { $0.id == id } }
            sections.append(LauncherSection(id: "favorites", title: L("Favoriler", "Favourites"), items: favorites))
            let recents = Recents.ids.compactMap { id in all.first { $0.id == id } }.filter { item in !favorites.contains { $0.id == item.id } }
            sections.append(LauncherSection(id: "recents", title: L("Son kullanılanlar", "Recent"), items: recents))
            if Prefs.bool(Prefs.clipboardEnabled) && Prefs.bool(Prefs.launcherClipboard) {
                let clips = ClipboardHistory.shared.items.prefix(3).map(clipRow)
                sections.append(LauncherSection(id: "clips", title: L("Son kopyalananlar", "Recently copied"), items: Array(clips)))
            }
            let downloads = Downloader.shared.jobs.prefix(3).map(jobItem)
            sections.append(LauncherSection(id: "downloads", title: L("İndirilenler", "Downloads"), items: Array(downloads)))
            let suggested = ["cmd:clipboard", "cmd:note", "cmd:pomodoro", "cmd:focus-25", "cmd:capture-area", "sys:lock", "win:leftHalf"]
            let suggestions = suggested.compactMap { id in commands.first { $0.id == id } }
                .filter { item in !recents.contains { $0.id == item.id } && !favorites.contains { $0.id == item.id } }
            sections.append(LauncherSection(id: "suggestions", title: L("Öneriler", "Suggestions"), items: suggestions))
            return sections.filter { !$0.items.isEmpty }
        }

        // Maths, money, units, time zones and dates first.
        let results = Calculator.evaluateAll(query)
        if !results.isEmpty {
            sections.append(LauncherSection(id: "calc", title: L("Hesap", "Calculator"),
                                            items: results.enumerated().map { calcItem($1, index: $0, expression: query) }))
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
                                        items: ranked(commands + timerItems(query), keywords: { Self.keywords[$0.id] ?? $0.id.split(separator: ":").last.map(String.init) ?? "" }, limit: 8)))

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
        "cmd:note": "note not notes notlar yüzen floating", "cmd:note-new": "note not new yeni", "cmd:schedules": "schedule görev zamanla tasks",
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
        "cmd:capture-toolbar": "screenshot record kayit video ekran", "cmd:capture-text": "ocr text metin qr oku read",
        "cmd:download": "download indir video youtube yt mp3 ses", "cmd:qr": "qr kod code", "cmd:mic": "mic mikrofon mute sessiz",
        "cmd:sleep-15": "sleep uyut uyku timer", "cmd:sleep-30": "sleep uyut uyku", "cmd:sleep-60": "sleep uyut uyku",
        "cmd:sleep-90": "sleep uyut uyku", "cmd:sleep-off": "sleep uyku iptal",
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
            command("note", "note.text", L("Notlar", "Notes"), accessory: "⌃⌥M") { NoteWindow.show() },
            command("note-new", "square.and.pencil", L("Yeni not", "New note")) { NoteWindow.show(NoteStore.shared.create()) },
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
            items.append(command("capture-\(mode.rawValue)", mode.symbol, L("Ekran görüntüsü: ", "Screenshot: ") + mode.title) { Capture.run(mode) })
        }
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
        // These already exist as commands above (or open the launcher itself).
        let skip: Set<ToolKind> = [.calculator, .keepAwake, .timer, .clipboard, .note, .displayOff, .pomodoro, .focus, .screenshot,
                                   .readText, .download, .mic]
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
        guard let item = selected else { return [] }
        let all = actions(for: item)
        let query = paletteQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { Fuzzy.score(query, $0.title) != nil || Fuzzy.keyword(query, $0.group) != nil }
    }

    func togglePalette() {
        paletteOpen = !paletteOpen && selected != nil
    }

    func movePalette(_ offset: Int) {
        let count = paletteActions.count
        guard count > 0 else { return }
        paletteSelection = (min(paletteSelection, count - 1) + offset + count) % count
    }

    func runPaletteAction(_ chosen: LauncherAction? = nil) {
        let actions = paletteActions
        guard let item = selected, let action = chosen ?? (actions.isEmpty ? nil : actions[min(paletteSelection, actions.count - 1)]) else { return }
        paletteOpen = false
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
                    NoteWindow.show(NoteStore.shared.create(text))
                })
                list.append(LauncherAction(id: "toSnippet", title: L("Parçacık olarak kaydet", "Save as snippet"), symbol: "text.quote", group: main) { [weak self] in
                    self?.close()
                    let name = String(clip.preview.prefix(40))
                    LauncherStore.shared.save(snippet: Snippet(keyword: "", name: name, text: text))
                    SettingsWindow.show(.snippets)
                })
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
                ClipboardHistory.shared.delete(current)
                if let self { selection = min(selection, max(items.count - 1, 0)) }
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

        if item.id.hasPrefix("snippet:") {
            list.append(LauncherAction(id: "editSnippet", title: L("Parçacıkları düzenle", "Edit snippets"), symbol: "pencil", group: main) { [weak self] in
                self?.close()
                SettingsWindow.show(.snippets)
            })
        }

        if item.id.hasPrefix("link:") || item.id == "search" {
            let words = text.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init)
            let links = LauncherStore.shared.quicklinks
            let pair: (Quicklink, String)? = item.id.hasPrefix("link:")
                ? links.first { "link:\($0.keyword)" == item.id }.map { ($0, "") }
                : words.count == 2 ? links.first { $0.keyword.lowercased() == words[0].lowercased() }.map { ($0, words[1]) }
                    ?? links.first.map { ($0, text.trimmingCharacters(in: .whitespaces)) }
                : links.first.map { ($0, text.trimmingCharacters(in: .whitespaces)) }
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
