// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit

/// One thing shown in the menu bar: a short label and its value.
struct MenuBarPart {
    /// With "coloured values" on: what the value is saying. Otherwise everything is drawn in the menu bar's own colour.
    enum Tone { case normal, warning, danger, up, down }

    let item: MenuBarItem
    let label: String
    let value: String
    var tone: Tone = .normal

    var color: NSColor {
        switch tone {
        case .normal: .labelColor
        case .warning: .systemOrange
        case .danger: .systemRed
        case .up: .systemGreen
        case .down: .systemRed
        }
    }
}

/// What the status item shows, built from the items the user picked in Settings.
/// Two layouts: stacked (label over value, two lines, narrow) or a single line.
@MainActor
enum MenuBarText {
    static var stacked: Bool { Prefs.string(Prefs.barStyle) != "line" }

    static func parts(monitor: Monitor?) -> [MenuBarPart] {
        var parts = MenuBarItem.allCases.filter { Prefs.bool($0.key) }.compactMap { part(for: $0, monitor: monitor) }
        // A running timer always shows first: it is what the user is waiting on.
        if let left = CountdownTimer.shared.remainingText {
            parts.insert(MenuBarPart(item: .timer, label: L("Süre", "Timer"), value: left), at: 0)
        }
        // So do a Pomodoro block and a timed focus session.
        let pomodoro = Pomodoro.shared
        if let left = pomodoro.remainingText {
            let label = pomodoro.phase == .work ? L("Odak", "Focus") : L("Mola", "Break")
            parts.insert(MenuBarPart(item: .timer, label: label, value: (pomodoro.isRunning ? "" : "⏸ ") + left), at: 0)
        } else if FocusMode.shared.isOn {
            parts.insert(MenuBarPart(item: .timer, label: L("Odak", "Focus"), value: FocusMode.shared.remainingText ?? L("açık", "on")), at: 0)
        }
        return parts
    }

    /// The single-line text: "CPU 34%  RAM 81%".
    static func compose(monitor: Monitor?) -> String {
        let labels = Prefs.bool(Prefs.barLabels)
        return parts(monitor: monitor).map { part in
            switch part.item {
            case .network: "\(part.label) \(part.value)"
            case .timer: "⏱ \(part.value)"
            case .currency where !labels: Format.symbol(part.label) + part.value
            default: labels ? "\(part.label) \(part.value)" : part.value
            }
        }
        .joined(separator: "  ")
    }

    /// The single-line text with each value in its tone's colour.
    static func colouredLine(monitor: Monitor?, font: NSFont, leadingSpace: Bool) -> NSAttributedString {
        let labels = Prefs.bool(Prefs.barLabels)
        let line = NSMutableAttributedString()
        for (index, part) in parts(monitor: monitor).enumerated() {
            let prefix = (index == 0 ? (leadingSpace ? " " : "") : "  ")
            let label: String = switch part.item {
            case .network: part.label + " "
            case .timer: "⏱ "
            case .currency where !labels: Format.symbol(part.label)
            default: labels ? part.label + " " : ""
            }
            line.append(NSAttributedString(string: prefix + label, attributes: [.font: font]))
            line.append(NSAttributedString(string: part.value, attributes: [.font: font, .foregroundColor: part.color]))
        }
        return line
    }

