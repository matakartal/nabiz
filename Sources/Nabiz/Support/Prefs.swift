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
    /// "stacked": a small label over a bold value, two lines like the system's own items; "line": one line.
    static let barStyle = "barStyle"
    /// AI limits show what is left ("6% left") instead of what is used ("94%").
    static let aiRemaining = "aiRemaining"

    static let showSystem = "showSystem"
    static let showCPUApps = "showCPUApps"
    /// Section headers fold their section open and shut.
    static let collapsible = "collapsible"
    /// Opening one section closes the others.
    static let accordion = "accordion"
    static let showAdvice = "showAdvice"
    static let showSimulators = "showSimulators"
    static let showApps = "showApps"
    static let showCurrency = "showCurrency"
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
    static let launcherClipboard = "launcherClipboard"
    /// ⌃⌥ arrows, Return and C move the front window.
    static let windowHotkeys = "windowHotkeys"
    /// The single note of 1.5, moved into the notes list on first launch.
    static let noteText = "floatingNote"
    static let noteOnTop = "noteOnTop"
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

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            language: "system", refreshSeconds: 5, hotkey: true, panelHotkey: true, notifications: false, onboarded: false,
            barIcon: false, barLabels: true, barCPU: true, barRAM: true, barGPU: false, barNetwork: false,
            barStyle: "stacked", aiRemaining: true, barMarket: false, barMarketID: "",
            showMarkets: true, hiddenTools: "", accentColor: "green", textSize: "normal", panelWidth: 320,
            panelStyle: "material", barColors: false, rustAutoClean: false, rustAutoCleanDays: 14, watchedMarkets: "BTC,ETH,SOL,xyz:XYZ100,xyz:TSLA,xyz:GOLD", "expanded.markets": true, barSwap: false, barDisk: false, barBattery: false, barAI: false, barCurrency: false,
            showSystem: true, showCPUApps: true, collapsible: true, accordion: false,
            "expanded.system": true, "expanded.advice": true, "expanded.simulators": true, "expanded.ai": true,
            "expanded.memory": true, "expanded.cpu": true, "expanded.currency": true, "expanded.tools": true,
            showAdvice: true, showSimulators: true, showApps: true, showCurrency: true, showTools: true, showAI: true,
            "ai.claude": false, "ai.codex": false, "ai.gemini": false,
            memoryAppCount: 5, cpuAppCount: 3,
            baseCurrency: "TRY", watchedCurrencies: "USD,EUR,GBP",
            clipboardHotkey: true, clipboardEnabled: true, clipboardSave: true, clipboardLimit: 200, clipboardDays: 30,
            clipboardExcluded: "", autoPaste: true, launcherApps: true, launcherClipboard: true, windowHotkeys: false,
            noteOnTop: true, noteHotkey: true,
            pomodoroWork: 25, pomodoroShort: 5, pomodoroLong: 15, pomodoroLongEvery: 4, pomodoroAuto: true, pomodoroFocus: true,
            focusBlocked: "", focusHideOthers: false, focusHideDesktop: false, focusShortcutOn: "", focusShortcutOff: "",
            downloadQuality: "best", downloadFolder: "",
            appearanceMode: "system", fontDesign: "standard", density: "normal", meterStyle: "thin",
            barSymbol: "gauge.with.dots.needle.33percent", customAccent: "#1DB954", sectionOrder: "",
        ])
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
    case system, advice, simulators, ai, memory, cpu, markets, currency, tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L("Sistem", "System")
        case .advice: L("Öneriler", "Suggestions")
        case .simulators: L("Simülatörler", "Simulators")
        case .ai: L("AI limitleri", "AI limits")
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
        case .ai: Prefs.showAI
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
        case .ai: "sparkles"
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
        let saved = Prefs.string(Prefs.sectionOrder).split(separator: ",").compactMap { PanelSection(rawValue: String($0)) }
        return saved + allCases.filter { !saved.contains($0) }
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
    case cpu, ram, gpu, swap, network, disk, battery, ai, market, currency
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
        case .timer: L("Zamanlayıcı", "Timer")
        }
    }
}

/// The app speaks Turkish and English. Every user-facing string is written in both, side by side.
func L(_ tr: String, _ en: String) -> String { Prefs.isTurkish ? tr : en }
