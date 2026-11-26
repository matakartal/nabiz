// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit

/// The screenshot editor's tools, in the order the bar shows them. Each has a one-key shortcut, like Shottr and
/// CleanShot: V, A, L, R, O, P, H, T, N, B, S, C.
enum ShotTool: String, CaseIterable, Identifiable {
    case select, arrow, line, rect, ellipse, pen, highlight, text, counter, blur, spotlight, crop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: L("Seç ve taşı", "Select and move")
        case .arrow: L("Ok", "Arrow")
        case .line: L("Çizgi", "Line")
        case .rect: L("Dikdörtgen", "Rectangle")
        case .ellipse: L("Elips", "Ellipse")
        case .pen: L("Kalem", "Pen")
        case .highlight: L("Vurgula", "Highlight")
        case .text: L("Yazı", "Text")
        case .counter: L("Adım numarası", "Step number")
        case .blur: L("Gizle (bulanık / piksel)", "Hide (blur / pixelate)")
        case .spotlight: L("Spot ışığı", "Spotlight")
        case .crop: L("Kırp", "Crop")
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .pen: "scribble"
        case .highlight: "highlighter"
        case .text: "textformat"
        case .counter: "1.circle"
        case .blur: "checkerboard.rectangle"
        case .spotlight: "rectangle.center.inset.filled"
        case .crop: "crop"
        }
    }

    var key: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rect: "r"
        case .ellipse: "o"
        case .pen: "p"
        case .highlight: "h"
        case .text: "t"
        case .counter: "n"
        case .blur: "b"
        case .spotlight: "s"
        case .crop: "c"
        }
    }

    /// The kind of mark this tool draws (select and crop draw none).
    var kind: ShotItem.Kind? {
        switch self {
        case .select, .crop: nil
        case .arrow: .arrow
        case .line: .line
        case .rect: .rect
        case .ellipse: .ellipse
        case .pen: .pen
        case .highlight: .highlight
        case .text: .text
        case .counter: .counter
        case .blur: .blur
        case .spotlight: .spotlight
        }
    }
}

/// An annotation colour: sRGB components, so it is the same on every screen and in the saved file.
struct ShotInk: Equatable, Hashable, Codable {
    var r, g, b: CGFloat
    var a: CGFloat = 1

    static func hex(_ v: UInt32) -> ShotInk {
        ShotInk(r: CGFloat((v >> 16) & 0xFF) / 255, g: CGFloat((v >> 8) & 0xFF) / 255, b: CGFloat(v & 0xFF) / 255)
    }

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

    /// Perceived brightness, 0…1.
    var luminance: CGFloat { 0.299 * r + 0.587 * g + 0.114 * b }
    /// Black on light colours, white on dark ones: text inside a counter or a label.
    var contrast: ShotInk { luminance > 0.62 ? ShotInk(r: 0.08, g: 0.08, b: 0.08) : ShotInk(r: 1, g: 1, b: 1) }

    /// The palette: the colours screenshot annotations need, readable on light and dark captures.
    static let palette: [ShotInk] = [
        .hex(0xFF3B30), .hex(0xFF9500), .hex(0xFFCC00), .hex(0x34C759),
        .hex(0x0A84FF), .hex(0xAF52DE), .hex(0x1C1C1E), .hex(0xFFFFFF),
    ]

    static var paletteNames: [String] {
        [L("Kırmızı", "Red"), L("Turuncu", "Orange"), L("Sarı", "Yellow"), L("Yeşil", "Green"),
         L("Mavi", "Blue"), L("Mor", "Purple"), L("Siyah", "Black"), L("Beyaz", "White")]
    }
}

/// Small, medium or large: line width, text size and counter size move together.
enum ShotSize: Int, CaseIterable, Identifiable, Codable {
    case small = 1, medium, large

    var id: Int { rawValue }
    var stroke: CGFloat { [2.5, 4, 7][rawValue - 1] }
    var fontSize: CGFloat { [15, 22, 34][rawValue - 1] }
    var counterRadius: CGFloat { [11, 15, 21][rawValue - 1] }
    var title: String { [L("İnce", "Thin"), L("Orta", "Medium"), L("Kalın", "Thick")][rawValue - 1] }
}

