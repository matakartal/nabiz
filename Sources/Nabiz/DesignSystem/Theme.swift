import AppKit
import SwiftUI

/// Kartal UI on macOS: the same tokens as the iOS/Android templates, resolved through AppKit appearances.
/// Near-white / near-black surfaces, one accent, orange only for "running low", red only for alarms.
enum Theme {
    /// The one accent, chosen in Settings → Appearance. Read live: never copy it into a stored constant.
    static var accent: Color { AccentChoice.current.color }
    /// Alarms only: critical memory pressure, a hot Mac.
    static let danger = Color(nsColor: .systemRed)
    /// "Running low": high swap, busy CPU. Bars use `fill`, text uses `mark`.
    static let warning = Palette.orange

    static let surface = dynamic(light: .white(0.985), dark: .white(0.09))
    static let surfaceRaised = dynamic(light: .white(1), dark: .white(0.14))
    static let field = dynamic(light: .white(0.94), dark: .white(0.17))
    static let text = dynamic(light: .white(0.07), dark: .white(0.95))
    static let textMuted = dynamic(light: .white(0.42), dark: .white(0.62))
    static let hairline = dynamic(light: .white(0, alpha: 0.08), dark: .white(1, alpha: 0.10))
    /// Fills on the frosted menu material: a row under the pointer, a graph's track.
    static let hover = dynamic(light: .white(0, alpha: 0.07), dark: .white(1, alpha: 0.10))
    static let track = dynamic(light: .white(0, alpha: 0.05), dark: .white(1, alpha: 0.06))

    // Two sizes and two weights per screen, at macOS menu scale (iOS 16/13 → macOS 13/11).
    // "Large text" in Settings → Appearance adds one point to each; the typeface can be rounded or monospaced.
    private static var bump: CGFloat { UserDefaults.standard.string(forKey: "textSize") == "large" ? 1 : 0 }
    private static var design: Font.Design {
        switch UserDefaults.standard.string(forKey: "fontDesign") {
        case "rounded": .rounded
        case "mono": .monospaced
        default: .default
        }
    }
    static var title: Font { .system(size: 15 + bump, weight: .semibold, design: design) }
    static var body: Font { .system(size: 13 + bump, weight: .regular, design: design) }
    static var bodyStrong: Font { .system(size: 13 + bump, weight: .semibold, design: design) }
    static var small: Font { .system(size: 11 + bump, weight: .regular, design: design) }
    static var smallStrong: Font { .system(size: 11 + bump, weight: .semibold, design: design) }
    /// The launcher's input line, Spotlight-sized.
    static var input: Font { .system(size: 20, weight: .regular, design: design) }
    static var inputStrong: Font { .system(size: 20, weight: .semibold, design: design) }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    static let radius: CGFloat = 10
    static let fieldRadius: CGFloat = 6
    static let dot: CGFloat = 6
    /// Height of a usage bar: thin or thick, from Settings → Appearance.
    static var meter: CGFloat { UserDefaults.standard.string(forKey: "meterStyle") == "thick" ? 5 : 3 }
    /// Menu-panel grid, copied from native macOS menus so every row lines up:
    /// icons start `menuInset` in, text starts `menuTextInset` in, values end `menuInset` before the edge.
    static let menuInset: CGFloat = 16
    static let menuTextInset: CGFloat = 40
    static let menuHighlightInset: CGFloat = 6
    static let menuIcon: CGFloat = 16
    /// Compact, normal or roomy, from Settings → Appearance.
    static var menuRow: CGFloat {
        switch UserDefaults.standard.string(forKey: "density") {
        case "compact": 22
        case "roomy": 28
        default: 24
        }
    }
    static let menuValueColumn: CGFloat = 76
    static let menuPercentColumn: CGFloat = 64
    static let menuResetColumn: CGFloat = 44
    /// A short row under a heading row (AI limit lines).
    static let menuLine: CGFloat = 20
    /// A tool tile in the panel's grid: one line of symbol, title and an optional value.
    static var toolTile: CGFloat { menuRow + 6 }
    static let toolColumns = 2
    /// Settings sidebar icon tile.
    static let settingsIcon: CGFloat = 22
    /// The icon tile in a Settings page's header.
    static let settingsHeaderIcon: CGFloat = 40
    /// One chart in the History window.
    static let historyChart: CGFloat = 80
    /// The launcher: a Spotlight-wide field over a list, with a key hint footer.
    static let launcherWidth: CGFloat = 680
    static let launcherHeight: CGFloat = 440
    static let launcherField: CGFloat = 52
    static let launcherFooter: CGFloat = 32
    static let launcherRow: CGFloat = 34
    static let launcherIcon: CGFloat = 20
    /// The list beside the clipboard preview.
    static let launcherList: CGFloat = 300
    /// Where text starts inside a grouped form row, so footers line up with it.
    static let formInset: CGFloat = 10
    /// The menu bar panel: one narrow column.
    /// Narrow, normal or wide, from Settings → Appearance.
    static var menuPanelWidth: CGFloat {
        let width = UserDefaults.standard.integer(forKey: "panelWidth")
        return [300, 320, 360].contains(width) ? CGFloat(width) : 320
    }
    /// Never taller than the screen below the menu bar.
    @MainActor static var menuPanelMaxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 720) - Spacing.xxl
    }

    struct RGBA: Sendable {
        var r, g, b, a: CGFloat
        static func white(_ w: CGFloat, alpha: CGFloat = 1) -> RGBA { RGBA(r: w, g: w, b: w, a: alpha) }
        static func hex(_ v: UInt32) -> RGBA {
            RGBA(r: CGFloat((v >> 16) & 0xFF) / 255, g: CGFloat((v >> 8) & 0xFF) / 255, b: CGFloat(v & 0xFF) / 255, a: 1)
        }
        var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    }

    static func dynamic(light: RGBA, dark: RGBA) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark.nsColor : light.nsColor
        })
    }
}

