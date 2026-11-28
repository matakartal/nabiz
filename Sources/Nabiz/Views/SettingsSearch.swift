// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import SwiftUI

/// Where a sidebar row leads: a page, or one section on it.
struct SettingsTarget: Hashable {
    let page: SettingsPage
    let anchor: String?
}

/// One search result.
struct SettingsHit: Identifiable, Hashable {
    let target: SettingsTarget
    let title: String
    let score: Double
    var id: String { target.page.rawValue + "/" + (target.anchor ?? "") + "/" + title }
}

/// A searchable setting: its name in both languages, the section it sits in and words people might type for it.
struct SettingsEntry {
    let page: SettingsPage
    let anchor: String
    let tr: String
    let en: String
    let words: String

    init(_ page: SettingsPage, _ anchor: String, _ tr: String, _ en: String, _ words: String = "") {
        self.page = page
        self.anchor = anchor
        self.tr = tr
        self.en = en
        self.words = words
    }
}

/// Settings search: every page and every setting, matched in Turkish and English, without accents, by word
/// beginnings and with one typo forgiven, ranked so a setting's own name beats a loose keyword.
enum SettingsIndex {
    static func search(_ query: String, limit: Int = 40) -> [SettingsHit] {
        let tokens = words(query)
        guard !tokens.isEmpty else { return [] }
        let phrase = fold(query.trimmingCharacters(in: .whitespaces))
        var hits: [SettingsHit] = []
        for page in SettingsPage.allCases {
            let fields: [(String, Double)] = [(page.names.tr + " " + page.names.en, 3),
                                              (page.subtitle, 1), (page.keywords, 1.2)]
            if let score = score(tokens, phrase: phrase, title: page.title, fields: fields) {
                hits.append(SettingsHit(target: SettingsTarget(page: page, anchor: nil), title: page.title, score: score + 0.5))
            }
        }
        for entry in entries {
            let title = L(entry.tr, entry.en)
            let fields: [(String, Double)] = [(entry.tr + " " + entry.en, 3), (entry.words, 1.5),
                                              (entry.page.names.tr + " " + entry.page.names.en, 0.8)]
            if let score = score(tokens, phrase: phrase, title: title, fields: fields) {
                hits.append(SettingsHit(target: SettingsTarget(page: entry.page, anchor: entry.anchor), title: title, score: score))
            }
        }
        // One row per name: the same setting can be listed under two words.
        var seen = Set<String>()
        return hits.sorted { $0.score != $1.score ? $0.score > $1.score : $0.title < $1.title }
            .filter { seen.insert($0.id).inserted }
            .prefix(limit).map { $0 }
    }

    /// Every token has to land somewhere; each scores by where (field weight) and how well (exact, start, inside, typo).
    private static func score(_ tokens: [String], phrase: String, title: String, fields: [(String, Double)]) -> Double? {
        let prepared = fields.map { (words($0.0), $0.1) }
        var total = 0.0
        for token in tokens {
            var best = 0.0
            for (list, weight) in prepared {
                for word in list {
                    best = max(best, quality(token, word) * weight)
                }
            }
            guard best > 0 else { return nil }
            total += best
        }
        let folded = fold(title)
        if folded.hasPrefix(phrase) { total += 3 } else if folded.contains(phrase) { total += 1.5 }
        return total
    }

    private static func quality(_ token: String, _ word: String) -> Double {
        if word == token { return 1 }
        if word.hasPrefix(token) { return token.count >= 2 ? 0.85 : 0.5 }
        if token.count >= 3, word.contains(token) { return 0.5 }
        if token.count >= 5 {
            // A slip of one letter: against the whole word, or the start of a longer one.
            if typo(token, word) || (word.count > token.count && typo(token, String(word.prefix(token.count)))) { return 0.4 }
        }
        return 0
    }

