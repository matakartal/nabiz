// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import SwiftUI

// MARK: - Each AI's own look

/// The colours each AI's own app uses, so a chat with Claude feels like Claude and one with Apple like Apple Intelligence.
struct AIBrand {
    let colors: [Color]
    var tint: Color { colors[0] }
    /// Several colours (Apple, Gemini): edges and highlights use the whole gradient, not one colour.
    var multicolor: Bool { colors.count > 3 }
    /// A ring of the colours, for edges.
    var ring: AngularGradient { AngularGradient(colors: colors + [colors[0]], center: .center) }
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }

    static func rgb(_ value: UInt32) -> Color { Color(nsColor: Theme.RGBA.hex(value).nsColor) }
}

extension AIEngine {
    @MainActor var brand: AIBrand {
        switch self {
        case .claude: AIBrand(colors: [AIBrand.rgb(0xD97757), AIBrand.rgb(0xE9A37F), AIBrand.rgb(0xC15F3C)])
        case .codex: AIBrand(colors: [AIBrand.rgb(0x3B3AF2), AIBrand.rgb(0x7D8DF7), AIBrand.rgb(0xB8A6F5)])
        case .grok: AIBrand(colors: [Theme.text, Theme.textMuted, Theme.text.opacity(0.6)])
        case .gemini: AIBrand(colors: [AIBrand.rgb(0x4796E3), AIBrand.rgb(0x9177C7), AIBrand.rgb(0xCA6673)])
        // Apple Intelligence's own palette; purple leads, so where one colour is needed it's the purple.
        case .onDevice: AIBrand(colors: [AIBrand.rgb(0xA97CF8), AIBrand.rgb(0x8D9FFF), AIBrand.rgb(0xF5B9EA),
                                         AIBrand.rgb(0xFF6778), AIBrand.rgb(0xFFBA71), AIBrand.rgb(0xC686FF)])
        case .auto: AIEngines.shared.resolved?.brand ?? AIBrand(colors: [Theme.accent, Theme.accent.opacity(0.6)])
        }
    }
}

/// A sun of tapered rays (Claude's look).
struct Starburst: Shape {
    var rays = 11

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for index in 0..<rays {
            let angle = Double(index) / Double(rays) * 2 * .pi - .pi / 2
            let length = radius * (0.78 + 0.22 * Double((index * 7) % 5) / 4)
            let width = 0.16
            let tip = CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length)
            let left = CGPoint(x: center.x + cos(angle - width) * radius * 0.16, y: center.y + sin(angle - width) * radius * 0.16)
            let right = CGPoint(x: center.x + cos(angle + width) * radius * 0.16, y: center.y + sin(angle + width) * radius * 0.16)
            path.move(to: center)
            path.addLine(to: left)
            path.addLine(to: tip)
            path.addLine(to: right)
            path.closeSubpath()
        }
        path.addEllipse(in: CGRect(x: center.x - radius * 0.2, y: center.y - radius * 0.2, width: radius * 0.4, height: radius * 0.4))
        return path
    }
}

/// A four-pointed sparkle with curved sides (Gemini's look).
struct Sparkle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: center)
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: center)
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: center)
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: center)
        path.closeSubpath()
        return path
    }
}

/// The providers' real marks, read from their apps on this Mac (nothing is copied into Nabız): Claude's spark from
/// the Claude app, the Codex icon from the ChatGPT/Codex app. Missing apps fall back to drawn marks.
@MainActor
enum AILogos {
    private static var cache: [String: NSImage?] = [:]

