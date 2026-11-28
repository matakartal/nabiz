// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation

/// Every setting lives in UserDefaults under these keys, so the settings window (@AppStorage)
/// and the menu (Prefs) read the same values.
enum Prefs {
    static let language = "language"
    static let refreshSeconds = "refreshSeconds"
    /// ⌃⌥Space opens the launcher (it was the quick calculator; the key stays so the setting carries over).
    static let hotkey = "calculatorHotkey"
    static let panelHotkey = "panelHotkey"
    /// Alerts for critical memory and an almost-used AI limit.
    static let notifications = "notifications"
    /// The welcome window has been shown.
    static let onboarded = "onboarded"

    static let barIcon = "barIcon"
    static let barLabels = "barLabels"
    static let barCPU = "barCPU"
    static let barRAM = "barRAM"
    static let barGPU = "barGPU"
    static let barNetwork = "barNetwork"
    static let barSwap = "barSwap"
    static let barDisk = "barDisk"
    static let barBattery = "barBattery"
    static let barAI = "barAI"
    static let barCurrency = "barCurrency"
    static let barWeather = "barWeather"
    /// "stacked": a small label over a bold value, two lines like the system's own items; "line": one line.
    static let barStyle = "barStyle"
    /// AI limits show what is left ("6% left") instead of what is used ("94%").
    static let aiRemaining = "aiRemaining"
    /// AI accounts: nicknames by account ("Work", "Personal"), the ones turned off, and CLI folders added by hand.
    static let aiNicknames = "aiNicknames"
    static let aiHiddenAccounts = "aiHiddenAccounts"
    static let aiFolders = "aiFolders"
    /// The account whose limit the menu bar and the closed AI header show; "" follows the tightest one.
    static let aiBarAccount = "aiBarAccount"

    static let showSystem = "showSystem"
    static let showCPUApps = "showCPUApps"
    /// Section headers fold their section open and shut.
    static let collapsible = "collapsible"
    /// Opening one section closes the others.
    static let accordion = "accordion"
    static let showAdvice = "showAdvice"
    static let showSimulators = "showSimulators"
    /// The panel's dev servers (listening ports) section.
    static let showPorts = "showPorts"
    /// The panel's projects section (git repositories with work not committed or not pushed).
    static let showProjects = "showProjects"
    /// How many projects the panel lists.
    static let projectCount = "projectCount"
    /// The panel's Docker containers section.
    static let showDocker = "showDocker"
    /// Bundle id of the editor projects open in ("" = the first one installed).
    static let devEditor = "devEditor"
    /// "claude" or "codex": the coding agent a project's "Agent" button starts in Terminal.
    static let devAgent = "devAgent"
    /// Watches `notarytool` submissions and notifies when Apple answers.
    static let notaryWatch = "notaryWatch"
    /// The keychain profile `notarytool` uses (`xcrun notarytool store-credentials <profile>`).
    static let notaryProfile = "notaryProfile"
    /// node_modules in projects untouched this many days count as cleanable.
    static let devStaleDays = "devStaleDays"
    /// The panel's display brightness section (external displays over DDC).
    static let showDisplays = "showDisplays"
    /// The keyboard's brightness keys change the external display under the pointer.
    static let brightnessKeys = "brightnessKeys"
    /// A second menu bar item that hides the icons left of its divider.
    static let menuBarHider = "menuBarHider"
    /// Hidden icons fold away again this many seconds after they were shown (0 = stay).
    static let menuBarHiderDelay = "menuBarHiderDelay"
    static let showApps = "showApps"
    static let showCurrency = "showCurrency"
    static let showWeather = "showWeather"
    /// The weather's city (JSON of `WeatherStore.Place`); empty: found from the time zone.
    static let weatherPlace = "weatherPlace"
    /// "system", "c" or "f".
    static let weatherUnit = "weatherUnit"
    /// A panel row with the humidity and wind.
    static let weatherDetails = "weatherDetails"
    static let showTools = "showTools"
    static let showAI = "showAI"
    static let memoryAppCount = "memoryAppCount"
    static let cpuAppCount = "cpuAppCount"

