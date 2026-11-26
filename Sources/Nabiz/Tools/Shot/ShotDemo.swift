// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit

/// Sample marks for `--snapshot … --shot image --seed`: one of each, placed relative to the image.
@MainActor
enum ShotDemo {
    static func seed(_ doc: ShotDocument) {
        let b = doc.bounds
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: b.width * x, y: b.height * y) }
        let palette = ShotInk.palette
        doc.items = [
            ShotItem(kind: .blur, start: p(0.62, 0.08), end: p(0.95, 0.16), ink: palette[0], size: .medium, style: 1),
            ShotItem(kind: .highlight, start: p(0.36, 0.30), end: p(0.70, 0.36), ink: palette[2], size: .medium),
            ShotItem(kind: .rect, start: p(0.33, 0.42), end: p(0.75, 0.58), ink: palette[0], size: .medium),
            ShotItem(kind: .arrow, start: p(0.12, 0.80), end: p(0.31, 0.56), ink: palette[0], size: .medium),
            ShotItem(kind: .arrow, start: p(0.86, 0.86), end: p(0.78, 0.62), ink: palette[4], size: .small, style: 1),
            ShotItem(kind: .ellipse, start: p(0.05, 0.05), end: p(0.25, 0.2), ink: palette[3], size: .medium),
            ShotItem(kind: .counter, start: p(0.33, 0.42), end: p(0.33, 0.42), ink: palette[0], size: .medium),
            ShotItem(kind: .counter, start: p(0.36, 0.30), end: p(0.36, 0.30), ink: palette[0], size: .medium),
            ShotItem(kind: .text, start: p(0.10, 0.84), end: p(0.10, 0.84), text: L("Buraya tıkla", "Click here"), ink: palette[0], size: .medium, style: 1),
            ShotItem(kind: .text, start: p(0.55, 0.88), end: p(0.55, 0.88), text: L("Yeni ayar", "New setting"), ink: palette[7], size: .medium),
            ShotItem(kind: .pen, start: p(0.8, 0.3), end: p(0.95, 0.35),
                     points: (0...20).map { i in p(0.8 + CGFloat(i) * 0.0075, 0.32 + sin(CGFloat(i) / 3) * 0.02) }, ink: palette[5], size: .medium),
        ]
        doc.selection = doc.items[2].id
    }
}