    private static func app(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private static func load(_ key: String, _ make: () -> NSImage?) -> NSImage? {
        if let cached = cache[key] { return cached }
        let image = make()
        cache[key] = image
        return image
    }

    /// Claude's spark as a template image, to tint in Claude's colour.
    static var claude: NSImage? {
        load("claude") {
            guard let app = app("com.anthropic.claudefordesktop") else { return nil }
            let resources = app.appendingPathComponent("Contents/Resources")
            for name in ["TrayIconTemplate@3x.png", "TrayIconTemplate@2x.png", "TrayIconTemplate.png"] {
                if let image = NSImage(contentsOf: resources.appendingPathComponent(name)) {
                    image.isTemplate = true
                    return image
                }
            }
            return nil
        }
    }

    /// The Codex app icon, light or dark.
    static func codex(dark: Bool) -> NSImage? {
        load(dark ? "codex.dark" : "codex.light") {
            for id in ["com.openai.codex", "com.openai.chat"] {
                guard let app = app(id) else { continue }
                let resources = app.appendingPathComponent("Contents/Resources")
                for name in dark ? ["icon-codex-dark-color.png", "icon-codex-light.png"] : ["icon-codex-light.png", "icon-codex-dark-color.png"] {
                    if let image = NSImage(contentsOf: resources.appendingPathComponent(name)) { return image }
                }
            }
            return nil
        }
    }
}

/// The AI's mark, still or "thinking": Claude's real spark turns and breathes, the Codex icon breathes, Gemini's
/// sparkle spins, Apple's symbol runs through its colours. Still with Reduce Motion.
struct AIBrandMark: View {
    let engine: AIEngine
    var size: CGFloat = 16
    var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if animating && !reduceMotion {
                TimelineView(.animation) { context in mark(context.date.timeIntervalSinceReferenceDate) }
            } else {
                mark(nil)
            }
        }
        .frame(width: size, height: size)
    }

    private static let appleSymbol = NSImage(systemSymbolName: "apple.intelligence", accessibilityDescription: nil) != nil ? "apple.intelligence" : "sparkles"

    @ViewBuilder private func mark(_ time: Double?) -> some View {
        let brand = engine.brand
        let t = time ?? 0
        let breathe = time == nil ? 1 : 0.9 + 0.1 * sin(t * 4)
        switch engine {
        case .claude, .auto:
            if let logo = AILogos.claude {
                // Claude's own thinking motion: the spark turns while it breathes.
                Image(nsImage: logo).renderingMode(.template).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .foregroundStyle(brand.tint)
                    .rotationEffect(.degrees(time == nil ? 0 : t * 60))
                    .scaleEffect(breathe)
            } else {
                Starburst().fill(brand.tint).rotationEffect(.degrees(time == nil ? 0 : t * 50)).scaleEffect(breathe)
            }
        case .codex:
            if let logo = AILogos.codex(dark: scheme == .dark) {
                Image(nsImage: logo).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .scaleEffect(1.22)
                    .scaleEffect(time == nil ? 1 : 0.88 + 0.12 * (0.5 + 0.5 * sin(t * 5)))
                    .brightness(time == nil ? 0 : 0.06 * sin(t * 5))
            } else {
                Circle().fill(brand.tint).frame(width: size * 0.62, height: size * 0.62)
                    .scaleEffect(time == nil ? 1 : 0.78 + 0.22 * (0.5 + 0.5 * sin(t * 5)))
            }
        case .grok:
            // A ring cut by a slash, in Grok's black and white.
            ZStack {
                Circle().trim(from: 0.08, to: 0.62).stroke(brand.tint, style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round))
                    .rotationEffect(.degrees(-20))
                Capsule().fill(brand.tint).frame(width: size * 0.13, height: size * 1.05).rotationEffect(.degrees(40))
            }
            .padding(size * 0.08)
            .rotationEffect(.degrees(time == nil ? 0 : t * 90))
            .scaleEffect(time == nil ? 1 : 0.9 + 0.1 * sin(t * 4))
        case .gemini:
            Sparkle()
                .fill(AngularGradient(colors: brand.colors + [brand.colors[0]], center: .center, angle: .degrees(t * 120)))
                .rotationEffect(.degrees(time == nil ? 0 : t * 70))
                .scaleEffect(time == nil ? 1 : 0.88 + 0.12 * sin(t * 3))
        case .onDevice:
            Image(systemName: Self.appleSymbol)
                .font(.system(size: size * 0.86, weight: .medium))
                .foregroundStyle(AngularGradient(colors: brand.colors + [brand.colors[0]], center: .center, angle: .degrees(t * 120)))
                .scaleEffect(time == nil ? 1 : 0.94 + 0.06 * sin(t * 3))
        }
    }
}

// MARK: - Shimmer

