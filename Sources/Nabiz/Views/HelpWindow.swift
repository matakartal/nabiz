// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import SwiftUI

/// "What can it do?": a short tour in four tabs (start, launcher, tools, shortcuts) with search across all of it.
/// Launcher examples open the launcher with that text, so trying something is one click.
@MainActor
enum HelpWindow {
    private static var window: NSWindow?

    static func show(_ tab: HelpTab = .start) {
        HelpState.shared.tab = tab
        HelpState.shared.query = ""
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: HelpView()))
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.minSize = NSSize(width: 600, height: 480)
            window.setContentSize(NSSize(width: 720, height: 640))
            window.center()
            self.window = window
        }
        window?.title = L("Nabız · Neler yapabilir?", "Nabız · What it can do")
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

enum HelpTab: String, CaseIterable, Identifiable {
    case start, launcher, tools, keys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: L("Başlangıç", "Start")
        case .launcher: L("Başlatıcı", "Launcher")
        case .tools: L("Araçlar", "Tools")
        case .keys: L("Kısayollar", "Shortcuts")
        }
    }
}

@MainActor
@Observable
final class HelpState {
    static let shared = HelpState()
    var tab: HelpTab = .start
    var query = ""
}

/// One thing to learn: an example to try, a key combination, or a tool.
private struct HelpItem: Identifiable {
    var id: String { tab.rawValue + group + title + (example ?? "") }
    let tab: HelpTab
    let group: String
    let title: String
    var detail = ""
    var keys: String?
    var example: String?
    var symbol: String?
}

struct HelpView: View {
    @AppStorage(Prefs.language) private var language = "system"
    @Bindable private var state = HelpState.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollView {
                Group {
                    if !state.query.trimmingCharacters(in: .whitespaces).isEmpty {
                        results
                    } else {
                        switch state.tab {
                        case .start: start
                        case .launcher: launcher
                        case .tools: tools
                        case .keys: keys
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.xl)
            }
            .scrollIndicators(.never)
        }
        .ignoresSafeArea(edges: .top)
        .frame(minWidth: 600, minHeight: 480)
        .background(MenuMaterial().ignoresSafeArea())
        .appearanceRoot(opaqueFill: Theme.surface)
    }

    // MARK: Header