/// One mark on the screenshot. Marks stay objects until the image is exported, so any of them can be moved,
/// resized, recoloured or deleted later. Coordinates are image points, origin top-left.
struct ShotItem: Identifiable, Equatable {
    enum Kind: String, Codable {
        case arrow, line, rect, ellipse, pen, highlight, text, counter, blur, spotlight
    }

    var id = UUID()
    var kind: Kind
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []
    var text = ""
    var ink: ShotInk
    var size: ShotSize
    /// The tool's variant: arrow 0 tapered / 1 line / 2 both ends; rect and ellipse 0 outline / 1 filled;
    /// text 0 outlined / 1 on a label; blur 0 blur / 1 pixelate.
    var style = 0

    var rect: CGRect { CGRect(from: start, to: end) }

    /// Moved by `delta`, points and all.
    func offset(by delta: CGVector) -> ShotItem {
        var copy = self
        copy.start = start.moved(delta)
        copy.end = end.moved(delta)
        copy.points = points.map { $0.moved(delta) }
        return copy
    }

    /// Whether it has two ends to drag (lines) or four corners (boxes); pens, text and counters only move.
    var handles: Handles {
        switch kind {
        case .arrow, .line: .ends
        case .rect, .ellipse, .highlight, .blur, .spotlight: .corners
        case .pen, .text, .counter: .none
        }
    }

    enum Handles { case none, ends, corners }

    /// Variants a tool offers, with their symbols and names, for the bottom bar.
    static func styles(for kind: Kind) -> [(symbol: String, title: String)] {
        switch kind {
        case .arrow: [("arrow.up.right", L("Sivri", "Tapered")), ("line.diagonal.arrow", L("Çizgi", "Line")),
                      ("arrow.up.left.and.arrow.down.right", L("İki uçlu", "Both ends"))]
        case .rect: [("rectangle", L("Çerçeve", "Outline")), ("rectangle.fill", L("Dolu", "Filled"))]
        case .ellipse: [("circle", L("Çerçeve", "Outline")), ("circle.fill", L("Dolu", "Filled"))]
        case .text: [("character", L("Kenarlıklı", "Outlined")), ("character.textbox", L("Etiket", "Label"))]
        case .blur: [("drop.halffull", L("Bulanık", "Blur")), ("checkerboard.rectangle", L("Piksel", "Pixelate"))]
        default: []
        }
    }
}

/// The frame around an exported screenshot: a gradient, padding, rounded corners and a shadow.
struct ShotBackground: Equatable {
    var enabled = false
    var preset = 0
    var padding: CGFloat = 48
    var radius: CGFloat = 12
    var shadow = true

    /// Two-colour gradients, top-left to bottom-right; the last one is plain white, the one before it plain dark.
    static let presets: [(ShotInk, ShotInk)] = [
        (.hex(0x5B8CFF), .hex(0x9C6BFF)),
        (.hex(0x34D3A6), .hex(0x2F6FEB)),
        (.hex(0xFF8A65), .hex(0xFF5E9C)),
        (.hex(0xFFD36E), .hex(0xFF8A3D)),
        (.hex(0xA8E063), .hex(0x2DC4B4)),
        (.hex(0xE0E5EC), .hex(0xB8C2CF)),
        (.hex(0x2B2B30), .hex(0x0E0E11)),
        (.hex(0xFFFFFF), .hex(0xFFFFFF)),
    ]
}

extension CGRect {
    init(from a: CGPoint, to b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

extension CGPoint {
    func moved(_ delta: CGVector) -> CGPoint { CGPoint(x: x + delta.dx, y: y + delta.dy) }
    func distance(to other: CGPoint) -> CGFloat { hypot(other.x - x, other.y - y) }

    /// With ⇧: lines snap to 45°, boxes become squares.
    func constrained(from origin: CGPoint, box: Bool) -> CGPoint {
        let dx = x - origin.x, dy = y - origin.y
        if box {
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: origin.x + (dx < 0 ? -side : side), y: origin.y + (dy < 0 ? -side : side))
        }
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        let length = hypot(dx, dy)
        return CGPoint(x: origin.x + cos(angle) * length, y: origin.y + sin(angle) * length)
    }
}