    private static func part(for item: MenuBarItem, monitor: Monitor?) -> MenuBarPart? {
        let system = monitor?.system
        /// CPU/GPU: red when pegged, orange when busy.
        func load(_ value: Double?) -> MenuBarPart.Tone {
            guard let value else { return .normal }
            return value >= 0.9 ? .danger : value >= 0.7 ? .warning : .normal
        }
        func make(_ label: String, _ value: String?, _ tone: MenuBarPart.Tone = .normal) -> MenuBarPart? {
            value.map { MenuBarPart(item: item, label: label, value: $0, tone: tone) }
        }

        switch item {
        case .cpu:
            return make("CPU", system.map { Format.percent($0.cpu) }, load(system?.cpu))
        case .ram:
            let tone: MenuBarPart.Tone = switch system?.pressure {
            case .critical: .danger
            case .warning: .warning
            default: .normal
            }
            return make("RAM", system.map { Format.percent($0.memoryFraction) }, tone)
        case .gpu:
            return make("GPU", system?.gpu.map { Format.percent($0) }, load(system?.gpu))
        case .swap:
            return make(L("Takas", "Swap"), system.map { Format.bytes($0.swapUsed) },
                        (system?.swapFraction ?? 0) > 0.6 ? .warning : .normal)
        case .network:
            guard let network = monitor?.network else { return nil }
            return make("↓" + Format.rate(network.down), "↑" + Format.rate(network.up))
        case .disk:
            return make("Disk", system?.diskFree.map { Format.bytes($0) }, (system?.diskFree ?? .max) < 10 << 30 ? .warning : .normal)
        case .battery:
            guard let battery = monitor?.battery else { return nil }
            let tone: MenuBarPart.Tone = battery.plugged ? .normal : battery.percent <= 5 ? .danger : battery.percent <= 15 ? .warning : .normal
            return make(L("Pil", "Battery"), Format.percent(Double(battery.percent) / 100) + (battery.charging ? "⚡︎" : ""), tone)
        case .ai:
            guard let status = AILimitsStore.shared.statuses.first(where: { !$0.limits.isEmpty }),
                  let top = status.headline else { return nil }
            // Coloured by what is left, whichever number is shown: plenty left is green, running out is red.
            // A fast burn (pace behind) only matters once half the limit is gone.
            let behind = top.pace?.status == .behind && top.remaining < 0.5
            let tone: MenuBarPart.Tone = top.remaining < 0.1 ? .danger
                : top.remaining < 0.25 || behind ? .warning
                : top.remaining >= 0.5 ? .up : .normal
            return make(status.provider.shortName, top.shortText, tone)
        case .market:
            let store = MarketStore.shared
            let chosen = Prefs.string(Prefs.barMarketID)
            guard let market = store.markets[chosen] ?? store.watched.first else { return nil }
            let change = market.change ?? 0
            return make(market.name, Format.price(market.price), change > 0.0005 ? .up : change < -0.0005 ? .down : .normal)
        case .timer:
            return nil
        case .currency:
            let base = Prefs.string(Prefs.baseCurrency)
            guard let code = Prefs.watched.first(where: { $0 != base }) else { return nil }
            return make(code, RateStore.shared.convert(1, from: code, to: base).map { Format.number($0, maxDigits: 2, minDigits: 2) })
        }
    }