    /// The title sits in the title bar next to the window buttons; tabs and search under it. Content scrolls below,
    /// never behind them.
    private var header: some View {
        VStack(spacing: Theme.Spacing.m) {
            Text(L("Neler yapabilir?", "What Nabız can do")).font(Theme.bodyStrong).foregroundStyle(Theme.text)
                .frame(height: Theme.noteHeader - Theme.Spacing.s)
            HStack(spacing: Theme.Spacing.m) {
                Picker("", selection: $state.tab) {
                    ForEach(HelpTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(!state.query.isEmpty)
                Spacer()
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textMuted)
                    TextField(L("Ara: hesap, pano, kısayol…", "Search: maths, clipboard, keys…"), text: $state.query)
                        .textFieldStyle(.plain)
                    if !state.query.isEmpty {
                        Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textMuted) }
                            .buttonStyle(.plain)
                    }
                }
                .font(Theme.body)
                .padding(.horizontal, Theme.Spacing.s)
                .frame(width: 240, height: Theme.toolTile)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.m)
    }

    // MARK: Tabs

    private var start: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(L("Nabız menü çubuğundan Mac'ini izler. Bir kısayol uzağında da bunlar var:",
                   "Nabız watches your Mac from the menu bar. One shortcut away, there's also:"))
                .font(Theme.body).foregroundStyle(Theme.textMuted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.m), GridItem(.flexible())], spacing: Theme.Spacing.m) {
                FeatureCard(symbol: "sparkles", title: L("AI sohbet", "AI chat"), keys: HotKey.label(.aiChat),
                            text: L("Claude, Codex, Gemini, Grok ya da Apple'ın ücretsiz modeliyle sohbet; kendi aboneliklerinle.",
                                    "Chat with Claude, Codex, Gemini, Grok or Apple's free model, on your own subscriptions.")) {
                    AIChatWindow.show()
                }
                FeatureCard(symbol: "camera.viewfinder", title: L("Ekran görüntüsü", "Screenshot"), keys: HotKey.label(.screenshot),
                            text: L("Alan seç; ok, kutu, yazı, numara, bulanıklaştırma ve çerçeveyle düzenle.",
                                    "Pick an area; mark it up with arrows, boxes, text, steps, blur and a frame.")) {
                    Capture.run(.area)
                }
                FeatureCard(symbol: "magnifyingglass", title: L("Başlatıcı", "Launcher"), keys: HotKey.label(.launcher),
                            text: L("Uygulama aç, hesapla, para ve birim çevir, dosya ve emoji bul, komut çalıştır.",
                                    "Open apps, calculate, convert money and units, find files and emoji, run commands.")) {
                    LauncherPanel.shared.show()
                }
                FeatureCard(symbol: "doc.on.clipboard", title: L("Pano geçmişi", "Clipboard history"), keys: HotKey.label(.clipboard),
                            text: L("Kopyaladığın her şey burada: ara, sabitle, ↩ ile yapıştır.", "Everything you copied: search, pin, paste with ↩.")) {
                    LauncherPanel.shared.show(.clipboard)
                }
                FeatureCard(symbol: "note.text", title: L("Notlar", "Notes"), keys: HotKey.label(.note),
                            text: L("Her uygulamanın üstünde duran notlar ve yapılacaklar.", "Notes and checklists that float over every app.")) {
                    NoteWindow.toggle()
                }
                FeatureCard(symbol: "menubar.rectangle", title: L("Panel", "Panel"), keys: HotKey.label(.panel),
                            text: L("İşlemci, bellek, AI limitleri, piyasalar, döviz ve araçlar.", "CPU, memory, AI limits, markets, rates and tools.")) {
                    HotKey.togglePanel()
                }
            }
            section(L("Bilmekte fayda var", "Good to know")) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    tip("command", L("Başlatıcıda bir satırı seçip ⌘K'ye bas: o satırla yapılabilecek her şey çıkar.",
                                     "Select a row in the launcher and press ⌘K for everything you can do with it."))
                    tip("textformat", L("Panodaki metne ⌘K: BÜYÜK HARF, tek satır, JSON, Base64, QR kodu…",
                                        "⌘K on copied text: UPPERCASE, one line, JSON, Base64, QR code…"))
                    tip("arrow.down.circle", L("Bir YouTube ya da Instagram bağlantısını başlatıcıya yapıştır: video ya da ses iner.",
                                               "Paste a YouTube or Instagram link into the launcher to save the video or its sound."))
                    tip("brain.head.profile", L("Pomodoro'yu başlat; odak bloklarında sohbet uygulamaları kendiliğinden gizlenir.",
                                                "Start a Pomodoro; chat apps hide themselves during focus blocks."))
                    tip("questionmark.bubble", L("Başlatıcıda bir soru yaz ya da başına ? koy: AI cevaplar. \(HotKey.label(.ai)) seçili metni de alır.",
                                                 "Type a question in the launcher, or start with ?: AI answers. \(HotKey.label(.ai)) takes the selected text too."))
                    tip("mic", L("Dikte: kısayola bas, konuş, yine bas; söylediklerin imlecin olduğu yere yazılır (Ayarlar → AI).",
                                 "Dictation: press the shortcut, speak, press again; your words are typed at the cursor (Settings → AI)."))
                    tip("text.magnifyingglass", L("AI sohbetinde: ⌘F sohbette ara, ⌥⌘↑/↓ sorular arasında gez, ⇧⌘C son cevabı kopyala, ⇧⌘⌫ sohbeti sil, ⌘1…9 sohbetler arasında geç. Cevap yazılırken yazdığın mesaj sıraya girer; bir cevabın altındaki dal simgesi oradan yeni sohbet açar. ⌘K sohbetlerde arar, ⌥⌘S yan sohbet açar, ⇧⌘' seçtiğin kısmı alıntılar, ⇥ gri öneriyi alır; uzun sohbeti ⋯ → Özetle ve sürdür ile hafiflet. Görsel ve PDF de ekleyebilirsin.",
                                                 "In AI chat: ⌘F find in chat, ⌥⌘↑/↓ move between questions, ⇧⌘C copy the last answer, ⇧⌘⌫ delete the chat, ⌘1…9 switch chats. What you send while it writes waits in a queue; the branch icon under an answer starts a new chat from there. ⌘K searches chats, ⌥⌘S opens a side chat, ⇧⌘' quotes what you selected, ⇥ takes the grey suggestion; lighten a long chat with ⋯ → Summarize and continue. Images and PDFs can be attached too."))
                    tip("calendar", L("Takvimi aç: bugünkü toplantılar panelde, tek tıkla katıl (Ayarlar → Takvim).",
                                      "Turn on the calendar: today's meetings in the panel, one click to join (Settings → Calendar)."))
                    tip("rectangle.split.2x1", L("Kendi pencere düzenlerini kur ve kısayol ver (Ayarlar → Pencereler).",
                                                 "Make your own window layouts and give them shortcuts (Settings → Windows)."))
                    tip("point.3.connected.trianglepath.dotted", L("Claude Code ya da Claude Desktop Nabız'ı kullanabilir (Ayarlar → MCP).",
                                                                   "Claude Code or Claude Desktop can use Nabız (Settings → MCP)."))
                    tip("cursorarrow.click.2", L("Menü çubuğundaki simgeye sağ tıkla: kısa bir menü açılır.", "Right-click the menu bar item for a short menu."))
                }
            }
        }
    }

    private var launcher: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            section(L("Ön ekler", "Prefixes")) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.m), GridItem(.flexible())], alignment: .leading,
                          spacing: Theme.Spacing.s) {
                    prefix("=", L("yalnızca hesap; boşsa geçmiş", "maths only; empty shows history"))
                    prefix(">", L("yalnızca komutlar", "commands only"))
                    prefix("/", L("yalnızca dosyalar", "files only"))
                    prefix(":", L("emoji", "emoji"))
                    prefix("?", L("AI'a sor (Claude, Codex, Gemini, Apple)", "ask AI (Claude, Codex, Gemini, Apple)"))
                    prefix("g", L("Google'da ara (gh, yt, w…)", "search Google (gh, yt, w…)"))
                }
            }
            ForEach(groups(for: .launcher), id: \.self) { group in
                section(group) {
                    FlowLayout(spacing: Theme.Spacing.s) {
                        ForEach(items(.launcher, group)) { ExampleChip(item: $0) }
                    }
                }
            }
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            ForEach(groups(for: .tools), id: \.self) { group in
                section(group) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.m), GridItem(.flexible())], alignment: .leading,
                              spacing: Theme.Spacing.m) {
                        ForEach(items(.tools, group)) { ToolCard(item: $0) }
                    }
                }
            }
        }
    }

    private var keys: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            ForEach(groups(for: .keys), id: \.self) { group in
                section(group) {
                    VStack(spacing: Theme.Spacing.s) {
                        ForEach(items(.keys, group)) { KeyRow(item: $0) }
                    }
                }
            }
            Button(L("Kısayolları değiştir…", "Change shortcuts…")) { SettingsWindow.show(.shortcuts) }
        }
    }

    private var results: some View {
        let query = state.query.trimmingCharacters(in: .whitespaces)
        let found = Self.all.filter { item in
            [item.title, item.detail, item.example ?? "", item.keys ?? "", item.group].contains { Fuzzy.contains(query, $0) }
        }
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if found.isEmpty {
                Text(L("Bulunamadı. Başlatıcıda dene: ", "Nothing here. Try it in the launcher: ") + query)
                    .font(Theme.body).foregroundStyle(Theme.textMuted)
                Button(L("Başlatıcıda aç", "Open in the launcher")) { LauncherPanel.shared.show(text: query) }
            }
            ForEach(found) { item in
                if item.example != nil {
                    ExampleChip(item: item)
                } else if item.keys != nil {
                    KeyRow(item: item)
                } else {
                    ToolCard(item: item)
                }
            }
        }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(verbatim: title).font(Theme.smallStrong).foregroundStyle(Theme.textMuted)
            content()
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: Theme.menuIcon)
            Text(verbatim: text).font(Theme.body).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func prefix(_ key: String, _ text: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Keycap(key)
            Text(verbatim: text).font(Theme.body).foregroundStyle(Theme.text)
        }
    }

    private func groups(for tab: HelpTab) -> [String] {
        var seen: [String] = []
        for item in Self.all where item.tab == tab && !seen.contains(item.group) { seen.append(item.group) }
        return seen
    }

    private func items(_ tab: HelpTab, _ group: String) -> [HelpItem] {
        Self.all.filter { $0.tab == tab && $0.group == group }
    }

    // MARK: Content

    private static var all: [HelpItem] {
        func example(_ group: String, _ text: String, _ detail: String) -> HelpItem {
            HelpItem(tab: .launcher, group: group, title: text, detail: detail, example: text)
        }
        func key(_ group: String, _ keys: String, _ title: String) -> HelpItem {
            HelpItem(tab: .keys, group: group, title: title, keys: keys)
        }
        let maths = L("Hesap", "Maths"), money = L("Para ve kripto", "Money and crypto"), units = L("Birimler", "Units")
        let time = L("Saat ve tarih", "Time and dates"), commands = L("Komutlar", "Commands"), find = L("Arama", "Search")
        var list: [HelpItem] = [
            example(maths, "12*4", L("dört işlem", "arithmetic")), example(maths, "√2 * 3", L("kök", "roots")),
            example(maths, "sin 30", L("trigonometri (derece)", "trig (degrees)")), example(maths, "20% of 150", L("yüzde", "percent")),
            example(maths, "200 + %18", L("KDV ekle", "add tax")), example(maths, "5!", L("faktöriyel", "factorial")),
            example(maths, "17 mod 5", L("mod", "modulo")), example(maths, "255 hex", L("onaltılık", "hexadecimal")),
            example(money, "100 usd", L("TL ve diğer kurlar", "to your currencies")), example(money, "250 € tl", L("iki para", "two currencies")),
            example(money, "5 bin tl eur", L("Türkçe tutar", "Turkish amounts")), example(money, "0.5 btc", L("kripto", "crypto")),
            example(money, "1000 tl eth", L("TL'den kriptoya", "fiat to crypto")),
            example(units, "5 km mi", L("uzunluk", "length")), example(units, "120 km/h mph", L("hız", "speed")),
            example(units, "3 dönüm m2", L("alan", "area")), example(units, "2 gb mb", L("veri", "data")),
            example(units, "100 f c", L("sıcaklık", "temperature")), example(units, "2 l ml", L("hacim", "volume")),
            example(time, "tokyo", L("orada saat kaç", "time there")), example(time, "15:00 istanbul to new york", L("saat çevir", "convert a time")),
            example(time, "bugün + 3 hafta", L("tarih ekle", "add to a date")), example(time, "1.1.2027 ye kaç gün", L("kalan gün", "days left")),
            example(commands, "kilitle", L("ekranı kilitle", "lock the screen")), example(commands, "pomodoro", L("odak bloğu", "focus block")),
            example(commands, "sol yarı", L("pencere yerleşimi", "window layout")), example(commands, "25 dk", L("zamanlayıcı", "timer")),
            example(commands, "30 dk sonra uyut", L("uyku zamanlayıcı", "sleep timer")), example(commands, "ekran görüntüsü", L("ekran al", "screenshot")),
            example(commands, L("sunucuyu durdur", "stop server"), L("açık dev sunucusunu kapat", "stop a running dev server")),
            example(commands, L("menü çubuğu", "menu bar"), L("kalabalık simgeleri gizle", "hide crowded icons")),
            example(find, "g nabız", L("Google", "Google")), example(find, "gh swift", "GitHub"), example(find, "/rapor", L("dosya", "files")),
            example(find, ":ateş", "emoji"), example(find, "safari", L("uygulama", "app")),
            example("AI", L("? bu hata ne demek", "? what does this error mean"), L("soru sor", "ask a question")),
            example("AI", "?", L("seçili metni özetle, çevir, düzelt", "summarise, translate, fix selected text")),
        ]
        let everyday = L("Her gün", "Everyday"), more = L("Diğer araçlar", "More tools")
        list += ToolKind.allCases.map { kind in
            HelpItem(tab: .tools, group: ToolKind.everyday.contains(kind) ? everyday : more, title: kind.title, detail: kind.help, symbol: kind.symbol)
        }
        let anywhere = L("Her yerden", "Anywhere"), inLauncher = L("Başlatıcıda", "In the launcher"), inNotes = L("Notlarda", "In notes")
        list += [
            key(anywhere, HotKey.label(.launcher), L("Başlatıcı", "Launcher")), key(anywhere, HotKey.label(.clipboard), L("Pano geçmişi", "Clipboard history")),
            key(anywhere, HotKey.label(.note), L("Notlar", "Notes")), key(anywhere, HotKey.label(.panel), L("Panel", "Panel")),
            key(anywhere, HotKey.label(.aiChat), L("AI sohbet penceresi", "AI chat window")),
            key(anywhere, HotKey.label(.ai), L("AI'a sor (seçili metinle)", "Ask AI (with the selected text)")),
            key(anywhere, HotKey.label(.screenshot), L("Ekran görüntüsü (alan)", "Screenshot (area)")),
            key(anywhere, HotKey.label(.dictation), L("Dikte (Ayarlar → AI'dan açılır)", "Dictation (turn on in Settings → AI)")),
            key(L("AI sohbetinde", "In an AI chat"), "⌘O", L("Sohbeti pencerede aç", "Open the chat in its window")),
            key(L("AI sohbetinde", "In an AI chat"), "⌘R", L("Son cevabı yeniden yaz", "Write the last answer again")),
            key(L("AI sohbetinde", "In an AI chat"), "⌘N", L("Yeni sohbet", "New chat")),
            key(L("AI sohbetinde", "In an AI chat"), "esc", L("Cevabı durdur", "Stop the answer")),
            key(anywhere, "⌃⌥← → ↑ ↓", L("Pencereyi yarıya yerleştir (Ayarlar → Pencereler)", "Snap the window to a half (Settings → Windows)")),
            key(anywhere, "⌃⌥↩", L("Pencereyi ekranı kaplayacak kadar büyüt", "Maximize the window")),
            key(anywhere, "🔅 🔆", L("Fare hangi harici ekrandaysa onun parlaklığı (Ayarlar → Kısayollar)", "The brightness of the external display under the pointer (Settings → Shortcuts)")),
            key(inLauncher, "↑ ↓", L("Seç", "Pick")), key(inLauncher, "↩", L("Çalıştır, aç ya da yapıştır", "Run, open or paste")),
            key(inLauncher, "⌘↩", L("İkinci eylem (kopyala, Finder'da göster…)", "Second action (copy, show in Finder…)")),
            key(inLauncher, "⌘K", L("Satırın tüm eylemleri", "Every action for the row")), key(inLauncher, "⇧⌘F", L("Favorilere ekle", "Add to favourites")),
            key(inLauncher, "⌘P", L("Pano öğesini sabitle", "Pin a clipboard item")), key(inLauncher, "⌘⌫", L("Pano öğesini sil", "Delete a clipboard item")),
            key(inLauncher, "⎋", L("Yazıyı sil, sonra kapat", "Clear the text, then close")),
            key(inNotes, "⌘N", L("Yeni not", "New note")), key(inNotes, "⌘P", L("Tüm notlar ve arama", "All notes and search")),
            key(inNotes, "⌘[ ⌘]", L("Önceki / sonraki not", "Previous / next note")), key(inNotes, "⌘L", L("Yapılacak kutusu ekle ya da işaretle", "Add or tick a checkbox")),
            key(inNotes, "⇧⌘L", L("Madde işareti", "Bullet")), key(inNotes, "⌘B ⌘I", L("Kalın, eğik", "Bold, italic")),
            key(inNotes, "⇧⌘C", L("Notu kopyala", "Copy the note")), key(inNotes, "⎋", L("Kapat", "Close")),
        ]
        return list
    }
}