/// A band of colour sweeping across the view, masked to its shape: "the AI is working". Stays still with Reduce Motion.
struct Shimmer: ViewModifier {
    var active = true
    var duration = 1.6
    var color: Color = Theme.accent
    /// A band of several colours (Apple Intelligence's sweep) instead of one.
    var colors: [Color]?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.overlay {
                TimelineView(.animation) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration
                    GeometryReader { geometry in
                        let band = max(geometry.size.width * 0.45, 40)
                        LinearGradient(colors: [.clear] + (colors ?? [color]) + [.clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: -band + (geometry.size.width + band) * phase)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

extension View {
    func shimmer(_ active: Bool = true, duration: Double = 1.6, color: Color = Theme.accent, colors: [Color]? = nil) -> some View {
        modifier(Shimmer(active: active, duration: duration, color: color, colors: colors))
    }

    /// The AI's own shimmer: Apple's and Gemini's sweep through their colours, the others in their one colour.
    @MainActor func shimmer(_ active: Bool = true, engine: AIEngine, duration: Double = 1.6) -> some View {
        let brand = engine.brand
        return modifier(Shimmer(active: active, duration: duration, color: brand.tint, colors: brand.multicolor ? brand.colors : nil))
    }
}

/// "Claude is thinking…" with its mark moving and the words shimmering in its colour.
struct AIThinkingLabel: View {
    let engine: AIEngine
    var text: String?
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            AIBrandMark(engine: engine, size: size + 5, animating: true)
            Text(verbatim: text ?? L("\(engine.shortName) düşünüyor…", "\(engine.shortName) is thinking…"))
                .font(.system(size: size))
                .foregroundStyle(Theme.textMuted)
                .shimmer(engine: engine)
        }
    }
}

/// Grey lines where the answer will be, shimmering until the first words arrive.
struct AISkeleton: View {
    var color: Color = Theme.accent
    private let widths: [CGFloat] = [1, 0.92, 0.74]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(widths.indices, id: \.self) { index in
                GeometryReader { geometry in
                    Capsule().fill(Theme.textMuted.opacity(0.18))
                        .frame(width: geometry.size.width * widths[index])
                }
                .frame(height: 10)
            }
        }
        .shimmer(duration: 1.4, color: color.opacity(0.6))
    }
}

// MARK: - Glow

/// Light running around the edge while an answer is being written, in the AI's colours: Apple Intelligence's
/// moving rainbow (layers of soft light whose colours drift, like Siri's edge), Gemini's blues, Claude's coral.
/// A faint still edge with Reduce Motion.
struct AIGlow: View {
    let engine: AIEngine
    let active: Bool
    var cornerRadius: CGFloat = Theme.radius
    var lineWidth: CGFloat = 1.5
    /// Softer, wider light, for a whole window's edge.
    var wide = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = engine.brand.colors
        TimelineView(.animation(paused: !active || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let gradient = AngularGradient(stops: Self.stops(colors, time: t), center: .center, angle: .degrees((t * 40).truncatingRemainder(dividingBy: 360)))
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                // Soft outer light, a brighter band, then a fine line: Siri's edge, kept thin enough not to cover the window.
                shape.strokeBorder(gradient, lineWidth: lineWidth * (wide ? 6 : 8)).blur(radius: wide ? 14 : 12).opacity(wide ? 0.4 : 0.35)
                shape.strokeBorder(gradient, lineWidth: lineWidth * (wide ? 3 : 4)).blur(radius: wide ? 5 : 6).opacity(wide ? 0.5 : 0.6)
                shape.strokeBorder(gradient, lineWidth: lineWidth * (wide ? 1.4 : 1.4)).blur(radius: 1.5)
                shape.strokeBorder(gradient, lineWidth: lineWidth * 0.8)
            }
        }
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: 0.5), value: active)
        .allowsHitTesting(false)
    }

    /// Colour stops that drift on their own slow waves, so the light moves rather than just turning.
    static func stops(_ colors: [Color], time: Double) -> [Gradient.Stop] {
        let count = Double(colors.count)
        var stops = colors.enumerated().map { index, color in
            let base = Double(index) / count
            let drift = 0.06 * sin(time * (0.9 + Double(index) * 0.23) + Double(index) * 1.7)
            return Gradient.Stop(color: color, location: min(max(base + drift, 0), 0.999))
        }
        stops.sort { $0.location < $1.location }
        if let first = stops.first { stops.append(Gradient.Stop(color: first.color, location: 1)) }
        return stops
    }
}

/// The line under the launcher field: the AI's colour running along it while an answer is coming.
struct AIProgressLine: View {
    let running: Bool
    var color: Color = Theme.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: running ? 2 : 1)
            .overlay { if running && !reduceMotion { light } }
            .animation(.easeOut(duration: 0.2), value: running)
    }

    private var light: some View {
        TimelineView(.animation) { context in
            let duration = 1.2
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration
            GeometryReader { geometry in
                let band = geometry.size.width * 0.35
                LinearGradient(colors: [.clear, color, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: band)
                    .offset(x: -band + (geometry.size.width + band) * phase)
            }
        }
        .clipped()
    }
}