    static let showMarkets = "showMarkets"
    /// Tool ids the user removed from the grid.
    static let hiddenTools = "hiddenTools"
    static let accentColor = "accentColor"
    static let textSize = "textSize"
    static let panelWidth = "panelWidth"
    /// "material" (frosted, like system menus) or "opaque".
    static let panelStyle = "panelStyle"
    /// Colour menu bar values that need attention (and market moves).
    static let barColors = "barColors"
    static let barAnimate = "barAnimate"
    /// Delete Rust build caches not built for `rustAutoCleanDays` days.
    static let rustAutoClean = "rustAutoClean"
    static let rustAutoCleanDays = "rustAutoCleanDays"
    /// Hyperliquid market ids, in the order they show: "BTC", "xyz:TSLA".
    static let watchedMarkets = "watchedMarkets"
    static let barMarket = "barMarket"
    /// Which watched market the menu bar shows ("" = the first one).
    static let barMarketID = "barMarketID"
    static let baseCurrency = "baseCurrency"
    static let watchedCurrencies = "watchedCurrencies"

    // Launcher, clipboard, windows.
    /// ⌃⌥V opens the clipboard history.
    static let clipboardHotkey = "clipboardHotkey"
    static let clipboardEnabled = "clipboardEnabled"
    /// Keep the history on disk across restarts.
    static let clipboardSave = "clipboardSave"
    static let clipboardLimit = "clipboardLimit"
    /// Forget unpinned items older than this many days (0 = never).
    static let clipboardDays = "clipboardDays"
    /// Bundle ids, comma separated, whose copies are never kept.
    static let clipboardExcluded = "clipboardExcluded"
    /// Return pastes into the app in front (needs Accessibility) instead of only copying.
    static let autoPaste = "autoPaste"
    static let launcherApps = "launcherApps"
    /// Shortcuts from the Shortcuts app appear as launcher commands.
    static let launcherShortcuts = "launcherShortcuts"
    /// Files from Spotlight appear in launcher searches (always with "/").
    static let launcherFiles = "launcherFiles"
    static let launcherClipboard = "launcherClipboard"
    /// ⌃⌥ arrows, Return and C move the front window.
    static let windowHotkeys = "windowHotkeys"
    /// The single note of 1.5, moved into the notes list on first launch.
    static let noteText = "floatingNote"
    static let noteOnTop = "noteOnTop"
    /// "nabiz" or "apple": which notes the note shortcut and tool open.
    static let notesApp = "notesApp"
    /// ⌃⌥M shows or hides the notes.
    static let noteHotkey = "noteHotkey"

    // Pomodoro and focus.
    static let pomodoroWork = "pomodoroWork"
    static let pomodoroShort = "pomodoroShort"
    static let pomodoroLong = "pomodoroLong"
    /// A long break after this many work blocks.
    static let pomodoroLongEvery = "pomodoroLongEvery"
    /// The next block starts by itself.
    static let pomodoroAuto = "pomodoroAuto"
    /// Work blocks turn focus mode on, breaks turn it off.
    static let pomodoroFocus = "pomodoroFocus"
    /// Bundle ids hidden during focus, comma separated ("" = the defaults).
    static let focusBlocked = "focusBlocked"
    static let focusHideOthers = "focusHideOthers"
    static let focusHideDesktop = "focusHideDesktop"
    /// Names of the user's Shortcuts that turn macOS Focus on and off.
    static let focusShortcutOn = "focusShortcutOn"
    static let focusShortcutOff = "focusShortcutOff"
    /// Websites kept away during focus (in Safari and Chromium browsers), comma separated domains.
    static let focusBlockSites = "focusBlockSites"
    static let focusSites = "focusSites"
    // MCP: AI apps using Nabız. Off until turned on; the clipboard needs its own yes.
    static let mcpEnabled = "mcpEnabled"
    static let mcpCommands = "mcpCommands"
    static let mcpNotes = "mcpNotes"
    static let mcpClipboard = "mcpClipboard"
    /// The clipboard's current text only (no history needed), behind its own yes.
    static let mcpClipboardNow = "mcpClipboardNow"
    /// Screenshots of the screen or an app's window.
    static let mcpScreen = "mcpScreen"
    /// Your own scripts and Shortcuts, and commands like sleep or lock, from run_command.
    static let mcpScripts = "mcpScripts"
    // Calendar: the panel section and the launcher's events (asks for access when turned on).
    static let calendarEnabled = "calendarEnabled"
    static let calendarHidden = "calendarHidden"
    static let calendarAlert = "calendarAlert"
    // Dictation: ⌃⌥D (off until turned on), and its language ("system", "tr", "en").
    static let dictationHotkey = "dictationHotkey"
    /// ⌃⌥S: select an area, copy it, show the thumbnail.
    static let shotHotkey = "shotHotkey"
    /// After a capture: "preview" (the thumbnail), "editor", or "none".
    static let shotAfter = "shotAfter"
    /// ⌃⌥R: start or stop a screen recording.
    static let recHotkey = "recHotkey"
    static let dictationLanguage = "dictationLanguage"
    /// A copy of the settings, snippets and notes in iCloud Drive once a day.
    static let autoBackup = "autoBackup"
    /// Video downloads: "best", "1080", "720" or "audio".
    static let downloadQuality = "downloadQuality"
    static let downloadFolder = "downloadFolder"