/// Palette colours: `fill` carries white glyphs or fills a bar; `mark` is for text and lines.
struct Tone: Sendable {
    let fill: Color
    let mark: Color
}

enum Palette {
    static let green = Tone(fill: Theme.dynamic(light: .hex(0x1DB954), dark: .hex(0x1DB954)),
                            mark: Theme.dynamic(light: .hex(0x0F8038), dark: .hex(0x3DDC74)))
    static let orange = Tone(fill: Theme.dynamic(light: .hex(0xEE7A2A), dark: .hex(0xEE7A2A)),
                             mark: Theme.dynamic(light: .hex(0xB5500A), dark: .hex(0xF79A5C)))
}

struct TextButtonStyle: ButtonStyle {
    var font: Font = Theme.body
    var color: Color?
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(configuration.role == .destructive ? Theme.danger : (color ?? Theme.text))
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == TextButtonStyle {
    static var text: TextButtonStyle { TextButtonStyle() }
}

/// A thin usage bar on the field track.
struct MeterBar: View {
    let value: Double
    let fill: Color
    /// The smallest visible fill, so a tiny value still shows; 0 lets an empty bar look empty.
    var minimum: CGFloat = Theme.meter

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.field)
                if value > 0 || minimum > 0 {
                    Capsule().fill(fill).frame(width: max(minimum, geo.size.width * min(max(value, 0), 1)))
                }
            }
        }
        .frame(height: Theme.meter)
    }
}

/// Hides every scroller in the window it lands in, even with "Show scroll bars: Always" on.
/// SwiftUI's `.scrollIndicators(.never)` is overridden by that system setting; the scroll views still scroll.
struct HiddenScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) { (nsView as? Probe)?.hideSoon() }

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hideSoon()
        }

        func hideSoon() {
            // Pages lay out their scroll views a moment after they appear.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.hide() }
            }
        }

        private func hide() {
            guard let root = window?.contentView else { return }
            var stack: [NSView] = [root]
            while let view = stack.popLast() {
                if let scroll = view as? NSScrollView {
                    scroll.hasVerticalScroller = false
                    scroll.hasHorizontalScroller = false
                    scroll.scrollerStyle = .overlay
                }
                stack.append(contentsOf: view.subviews)
            }
        }
    }
}

/// The frosted material native menus use; the panel, calculator and Settings all sit on it.
struct MenuMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// The accent colours on offer, plus the system accent and one of your own.
/// Orange and red are left out on purpose: they mean "running low" and "danger".
enum AccentChoice: String, CaseIterable, Identifiable {
    case green, mint, lime, teal, cyan, sky, blue, cobalt, indigo, violet, purple, magenta, pink, gold, cocoa, slate, graphite
    case system, custom

    var id: String { rawValue }

    /// The swatches in the grid; system and custom have their own rows.
    static var swatches: [AccentChoice] { allCases.filter { $0 != .system && $0 != .custom } }

    static var current: AccentChoice {
        AccentChoice(rawValue: UserDefaults.standard.string(forKey: "accentColor") ?? "") ?? .green
    }