    /// True when the two differ by one letter added, dropped, changed or two letters swapped.
    static func typo(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        guard abs(x.count - y.count) <= 1, x != y else { return false }
        if x.count == y.count {
            let diff = x.indices.filter { x[$0] != y[$0] }
            if diff.count == 1 { return true }
            return diff.count == 2 && diff[1] == diff[0] + 1 && x[diff[0]] == y[diff[1]] && x[diff[1]] == y[diff[0]]
        }
        let (short, long) = x.count < y.count ? (x, y) : (y, x)
        var i = 0, j = 0, skipped = false
        while i < short.count && j < long.count {
            if short[i] == long[j] { i += 1; j += 1 } else if skipped { return false } else { skipped = true; j += 1 }
        }
        return true
    }

    /// Lower case, no accents, Turkish dotless i folded too: "Karanlık Görünüm" → "karanlik gorunum".
    static func fold(_ text: String) -> String {
        text.replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "İ", with: "i")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
    }

    static func words(_ text: String) -> [String] {
        fold(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// The title with the letters the query matched at word starts set in bold.
    static func highlighted(_ title: String, _ query: String) -> AttributedString {
        var result = AttributedString(title)
        let tokens = words(query)
        guard !tokens.isEmpty else { return result }
        let folded = Array(fold(title))
        let original = Array(title)
        guard folded.count == original.count else { return result }
        var i = 0
        while i < folded.count {
            let startsWord = i == 0 || !(folded[i - 1].isLetter || folded[i - 1].isNumber)
            if startsWord, let token = tokens.first(where: { i + $0.count <= folded.count && String(folded[i..<(i + $0.count)]) == $0 }) {
                let lower = result.index(result.startIndex, offsetByCharacters: i)
                let upper = result.index(lower, offsetByCharacters: token.count)
                result[lower..<upper].font = Theme.bodyStrong
                i += token.count
            } else {
                i += 1
            }
        }
        return result
    }

    static let entries: [SettingsEntry] = [
        // General
        .init(.general, "general.language", "Dil", "Language", "türkçe english ingilizce locale"),
        .init(.general, "general.language", "Girişte aç", "Open at login", "başlangıç startup otomatik başlat launch açılış"),
        .init(.general, "general.language", "Dock'ta göster", "Show in Dock", "dock simge icon ⌘⇥ cmd tab uygulama değiştirici app switcher"),
        .init(.general, "general.refresh", "Arka planda yenileme sıklığı", "Background refresh", "saniye interval pil battery hız"),
        .init(.general, "general.notes", "Notlar uygulaması", "Notes app", "apple notes not nabız"),
        .init(.general, "general.notifications", "Bildirimler", "Notifications", "uyarı alert bellek cpu disk pil limit"),
        // Shortcuts
        .init(.shortcuts, "shortcuts.keys", "Başlatıcı kısayolu", "Launcher shortcut", "hotkey tuş ⌃⌥ boşluk space"),
        .init(.shortcuts, "shortcuts.brightness", "Harici ekran parlaklığı", "External display brightness", "parlaklık brightness monitör monitor ddc ekran display tuş keys monitorcontrol"),
        .init(.shortcuts, "shortcuts.keys", "Pano geçmişi kısayolu", "Clipboard history shortcut", "hotkey tuş ⌃⌥v"),
        .init(.shortcuts, "shortcuts.keys", "Not kısayolu", "Notes shortcut", "hotkey tuş"),
        .init(.shortcuts, "shortcuts.keys", "AI sohbet kısayolu", "AI chat shortcut", "hotkey tuş"),
        .init(.shortcuts, "shortcuts.keys", "AI'a sor kısayolu", "Ask AI shortcut", "hotkey tuş hızlı soru"),
        .init(.shortcuts, "shortcuts.keys", "Panel kısayolu", "Panel shortcut", "hotkey tuş"),
        .init(.shortcuts, "shortcuts.keys", "Dikte kısayolu", "Dictation shortcut", "hotkey tuş ses"),
        .init(.shortcuts, "shortcuts.keys", "Kısayolları değiştir", "Change shortcuts", "kaydet record tuş key combination"),
        // Screenshots
        .init(.screenshot, "screenshot.keys", "Ekran görüntüsü kısayolu", "Screenshot shortcut", "screen capture ss yakala"),
        .init(.screenshot, "screenshot.keys", "Ekran görüntüsünden sonra", "After a screenshot", "önizleme preview düzenleyici editor"),
        .init(.screenshot, "screenshot.record", "Ekran kaydı", "Screen recording", "video kayıt record screen studio mp4 gif zoom"),
        .init(.screenshot, "screenshot.record", "Son kaydı aç", "Open the last recording", "video kayıt düzenle edit"),
        .init(.screenshot, "screenshot.library", "Geçmiş kayıtlar", "Past recordings", "video kayıt sil delete boyut size disk eski old"),
        // Backup & upkeep
        .init(.maintenance, "maintenance.recordings", "Ekran kayıtlarının boyutu", "Screen recordings size", "video kayıt disk alan space temizlik clean"),
        .init(.maintenance, "maintenance.backup", "Yedekle", "Back up", "backup dışa aktar export dosya"),
        .init(.maintenance, "maintenance.backup", "Yedekten yükle", "Load a backup", "restore geri yükle içe aktar import"),
        .init(.maintenance, "maintenance.backup", "Her gün iCloud'a yedekle", "Daily iCloud backup", "icloud drive otomatik auto"),
        .init(.maintenance, "maintenance.rust", "Rust önbelleklerini temizle", "Clean Rust caches", "cargo target temizlik clean disk alan space"),
        .init(.maintenance, "maintenance.reset", "Tüm ayarları sıfırla", "Reset all settings", "varsayılan default fabrika factory"),
        // Appearance
        .init(.appearance, "appearance.accent", "Vurgu rengi", "Accent colour", "renk color mavi blue"),
        .init(.appearance, "appearance.theme", "Koyu / açık görünüm", "Dark / light appearance", "tema theme karanlık dark mode"),
        .init(.appearance, "appearance.theme", "Arka plan: buzlu cam ya da opak", "Background: frosted or opaque", "material şeffaf transparent blur"),
        .init(.appearance, "appearance.text", "Yazı tipi", "Typeface", "font yuvarlak rounded mono"),
        .init(.appearance, "appearance.text", "Yazı boyutu", "Text size", "font büyük large"),
        .init(.appearance, "appearance.panel", "Panel genişliği", "Panel width", "dar geniş narrow wide"),
        .init(.appearance, "appearance.panel", "Satır sıklığı", "Row density", "sıkı ferah compact roomy"),
        .init(.appearance, "appearance.panel", "Çubuk kalınlığı", "Bar thickness", "ince kalın thin thick meter"),
        .init(.appearance, "appearance.menuBar", "Menü çubuğu değerlerini renklendir", "Colour menu bar values", "renk color"),
        .init(.appearance, "appearance.menuBar", "Değişen rakamları kaydır", "Roll changing digits", "animasyon animation sayı"),
        .init(.appearance, "appearance.reset", "Görünümü sıfırla", "Reset appearance", "varsayılan default"),
        // Menu bar
        .init(.menuBar, "menuBar.preview", "Menü çubuğu yerleşimi", "Menu bar layout", "iki satır tek satır two lines one line önizleme"),
        .init(.menuBar, "menuBar.system", "İşlemci (CPU)", "Processor (CPU)", "cpu yük load"),
        .init(.menuBar, "menuBar.system", "Bellek (RAM)", "Memory (RAM)", "ram"),
        .init(.menuBar, "menuBar.system", "Ekran kartı (GPU)", "Graphics (GPU)", "gpu"),
        .init(.menuBar, "menuBar.system", "Takas alanı", "Swap", "swap"),
        .init(.menuBar, "menuBar.system", "Ağ hızı", "Network speed", "network internet indirme yükleme download upload"),
        .init(.menuBar, "menuBar.system", "Disk", "Disk", "depolama storage boş alan free"),
        .init(.menuBar, "menuBar.system", "Pil", "Battery", "şarj charge"),
        .init(.menuBar, "menuBar.other", "Menü çubuğunda AI limiti", "AI limit in the menu bar", "claude codex gemini"),
        .init(.menuBar, "menuBar.other", "Menü çubuğunda piyasa fiyatı", "Market price in the menu bar", "btc bitcoin kripto"),
        .init(.menuBar, "menuBar.other", "Menü çubuğunda döviz kuru", "Exchange rate in the menu bar", "usd eur kur"),
        .init(.menuBar, "menuBar.hider", "Kalabalık simgeleri gizle", "Hide crowded icons", "gizle hide bartender ice hidden bar sadeleştir tidy çentik notch simgeler icons"),
        .init(.menuBar, "menuBar.hider", "Simgeleri kendiliğinden gizle", "Hide icons again", "süre delay otomatik auto"),
        .init(.menuBar, "menuBar.icon", "Menü çubuğu simgesi", "Menu bar icon", "ikon icon"),
        .init(.menuBar, "menuBar.icon", "Etiketleri yaz (CPU, RAM…)", "Show labels (CPU, RAM…)", "label"),
        // Panel
        .init(.panel, "panel.folding", "Katlanabilir bölümler", "Collapsible sections", "katla fold"),
        .init(.panel, "panel.folding", "Akordeon: tek bölüm açık", "Accordion: one section open", "accordion"),
        .init(.panel, "panel.sections", "Panel bölümleri ve sırası", "Panel sections and order", "gizle göster hide show sırala reorder"),
        .init(.panel, "panel.sections", "Dev sunucuları ve portlar", "Dev servers and ports", "port localhost sunucu server vite next npm kill durdur stop"),
        .init(.panel, "panel.sections", "Ekran parlaklığı sürgüsü", "Display brightness slider", "parlaklık brightness monitör monitor ekran display"),
        .init(.panel, "panel.tools", "Panel araçları", "Panel tools", "tool"),
        .init(.panel, "panel.apps", "Çok kaynak kullanan uygulamalar", "Busiest apps list", "işlem process top bellek cpu"),
        // Suggestions
        .init(.advice, "advice.show", "Panelde önerileri göster", "Show suggestions in the panel", "öneri tavsiye advice"),
        .init(.advice, "advice.kinds", "Ne zaman öneri gelsin", "When to suggest", "bellek ısı disk pil memory heat"),
        .init(.advice, "advice.security", "Güvenlik kontrolleri", "Security checks", "güvenlik duvarı firewall filevault gatekeeper sip"),
        .init(.advice, "advice.hidden", "Gizlenen önerileri geri getir", "Bring hidden suggestions back", "hide restore"),
        // Ask AI
        .init(.ai, "ai.ask", "Başlatıcıda AI'a sor", "Ask AI in the launcher", "soru question ?"),
        .init(.ai, "ai.ask", "Kim cevaplasın", "Who answers", "claude codex gemini cihaz içi on-device apple intelligence motor engine"),
        .init(.ai, "ai.ask", "AI modeli", "AI model", "opus sonnet gpt gemini model"),
        .init(.ai, "ai.ask", "Düşünme seviyesi", "Thinking level", "effort reasoning akıl yürütme"),
        .init(.ai, "ai.commands", "Kendi AI komutların", "Your own AI commands", "istem prompt özetle çevir düzelt summarise translate"),
        // Chat
        .init(.aiChat, "aiChat.open", "Sohbet penceresini aç", "Open the chat window", "chat"),
        .init(.aiChat, "aiChat.answers", "Cevap gelince bildir", "Notify when an answer arrives", "bildirim notification"),
        .init(.aiChat, "aiChat.answers", "Sonraki mesajı öner", "Suggest the next message", "öneri suggestion tab"),
        .init(.aiChat, "aiChat.answers", "Claude sohbeti kendisi hatırlasın", "Let Claude remember the chat itself", "oturum session hızlı faster limit"),
        .init(.aiChat, "aiChat.instructions", "Hakkında ve nasıl cevap versin", "About you and how to answer", "talimat instructions özel custom prompt sistem system"),
        .init(.aiChat, "aiChat.history", "Sohbetleri sakla", "Keep chats", "geçmiş history şifreli encrypted"),
        .init(.aiChat, "aiChat.history", "Tüm sohbetleri sil", "Delete all chats", "temizle clear"),
        // Dictation
        .init(.dictation, "dictation.main", "Dikte dili", "Dictation language", "konuş ses voice speak türkçe english"),
        // AI limits
        .init(.aiLimits, "aiLimits.providers", "Claude limitleri", "Claude limits", "anthropic abonelik subscription"),
        .init(.aiLimits, "aiLimits.providers", "Codex limitleri", "Codex limits", "openai chatgpt abonelik subscription"),
        .init(.aiLimits, "aiLimits.providers", "Gemini limitleri", "Gemini limits", "google abonelik subscription"),
        .init(.aiLimits, "aiLimits.accounts", "Hesaplar ve takma adlar", "Accounts and nicknames",
              "ikinci hesap second account nickname iş work kişisel personal ekle add klasör folder"),
        .init(.aiLimits, "aiLimits.display", "Kalanı ya da kullanılanı göster", "Show what's left or used", "yüzde percent"),
        .init(.aiLimits, "aiLimits.display", "Menü çubuğunda hangi limit", "Menu bar shows",
              "en sıkı tightest hesap account menü çubuğu menu bar"),
        .init(.aiLimits, "aiLimits.grok", "Grok", "Grok", "xai"),
        .init(.aiLimits, "aiLimits.refresh", "Limitleri şimdi yenile", "Refresh limits now", "güncelle update"),
        // MCP
        .init(.mcp, "mcp.server", "MCP sunucusu", "MCP server", "server aç turn on"),
        .init(.mcp, "mcp.permissions", "Mac'te işlem yapsın", "Act on the Mac", "izin permission komut command"),
        .init(.mcp, "mcp.permissions", "Notları ve parçacıkları okuyup yazsın", "Read and write notes and snippets", "izin permission"),
        .init(.mcp, "mcp.permissions", "Pano geçmişini okusun", "Read the clipboard history", "izin permission"),
        .init(.mcp, "mcp.permissions", "Betiklerimi ve Kestirmelerimi çalıştırsın", "Let AI apps run my scripts and Shortcuts", "izin permission script shortcut kestirme uyku sleep kilit lock"),
        .init(.mcp, "mcp.permissions", "Ekran görüntüsü alsın", "Take screenshots", "izin permission ekran screen screenshot"),
        .init(.mcp, "mcp.permissions", "Panodaki metni okusun", "Read what's on the clipboard now", "izin permission pano clipboard"),
        .init(.mcp, "mcp.connect", "Claude Code'a ekle", "Add to Claude Code", "bağla connect"),
        .init(.mcp, "mcp.connect", "Claude Desktop'a ekle", "Add to Claude Desktop", "bağla connect"),
        .init(.mcp, "mcp.connect", "Diğer uygulamalar için JSON", "JSON for other apps", "cursor windsurf config"),
        // Launcher
        .init(.launcher, "launcher.main", "Başlatıcıyı aç", "Open the launcher", "raycast spotlight"),
        .init(.launcher, "launcher.main", "Uygulamaları ara", "Search apps", "app"),
        .init(.launcher, "launcher.main", "Başlatıcıda pano öğeleri", "Clipboard items in the launcher", "pano clipboard"),
        .init(.launcher, "launcher.search", "Varsayılan arama motoru", "Default search engine", "web google duckduckgo bing arama search"),
        .init(.launcher, "launcher.quicklinks", "Hızlı bağlantılar", "Quicklinks", "web arama google github url kısaltma keyword"),
        .init(.launcher, "launcher.bindings", "Kendi kısayolların ve takma adların", "Your shortcuts and aliases", "alias hotkey"),
        .init(.launcher, "launcher.aiCommands", "Başlatıcıda AI komutları", "AI commands in the launcher", "istem prompt özetle çevir summarise translate"),
        // Extensions
        .init(.developer, "developer.projects", "Panelde projeleri göster", "Show projects in the panel", "git repo dal branch push commit"),
        .init(.developer, "developer.projects", "Projeyi aç", "Open projects in", "editör editor cursor vs code zed"),
        .init(.developer, "developer.projects", "Kodlama ajanı", "Coding agent", "claude code codex ai"),
        .init(.developer, "developer.projects", "Docker konteynerleri", "Docker containers", "docker container compose supabase"),
        .init(.developer, "developer.cleanup", "Geliştirici temizliği", "Developer clean-up", "disk yer space simülatör simulator worktree node_modules deriveddata pnpm npm brew playwright docker volume dal branch"),
        .init(.developer, "developer.notary", "Notarize bitince haber ver", "Tell me when notarization finishes", "notarytool apple imza sign release"),
        .init(.developer, "developer.launcher", "Launcher'da geliştirici araçları", "Developer tools in the launcher", "port jwt unix epoch zaman timestamp hash sha md5 uuid ulid case camel snake renk color hex cron http base64"),
        .init(.extensions, "extensions.files", "Aramada dosyaları göster", "Show files in searches", "spotlight dosya file"),
        .init(.extensions, "extensions.files", "Kestirmeler (Shortcuts)", "Shortcuts app", "kestirme otomasyon automation"),
        .init(.extensions, "extensions.files", "Betikler", "Scripts", "script sh python bash"),
        .init(.extensions, "extensions.downloads", "Video indirme", "Video downloads", "youtube yt-dlp ffmpeg kalite quality"),
        // Clipboard
        .init(.clipboard, "clipboard.history", "Pano geçmişini tut", "Keep clipboard history", "kopyala copy"),
        .init(.clipboard, "clipboard.history", "Yeniden başlatınca hatırla", "Remember after a restart", "kaydet save disk"),
        .init(.clipboard, "clipboard.history", "Kaç öğe tutulsun", "How many items to keep", "limit en fazla"),
        .init(.clipboard, "clipboard.history", "Silinme süresi", "Forget after", "gün days"),
        .init(.clipboard, "clipboard.paste", "↩ ile yapıştır", "Paste with ↩", "yapıştırma paste enter"),
        .init(.clipboard, "clipboard.paste", "Erişilebilirlik izni", "Accessibility permission", "izin permission"),
        .init(.clipboard, "clipboard.excluded", "Kaydedilmeyen uygulamalar", "Apps never recorded", "şifre password 1password gizli private"),
        .init(.clipboard, "clipboard.clear", "Pano geçmişini temizle", "Clear clipboard history", "sil delete"),
        // Snippets
        .init(.snippets, "snippets.list", "Parçacık ekle", "Add a snippet", "metin text kısaltma keyword genişlet expand"),
        .init(.snippets, "snippets.expand", "Her uygulamada genişlet", "Expand in any app", "yazarken typing kısaltma keyword ön ek prefix textexpander otomatik"),
        // Windows
        .init(.windows, "windows.shortcuts", "Pencere kısayolları", "Window shortcuts", "hotkey"),
        .init(.windows, "windows.layouts", "Yarım, çeyrek ve tam ekran", "Halves, quarters and full screen", "yerleşim layout sol sağ left right maximize"),
        .init(.windows, "windows.custom", "Kendi yerleşimlerin", "Your own layouts", "özel custom çoklu pencere"),
        // Focus
        .init(.focus, "focus.pomodoro", "Pomodoro süreleri", "Pomodoro lengths", "odak blok mola break dakika"),
        .init(.focus, "focus.pomodoro", "Sıradaki blok kendiliğinden başlasın", "Start the next block by itself", "otomatik auto"),
        .init(.focus, "focus.hide", "Odakta gizlenecek uygulamalar", "Apps hidden during focus", "gizle hide slack mail"),
        .init(.focus, "focus.hide", "Masaüstü simgelerini gizle", "Hide desktop icons", "desktop"),
        .init(.focus, "focus.sites", "Siteleri engelle", "Block websites", "site engel block youtube twitter"),
        .init(.focus, "focus.macos", "macOS Odak kestirmeleri", "macOS Focus shortcuts", "rahatsız etme do not disturb"),
        // Schedules
        .init(.schedules, "schedules.list", "Zamanlanmış görevler", "Scheduled tasks", "görev zaman saat"),
        .init(.schedules, "schedules.add", "Görev ekle", "Add a task", "hatırlatma reminder"),
        // Calendar
        .init(.calendar, "calendar.main", "Takvimi göster", "Show the calendar", "etkinlik event"),
        .init(.weather, "weather.main", "Hava durumunu panelde göster", "Show the weather in the panel", "hava weather sıcaklık temperature"),
        .init(.weather, "weather.main", "Nem ve rüzgâr satırı", "Humidity and wind row", "nem humidity rüzgâr rüzgar wind"),
        .init(.weather, "weather.main", "Menü çubuğunda sıcaklık", "Temperature in the menu bar", "derece degrees hava weather"),
        .init(.weather, "weather.main", "Sıcaklık birimi", "Temperature unit", "celsius fahrenheit santigrat °c °f"),
        .init(.weather, "weather.city", "Hava durumu şehri", "Weather city", "konum location şehir city yer place"),
        .init(.calendar, "calendar.main", "Toplantıdan önce bildir", "Notify before a meeting", "hatırlatma reminder zoom meet teams"),
        .init(.calendar, "calendar.calendars", "Gösterilen takvimler", "Calendars shown", "gizle hide"),
        // Markets
        .init(.markets, "markets.panel", "Paneldeki piyasalar", "Markets in the panel", "btc eth kripto hisse"),
        .init(.markets, "markets.alerts", "Fiyat alarmları", "Price alerts", "alarm alert hedef target bildirim"),
        .init(.markets, "markets.catalog", "Piyasa ekle", "Add a market", "hyperliquid btc tsla gold altın hisse stock"),
        // Currency
        .init(.currency, "currency.base", "Ana para birimi", "Main currency", "try usd eur lira dolar euro"),
        .init(.currency, "currency.watched", "İzlenen kurlar", "Watched rates", "döviz kur usd eur gbp"),
    ]
}

extension SettingsPage {
    /// Words for what is on the page, in both languages, so a search finds the page from what it holds.
    var keywords: String {
        switch self {
        case .general: "dil language giriş login açılış startup yenile refresh not notes bildirim notification"
        case .appearance: "renk color colour tema theme karanlık dark açık light yazı font typeface boyut size sıklık density vurgu accent opak opaque"
        case .shortcuts: "kısayol shortcut hotkey tuş key klavye keyboard"
        case .maintenance: "yedek backup icloud geri yükle restore rust temizlik clean sıfırla reset"
        case .menuBar: "cpu ram gpu takas swap ağ network disk pil battery simge icon etiket label değer value"
        case .panel: "bölüm section sıra order katla fold akordeon accordion araç tool uygulama app"
        case .advice: "öneri suggestion güvenlik security güvenlik duvarı firewall filevault gatekeeper gizle hide bellek memory ısı heat"
        case .ai: "ai claude codex gemini sor ask apple intelligence cihaz içi on-device çevir özetle komut command istem prompt model"
        case .aiChat: "ai sohbet chat pencere window geçmiş history"
        case .dictation: "dikte dictation konuş speak ses voice mikrofon microphone"
        case .aiLimits: "ai limit abonelik subscription claude codex gemini grok kota quota"
        case .mcp: "mcp claude code desktop cursor ai yapay zeka bağla connect server sunucu araç tool"
        case .launcher: "arama search uygulama app hesap calculator maths web bağlantı link"
        case .extensions: "uzantı extension dosya file kestirme shortcuts betik script video indir download youtube"
        case .developer: "geliştirici developer dev proje project git repo port docker konteyner container temizlik cleanup simülatör simulator worktree node_modules deriveddata xcode notarize jwt cron hash uuid"
        case .clipboard: "pano clipboard geçmiş history kopyala copy yapıştır paste şifreli encrypted"
        case .snippets: "parçacık snippet metin text kelime keyword"
        case .windows: "pencere window yerleştir place layout yarım half"
        case .screenshot: "ekran görüntüsü screenshot screen capture yakala kayıt video record"
        case .focus: "pomodoro odak focus engelle block gizle hide"
        case .schedules: "görev task zamanla schedule saat time gün day"
        case .calendar: "takvim calendar toplantı meeting etkinlik event katıl join zoom meet teams"
        case .weather: "hava weather sıcaklık temperature yağmur rain derece forecast tahmin"
        case .markets: "piyasa market hyperliquid btc kripto crypto hisse stock fiyat price alarm alert"
        case .currency: "döviz currency kur rate usd eur try para money"
        case .about: "hakkında about sürüm version güncelleme update çökme crash"
        }
    }
}