    // Personalization.
    /// "system", "light" or "dark": Nabız's own windows, whatever macOS uses.
    static let appearanceMode = "appearanceMode"
    /// "standard", "rounded" or "mono".
    static let fontDesign = "fontDesign"
    /// "compact", "normal" or "roomy" rows in the panel.
    static let density = "density"
    /// "thin" or "thick" usage bars.
    static let meterStyle = "meterStyle"
    /// The SF Symbol shown in the menu bar when the icon is on.
    static let barSymbol = "barSymbol"
    /// "#RRGGBB" for the custom accent.
    static let customAccent = "customAccent"
    /// Panel section ids, comma separated, in the order they show.
    static let sectionOrder = "sectionOrder"
    /// "Ask AI" in the launcher and AI actions on text.
    static let aiAsk = "aiAsk"
    /// Which AI answers: an AIEngine raw value ("auto", "claude", "codex", "gemini", "onDevice").
    static let aiEngine = "aiEngine"
    /// Chats are kept (encrypted) so they can be reopened.
    static let aiHistory = "aiHistory"
    /// ⌃⌥A opens the launcher ready to ask.
    static let aiHotkey = "aiHotkey"
    /// ⌃⌥I opens the AI chat window.
    static let aiChatHotkey = "aiChatHotkey"
    /// Claude keeps its own copy of each chat (in ~/.claude), so only new messages are sent.
    static let aiClaudeSessions = "aiClaudeSessions"
    /// A notification when an answer arrives while you're elsewhere.
    static let aiNotify = "aiNotify"
    /// A grey "what you might say next" in the empty message box (Apple's on-device model).
    static let aiSuggest = "aiSuggest"
    /// Claude, Codex and Grok may search the web when a question needs it.
    static let aiWebSearch = "aiWebSearch"
    /// "About you / how to answer": added to every chat's instructions.
    static let aiInstructions = "aiInstructions"
    /// Nabız also shows in the Dock and ⌘⇥, with a full menu bar (off: only the menu bar item).
    static let showInDock = "showInDock"
    /// The app version whose "New" note in the panel was seen or closed.
    static let seenVersion = "seenVersion"

    /// The Mac's own currency, so a new user abroad doesn't start in lira; US dollars when the region has none.
    static let defaultBaseCurrency = Locale.current.currency?.identifier ?? "USD"