    var color: Color {
        switch self {
        case .green: Palette.green.fill
        case .mint: Theme.dynamic(light: .hex(0x00B386), dark: .hex(0x34D3A6))
        case .lime: Theme.dynamic(light: .hex(0x6BA80F), dark: .hex(0x9AD62E))
        case .teal: Theme.dynamic(light: .hex(0x14A89A), dark: .hex(0x2DC4B4))
        case .cyan: Theme.dynamic(light: .hex(0x0AA3BF), dark: .hex(0x32C5DD))
        case .sky: Theme.dynamic(light: .hex(0x0A9BD8), dark: .hex(0x38B6EE))
        case .blue: Theme.dynamic(light: .hex(0x2F6FEB), dark: .hex(0x4C8BFF))
        case .cobalt: Theme.dynamic(light: .hex(0x1F4FC2), dark: .hex(0x5A7EF0))
        case .indigo: Theme.dynamic(light: .hex(0x5350D6), dark: .hex(0x7471F0))
        case .violet: Theme.dynamic(light: .hex(0x8A4FE0), dark: .hex(0xA374F2))
        case .purple: Theme.dynamic(light: .hex(0xA43FC4), dark: .hex(0xC265E0))
        case .magenta: Theme.dynamic(light: .hex(0xC2389E), dark: .hex(0xE25DBE))
        case .pink: Theme.dynamic(light: .hex(0xDB3E8A), dark: .hex(0xF060A6))
        case .gold: Theme.dynamic(light: .hex(0xB8901A), dark: .hex(0xE0B83E))
        case .cocoa: Theme.dynamic(light: .hex(0x8B6346), dark: .hex(0xB78B6A))
        case .slate: Theme.dynamic(light: .hex(0x4F6B84), dark: .hex(0x7F9AB3))
        case .graphite: Theme.dynamic(light: .hex(0x6E6E73), dark: .hex(0x98989D))
        case .system: Color(nsColor: .controlAccentColor)
        case .custom:
            Color(hex: UserDefaults.standard.string(forKey: "customAccent") ?? "") ?? Palette.green.fill
        }
    }

    var title: String {
        switch self {
        case .green: L("Yeşil", "Green")
        case .mint: L("Nane", "Mint")
        case .lime: L("Limon", "Lime")
        case .teal: L("Turkuaz", "Teal")
        case .cyan: L("Camgöbeği", "Cyan")
        case .sky: L("Gök mavisi", "Sky")
        case .blue: L("Mavi", "Blue")
        case .cobalt: L("Kobalt", "Cobalt")
        case .indigo: L("Çivit", "Indigo")
        case .violet: L("Menekşe", "Violet")
        case .purple: L("Mor", "Purple")
        case .magenta: L("Eflatun", "Magenta")
        case .pink: L("Pembe", "Pink")
        case .gold: L("Altın", "Gold")
        case .cocoa: L("Kakao", "Cocoa")
        case .slate: L("Arduvaz", "Slate")
        case .graphite: L("Grafit", "Graphite")
        case .system: L("Sistem", "System")
        case .custom: L("Özel", "Custom")
        }
    }
}

/// Re-renders a window's content when anything in Settings → Appearance (or the language) changes, and gives it
/// the chosen background: the frosted menu material, or opaque.
struct AppearanceRoot: ViewModifier {
    @AppStorage("language") private var language = "system"
    @AppStorage("accentColor") private var accent = "green"
    @AppStorage("customAccent") private var customAccent = "#1DB954"
    @AppStorage("textSize") private var textSize = "normal"
    @AppStorage("fontDesign") private var fontDesign = "standard"
    @AppStorage("density") private var density = "normal"
    @AppStorage("meterStyle") private var meterStyle = "thin"
    @AppStorage("panelWidth") private var width = 320
    @AppStorage("panelStyle") private var style = "material"
    var opaqueFill = Theme.surfaceRaised

    func body(content: Content) -> some View {
        content
            .background(style == "opaque" ? opaqueFill : Color.clear)
            .tint(Theme.accent)
            .id("\(language)-\(accent)-\(customAccent)-\(textSize)-\(fontDesign)-\(density)-\(meterStyle)-\(width)-\(style)")
    }
}

/// Light, dark or follow macOS, for Nabız's own windows.
@MainActor
enum AppearanceMode {
    static func apply() {
        switch UserDefaults.standard.string(forKey: "appearanceMode") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}

extension View {
    func appearanceRoot(opaqueFill: Color = Theme.surfaceRaised) -> some View { modifier(AppearanceRoot(opaqueFill: opaqueFill)) }
}