    /// The stacked layout drawn as one template image, so the system tints it like any other menu bar item.
    static func image(parts: [MenuBarPart], icon: NSImage?, height: CGFloat) -> NSImage {
        let labelFont = NSFont.systemFont(ofSize: 9, weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let coloured = Prefs.bool(Prefs.barColors) && parts.contains { $0.tone != .normal }
        let columns = parts.map { part -> (label: NSAttributedString, value: NSAttributedString, width: CGFloat, roll: BarRoll.Frame?) in
            // Template images draw in black and the system tints them; coloured ones use the menu bar's label colour.
            let color: NSColor = coloured ? .labelColor : .black
            let valueColor: NSColor = coloured ? part.color : .black
            // The network column is two small lines (down over up); the rest are a small label over a bold value.
            let valueAttributes: [NSAttributedString.Key: Any] = [.font: part.item == .network ? labelFont : valueFont, .foregroundColor: valueColor]
            let label = NSAttributedString(string: part.label, attributes: [.font: labelFont, .foregroundColor: color])
            let value = NSAttributedString(string: part.value, attributes: valueAttributes)
            let roll = part.item == .network ? nil : BarRoll.shared.frame(key: "\(part.item.rawValue).\(part.label)", value: part.value)
            return (label, value, ceil(max(label.size().width, value.size().width)), roll)
        }
        let iconSize: CGFloat = 16, iconGap: CGFloat = 5, columnGap: CGFloat = 8
        let width = (icon == nil ? 0 : iconSize + (columns.isEmpty ? 0 : iconGap))
            + columns.reduce(0) { $0 + $1.width } + columnGap * CGFloat(max(columns.count - 1, 0))

        let image = NSImage(size: NSSize(width: max(ceil(width), 1), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            if let icon {
                if coloured {
                    // A template symbol drawn into a non-template image: tint it with the label colour first.
                    let tinted = NSImage(size: icon.size, flipped: false) { rect in
                        icon.draw(in: rect)
                        NSColor.labelColor.set()
                        rect.fill(using: .sourceAtop)
                        return true
                    }
                    tinted.draw(in: NSRect(x: 0, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
                } else {
                    icon.draw(in: NSRect(x: 0, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
                }
                x += iconSize + iconGap
            }
            // Two lines, tightened by their descenders so they fit a 22 pt bar.
            let labelHeight = labelFont.ascender - labelFont.descender
            let valueHeight = valueFont.ascender - valueFont.descender
            let overlap: CGFloat = 2
            let bottom = (height - (labelHeight + valueHeight - overlap)) / 2
            for column in columns {
                let box = NSRect(x: x, y: bottom, width: column.width, height: valueHeight)
                if let roll = column.roll {
                    BarRoll.draw(roll, value: column.value, in: box)
                } else {
                    column.value.draw(at: NSPoint(x: x, y: bottom))
                }
                column.label.draw(at: NSPoint(x: x, y: bottom + valueHeight - overlap))
                x += column.width + columnGap
            }
            return true
        }
        // Template (tinted by the system) unless coloured values are on and something has a colour to show.
        image.isTemplate = !(Prefs.bool(Prefs.barColors) && parts.contains { $0.tone != .normal })
        return image
    }
}

/// A small odometer for the stacked menu bar: when a value changes, the digits that changed roll in
/// (up when the number grew, down when it shrank) over a third of a second.
@MainActor
final class BarRoll {
    static let shared = BarRoll()

    struct Frame {
        let old: String
        let progress: CGFloat
        let up: Bool
    }

    private struct Change { let old: String; let start: Date; let up: Bool }
    private static let duration: TimeInterval = 0.35

    private var shown: [String: String] = [:]
    private var changes: [String: Change] = [:]

    var enabled: Bool { Prefs.bool(Prefs.barAnimate) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Something is still rolling: the status item should redraw again soon.
    var isAnimating: Bool {
        let now = Date()
        changes = changes.filter { now.timeIntervalSince($0.value.start) < Self.duration }
        return !changes.isEmpty
    }

    func frame(key: String, value: String) -> Frame? {
        let previous = shown[key]
        shown[key] = value
        guard enabled else { changes[key] = nil; return nil }
        if let previous, previous != value {
            // A value that changes again mid-roll starts from what is on screen now.
            changes[key] = Change(old: previous, start: Date(), up: Self.grew(from: previous, to: value))
        }
        guard let change = changes[key] else { return nil }
        let t = min(max(Date().timeIntervalSince(change.start) / Self.duration, 0), 1)
        guard t < 1 else { changes[key] = nil; return nil }
        // Ease out: quick start, soft landing.
        let eased = 1 - pow(1 - t, 3)
        return Frame(old: change.old, progress: CGFloat(eased), up: change.up)
    }

    private static func grew(from old: String, to new: String) -> Bool {
        let a = old.filter(\.isNumber), b = new.filter(\.isNumber)
        return a.count == b.count ? b > a : b.count > a.count
    }

    /// Draws `value` with each changed character rolling in from `frame.old`, clipped to `box`.
    static func draw(_ frame: Frame, value: NSAttributedString, in box: NSRect) {
        let attributes = value.attributes(at: 0, effectiveRange: nil)
        let new = Array(value.string), old = Array(frame.old)
        let shift = box.height * frame.progress * (frame.up ? 1 : -1)
        let height = box.height * (frame.up ? 1 : -1)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: box.insetBy(dx: -1, dy: 0)).addClip()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard new.count == old.count else {
            // A different length (e.g. 9% → 10%): roll the whole value.
            NSAttributedString(string: frame.old, attributes: attributes).draw(at: NSPoint(x: box.minX, y: box.minY + shift))
            value.draw(at: NSPoint(x: box.minX, y: box.minY + shift - height))
            return
        }
        var x = box.minX
        for (index, character) in new.enumerated() {
            let glyph = NSAttributedString(string: String(character), attributes: attributes)
            if character == old[index] {
                glyph.draw(at: NSPoint(x: x, y: box.minY))
            } else {
                NSAttributedString(string: String(old[index]), attributes: attributes).draw(at: NSPoint(x: x, y: box.minY + shift))
                glyph.draw(at: NSPoint(x: x, y: box.minY + shift - height))
            }
            x += glyph.size().width
        }
    }
}

/// The symbols on offer for the menu bar icon.
enum BarSymbol {
    static let all = [
        "gauge.with.dots.needle.33percent", "waveform.path.ecg", "heart.fill", "cpu", "memorychip", "bolt.fill",
        "leaf.fill", "sparkle", "circle.hexagongrid.fill", "chart.bar.fill", "flame.fill", "hare.fill",
    ]

    static var current: String {
        let saved = Prefs.string(Prefs.barSymbol)
        return all.contains(saved) ? saved : all[0]
    }

    static func title(_ name: String) -> String {
        switch name {
        case "gauge.with.dots.needle.33percent": L("Gösterge", "Gauge")
        case "waveform.path.ecg": L("Nabız", "Pulse")
        case "heart.fill": L("Kalp", "Heart")
        case "cpu": L("İşlemci", "Chip")
        case "memorychip": L("Bellek", "Memory")
        case "bolt.fill": L("Şimşek", "Bolt")
        case "leaf.fill": L("Yaprak", "Leaf")
        case "sparkle": L("Parıltı", "Sparkle")
        case "circle.hexagongrid.fill": L("Petek", "Hexagons")
        case "chart.bar.fill": L("Grafik", "Chart")
        case "flame.fill": L("Alev", "Flame")
        case "hare.fill": L("Tavşan", "Hare")
        default: name
        }
    }
}