    static func registerDefaults() {
        let defaults = UserDefaults.standard
        // Before this default followed the Mac's region it was lira. Someone who already used Nabız without picking
        // a currency keeps lira; only new users start from their region. Read before registering, so a stored value
        // is told apart from the default.
        if defaults.object(forKey: baseCurrency) == nil, defaults.object(forKey: onboarded) != nil {
            defaults.set("TRY", forKey: baseCurrency)
        }
        defaults.register(defaults: [
            language: "system", refreshSeconds: 5, hotkey: true, panelHotkey: true, notifications: false, onboarded: false,
            barIcon: false, barLabels: true, barCPU: true, barRAM: true, barGPU: false, barNetwork: false,
            barStyle: "stacked", aiRemaining: true, barMarket: false, barMarketID: "",
            showMarkets: true, hiddenTools: "", accentColor: "green", textSize: "normal", panelWidth: 320,
            panelStyle: "material", barColors: false, barAnimate: true, rustAutoClean: false, rustAutoCleanDays: 14, watchedMarkets: "BTC,ETH,SOL,xyz:XYZ100,xyz:TSLA,xyz:GOLD", "expanded.markets": true, barSwap: false, barDisk: false, barBattery: false, barAI: false, barCurrency: false,
            showSystem: true, showCPUApps: true, collapsible: true, accordion: false,
            "expanded.system": true, "expanded.advice": true, "expanded.simulators": true, "expanded.ports": true, "expanded.displays": true, "expanded.ai": true,
            "expanded.memory": true, "expanded.cpu": true, "expanded.currency": true, "expanded.tools": true,
            showAdvice: true, showSimulators: true, showPorts: true, showProjects: true, projectCount: 5, showDocker: true,
            devEditor: "", devAgent: "claude", notaryWatch: true, notaryProfile: "", devStaleDays: 30,
            "expanded.projects": true, "expanded.docker": true, showDisplays: true, brightnessKeys: false,
            menuBarHider: false, menuBarHiderDelay: 10, showApps: true, showCurrency: true, showWeather: true, barWeather: false, weatherUnit: "system", weatherDetails: false, "expanded.weather": false, showTools: true, showAI: true,
            "ai.claude": false, "ai.codex": false, "ai.gemini": false, "ai.grok": false,
            memoryAppCount: 5, cpuAppCount: 3,
            baseCurrency: defaultBaseCurrency, watchedCurrencies: "USD,EUR,GBP", aiBarAccount: AIFeatured.tightest,
            clipboardHotkey: true, clipboardEnabled: true, clipboardSave: true, clipboardLimit: 200, clipboardDays: 30,
            clipboardExcluded: "", autoPaste: true, launcherApps: true, launcherClipboard: true, launcherShortcuts: true, launcherFiles: true, windowHotkeys: false,
            noteOnTop: true, noteHotkey: true, notesApp: "nabiz",
            pomodoroWork: 25, pomodoroShort: 5, pomodoroLong: 15, pomodoroLongEvery: 4, pomodoroAuto: true, pomodoroFocus: true,
            focusBlocked: "", focusHideOthers: false, focusHideDesktop: false, focusShortcutOn: "", focusShortcutOff: "", focusBlockSites: false, focusSites: "", mcpEnabled: false, mcpCommands: true, mcpNotes: true, mcpClipboard: false, mcpClipboardNow: false, mcpScreen: false, mcpScripts: false,
            calendarEnabled: false, calendarHidden: "", calendarAlert: true, dictationHotkey: false, shotHotkey: true, shotAfter: "preview", recHotkey: true, dictationLanguage: "system", autoBackup: false,
            downloadQuality: "best", downloadFolder: "",
            appearanceMode: "system", fontDesign: "standard", density: "normal", meterStyle: "thin",
            barSymbol: "gauge.with.dots.needle.33percent", customAccent: "#1DB954", sectionOrder: "",
            aiAsk: true, aiEngine: "onDevice", aiHistory: true, aiHotkey: true, aiChatHotkey: true, aiClaudeSessions: true, aiNotify: true, aiSuggest: true, aiWebSearch: true, aiInstructions: "", showInDock: false, seenVersion: "",
        ])
        AdviceKind.registerDefaults()
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func int(_ key: String) -> Int { UserDefaults.standard.integer(forKey: key) }
    static func string(_ key: String) -> String { UserDefaults.standard.string(forKey: key) ?? "" }

    static var isTurkish: Bool {
        switch string(language) {
        case "tr": true
        case "en": false
        default: systemIsTurkish
        }
    }

    private static let systemIsTurkish = (Locale.preferredLanguages.first ?? "en").hasPrefix("tr")

    static var watched: [String] {
        string(watchedCurrencies).split(separator: ",").map(String.init)
    }
}

/// The panel's foldable sections, in the order they appear.
enum PanelSection: String, CaseIterable, Identifiable {
    case system, advice, simulators, ports, projects, docker, displays, ai, calendar, weather, memory, cpu, markets, currency, tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L("Sistem", "System")
        case .advice: L("Öneriler", "Suggestions")
        case .simulators: L("Simülatörler", "Simulators")
        case .ports: L("Dev sunucuları", "Dev servers")
        case .projects: L("Projeler", "Projects")
        case .docker: "Docker"
        case .displays: L("Ekranlar", "Displays")
        case .ai: "AI"
        case .calendar: L("Takvim", "Calendar")
        case .weather: L("Hava durumu", "Weather")
        case .memory: L("En çok bellek", "Top memory")
        case .cpu: L("En çok işlemci", "Top CPU")
        case .markets: L("Piyasalar", "Markets")
        case .currency: L("Döviz", "Exchange rates")
        case .tools: L("Araçlar", "Tools")
        }
    }

    var showKey: String {
        switch self {
        case .system: Prefs.showSystem
        case .advice: Prefs.showAdvice
        case .simulators: Prefs.showSimulators
        case .ports: Prefs.showPorts
        case .projects: Prefs.showProjects
        case .docker: Prefs.showDocker
        case .displays: Prefs.showDisplays
        case .ai: Prefs.showAI
        case .calendar: Prefs.calendarEnabled
        case .weather: Prefs.showWeather
        case .memory: Prefs.showApps
        case .cpu: Prefs.showCPUApps
        case .markets: Prefs.showMarkets
        case .currency: Prefs.showCurrency
        case .tools: Prefs.showTools
        }
    }

    var symbol: String {
        switch self {
        case .system: "gauge.with.dots.needle.50percent"
        case .advice: "lightbulb"
        case .simulators: "iphone"
        case .ports: "network"
        case .projects: "folder"
        case .docker: "shippingbox"
        case .displays: "sun.max"
        case .ai: "sparkles"
        case .calendar: "calendar"
        case .weather: "cloud.sun"
        case .memory: "memorychip"
        case .cpu: "cpu"
        case .markets: "chart.line.uptrend.xyaxis"
        case .currency: "dollarsign.circle"
        case .tools: "wrench.and.screwdriver"
        }
    }

    var expandedKey: String { "expanded.\(rawValue)" }

    /// In the order chosen in Settings → Panel; sections added in later versions go to the end.
    static var ordered: [PanelSection] {
        var list = Prefs.string(Prefs.sectionOrder).split(separator: ",").compactMap { PanelSection(rawValue: String($0)) }
        guard !list.isEmpty else { return allCases }
        // A section added in a later version goes right after the one it follows in the default order.
        for (index, section) in allCases.enumerated() where !list.contains(section) {
            let before = allCases[..<index].last { list.contains($0) }
            list.insert(section, at: before.flatMap { list.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        }
        return list
    }

    static func move(_ section: PanelSection, by offset: Int) {
        var list = ordered
        guard let index = list.firstIndex(of: section), list.indices.contains(index + offset) else { return }
        list.swapAt(index, index + offset)
        UserDefaults.standard.set(list.map(\.rawValue).joined(separator: ","), forKey: Prefs.sectionOrder)
    }

    var isExpanded: Bool { UserDefaults.standard.object(forKey: expandedKey) as? Bool ?? true }

    /// Opens or closes the section; in accordion mode opening it closes every other one.
    func setExpanded(_ open: Bool) {
        if open && Prefs.bool(Prefs.accordion) {
            for other in Self.allCases where other != self { UserDefaults.standard.set(false, forKey: other.expandedKey) }
        }
        UserDefaults.standard.set(open, forKey: expandedKey)
    }

    func toggle() { setExpanded(!isExpanded) }
}

/// What the status item can show, in the order it shows them.
enum MenuBarItem: String, CaseIterable, Identifiable {
    case cpu, ram, gpu, swap, network, disk, battery, ai, market, currency, weather
    /// Not a setting: shown automatically while a timer runs.
    case timer

    var id: String { rawValue }

    var key: String {
        switch self {
        case .cpu: Prefs.barCPU
        case .ram: Prefs.barRAM
        case .gpu: Prefs.barGPU
        case .swap: Prefs.barSwap
        case .network: Prefs.barNetwork
        case .disk: Prefs.barDisk
        case .battery: Prefs.barBattery
        case .ai: Prefs.barAI
        case .market: Prefs.barMarket
        case .currency: Prefs.barCurrency
        case .weather: Prefs.barWeather
        case .timer: "barTimer"
        }
    }

    var title: String {
        switch self {
        case .cpu: L("İşlemci (CPU)", "Processor (CPU)")
        case .ram: L("Bellek (RAM)", "Memory (RAM)")
        case .gpu: L("Grafik (GPU)", "Graphics (GPU)")
        case .swap: L("Takas alanı", "Swap")
        case .network: L("Ağ hızı", "Network speed")
        case .disk: L("Boş disk", "Free disk")
        case .battery: L("Pil", "Battery")
        case .ai: L("AI limiti", "AI limit")
        case .market: L("Piyasa fiyatı", "Market price")
        case .currency: L("Döviz kuru", "Exchange rate")
        case .weather: L("Hava durumu", "Weather")
        case .timer: L("Zamanlayıcı", "Timer")
        }
    }
}

/// The app speaks Turkish and English. Every user-facing string is written in both, side by side.
func L(_ tr: String, _ en: String) -> String { Prefs.isTurkish ? tr : en }
