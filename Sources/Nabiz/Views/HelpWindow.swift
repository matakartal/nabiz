import AppKit
import SwiftUI

/// "What can it do?": the shortcuts, launcher examples you can click to try, and every tool in one sentence.
@MainActor
enum HelpWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: HelpView()))
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.setContentSize(NSSize(width: 640, height: 620))
            window.center()
            self.window = window
        }
        window?.title = L("Nabız · Neler yapabilir?", "Nabız · What it can do")
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HelpView: View {
    @AppStorage(Prefs.language) private var language = "system"

    private var examples: [(String, String)] {
        [
            ("100 usd", L("döviz", "currency")), ("0.5 btc", L("kripto", "crypto")), ("5 bin tl eur", L("Türkçe tutar", "amounts")),
            ("√2 * 3", L("matematik", "maths")), ("120 km/h mph", L("birim", "units")), ("tokyo", L("dünya saati", "world clock")),
            ("bugün + 3 hafta", L("tarih", "dates")), ("255 hex", L("taban", "bases")), ("=", L("hesap geçmişi", "maths history")),
            ("> ", L("komutlar", "commands")), (":kalp", "emoji"), ("/", L("dosya ara", "find files")),
            ("g nabız", L("web'de ara", "web search")), ("pomodoro", L("odak", "focus")), ("sol yarı", L("pencere", "windows")),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(L("Neler yapabilir?", "What Nabız can do")).font(Theme.title).foregroundStyle(Theme.text)
                    Text(L("Menü çubuğundaki Nabız, Mac'ini izler ve bir kısayol uzağında bir başlatıcı, pano geçmişi, notlar ve araçlar sunar.",
                           "Nabız watches your Mac from the menu bar and keeps a launcher, clipboard history, notes and tools one shortcut away."))
                        .font(Theme.body).foregroundStyle(Theme.textMuted)
                }

                group(L("Kısayollar", "Shortcuts")) {
                    shortcut(HotKey.label(.launcher), L("Başlatıcı: uygulama, komut, hesap, dosya, emoji", "Launcher: apps, commands, maths, files, emoji"))
                    shortcut(HotKey.label(.clipboard), L("Pano geçmişi", "Clipboard history"))
                    shortcut(HotKey.label(.note), L("Notlar", "Notes"))
                    shortcut(HotKey.label(.panel), L("Bu panel", "This panel"))
                    shortcut("⌘K", L("Başlatıcıda seçili satırın tüm eylemleri", "In the launcher: everything you can do with the selected row"))
                    shortcut("⇧⌘F", L("Favorilere ekle", "Add to favourites"))
                    shortcut("⌃⌥← → ↑ ↓", L("Pencere yerleşimi (Ayarlar → Pencereler'den açılır)", "Window layouts (turn on in Settings → Windows)"))
                }

                group(L("Başlatıcıda dene", "Try in the launcher")) {
                    FlowLayout(spacing: Theme.Spacing.s) {
                        ForEach(examples, id: \.0) { example in
                            Button { LauncherPanel.shared.show(text: example.0) } label: {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Text(verbatim: example.0).font(Theme.bodyStrong).foregroundStyle(Theme.text)
                                    Text(verbatim: example.1).font(Theme.small).foregroundStyle(Theme.textMuted)
                                }
                                .padding(.horizontal, Theme.Spacing.m)
                                .padding(.vertical, Theme.Spacing.xs + 2)
                                .background(Theme.track, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .help(L("Başlatıcıda aç", "Open in the launcher"))
                        }
                    }
                }

                group(L("Araçlar", "Tools")) {
                    ForEach(ToolKind.allCases) { kind in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                            Image(systemName: kind.symbol).foregroundStyle(Theme.accent).frame(width: Theme.menuIcon)
                            Text(verbatim: kind.title).font(Theme.bodyStrong).foregroundStyle(Theme.text).frame(width: 120, alignment: .leading)
                            Text(verbatim: kind.help).font(Theme.body).foregroundStyle(Theme.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                group(L("İpuçları", "Tips")) {
                    tip(L("Panoda bir öğeye ⌘K: sabitle, nota kaydet, BÜYÜK HARF, JSON, Base64, QR kodu…", "⌘K on a clipboard item: pin, save as a note, UPPERCASE, JSON, Base64, QR code…"))
                    tip(L("Notlarda Return listeyi sürdürür; kutuya tıkla ya da ⌘L ile işaretle.", "In notes, Return continues a list; click a box or press ⌘L to tick it."))
                    tip(L("Bir video bağlantısını başlatıcıya yapıştır: video ya da sesi indirir.", "Paste a video link into the launcher to save the video or its sound."))
                    tip(L("Menü çubuğundaki simgeye sağ tıkla: kısa menü.", "Right-click the menu bar item for a short menu."))
                    tip(L("Kendi betiklerin: Ayarlar → Başlatıcı → Betik klasörü.", "Your own scripts: Settings → Launcher → Scripts folder."))
                }
            }
            .padding(Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.l)
        }
        .scrollIndicators(.never)
        .frame(minWidth: 520, minHeight: 420)
        .background(MenuMaterial().ignoresSafeArea())
        .appearanceRoot(opaqueFill: Theme.surface)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(verbatim: title).font(Theme.smallStrong).foregroundStyle(Theme.textMuted)
            content()
        }
    }

    private func shortcut(_ keys: String, _ text: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(verbatim: keys).font(Theme.bodyStrong).monospacedDigit().foregroundStyle(Theme.text)
                .padding(.horizontal, Theme.Spacing.s).padding(.vertical, 2)
                .background(Theme.track, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
                .frame(width: 120, alignment: .leading)
            Text(verbatim: text).font(Theme.body).foregroundStyle(Theme.text)
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text(verbatim: "•").foregroundStyle(Theme.accent)
            Text(verbatim: text).font(Theme.body).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
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