/// A key combination drawn as separate keys: ⌃ ⌥ Space.
struct Keycap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs / 2) {
            ForEach(Array(Self.split(text).enumerated()), id: \.offset) { _, key in
                Text(verbatim: key).font(Theme.smallStrong).monospacedDigit().foregroundStyle(Theme.text)
                    .padding(.horizontal, Theme.Spacing.xs + 1)
                    .frame(minWidth: Theme.menuRow - Theme.Spacing.xs, minHeight: Theme.menuRow - Theme.Spacing.xs)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.fieldRadius - 1, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius - 1, style: .continuous).strokeBorder(Theme.hairline))
            }
        }
    }

    /// "⌃⌥Space" → ⌃ ⌥ Space; "⌘[ ⌘]" → ⌘ [ ⌘ ].
    static func split(_ text: String) -> [String] {
        var keys: [String] = []
        for word in text.split(separator: " ") {
            var rest = ""
            for character in word {
                if "⌃⌥⇧⌘".contains(character) {
                    if !rest.isEmpty { keys.append(rest); rest = "" }
                    keys.append(String(character))
                } else {
                    rest.append(character)
                }
            }
            if !rest.isEmpty { keys.append(rest) }
        }
        return keys
    }
}

private struct FeatureCard: View {
    let symbol: String
    let title: String
    let keys: String
    let text: String
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: symbol).font(Theme.title).foregroundStyle(.white)
                        .frame(width: Theme.settingsHeaderIcon - Theme.Spacing.s, height: Theme.settingsHeaderIcon - Theme.Spacing.s)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.fieldRadius + 2, style: .continuous))
                    Text(verbatim: title).font(Theme.title).foregroundStyle(Theme.text)
                    Spacer(minLength: 0)
                    Keycap(keys)
                }
                Text(verbatim: text).font(Theme.body).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(L("Aç →", "Open →")).font(Theme.smallStrong).foregroundStyle(Theme.accent).opacity(hovering ? 1 : 0.7)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(hovering ? Theme.hover : Theme.track, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// An example to try: click opens the launcher with it; hover shows what it gives.
private struct ExampleChip: View {
    let item: HelpItem
    @State private var hovering = false

    var body: some View {
        Button { LauncherPanel.shared.show(text: item.example ?? item.title) } label: {
            HStack(spacing: Theme.Spacing.s) {
                Text(verbatim: item.title).font(.system(.body, design: .monospaced).weight(.medium)).foregroundStyle(Theme.text)
                Text(verbatim: item.detail).font(Theme.small).foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: Theme.toolTile)
            .background(hovering ? Theme.hover : Theme.track, in: Capsule())
            .overlay(Capsule().strokeBorder(hovering ? Theme.accent.opacity(0.6) : Theme.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Calculator.evaluate(item.example ?? "")?.text ?? L("Başlatıcıda dene", "Try it in the launcher"))
    }
}

private struct ToolCard: View {
    let item: HelpItem

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: item.symbol ?? "wrench").font(Theme.body).foregroundStyle(.white)
                .frame(width: Theme.settingsIcon + 4, height: Theme.settingsIcon + 4)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(verbatim: item.title).font(Theme.bodyStrong).foregroundStyle(Theme.text)
                Text(verbatim: item.detail).font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.track, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

private struct KeyRow: View {
    let item: HelpItem

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            Keycap(item.keys ?? "").frame(width: 150, alignment: .leading)
            Text(verbatim: item.title).font(Theme.body).foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
    }
}

/// Lays children left to right and wraps them onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
