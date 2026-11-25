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
        func make(_ label: String, _ value: String?, _ tone: MenuBarPart.Tone = .normal) -> MenuBarPart? {
            value.map { MenuBarPart(item: item, label: label, value: $0, tone: tone) }
        }

        switch item {
        case .cpu:
            return make("CPU", system.map { Format.percent($0.cpu) }, (system?.cpu ?? 0) > 0.85 ? .warning : .normal)
        case .ram:
            let tone: MenuBarPart.Tone = switch system?.pressure {
            case .critical: .danger
            case .warning: .warning
            default: .normal
            }
            return make("RAM", system.map { Format.percent($0.memoryFraction) }, tone)
        case .gpu:
            return make("GPU", system?.gpu.map { Format.percent($0) }, (system?.gpu ?? 0) > 0.85 ? .warning : .normal)
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
            let tone: MenuBarPart.Tone = top.remaining < 0.1 || top.pace?.status == .behind ? .danger
                : top.remaining < 0.25 ? .warning : .normal
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
        let columns = parts.map { part -> (label: NSAttributedString, value: NSAttributedString, width: CGFloat) in
            // Template images draw in black and the system tints them; coloured ones use the menu bar's label colour.
            let color: NSColor = coloured ? .labelColor : .black
            let valueColor: NSColor = coloured ? part.color : .black
            // The network column is two small lines (down over up); the rest are a small label over a bold value.
            let valueAttributes: [NSAttributedString.Key: Any] = [.font: part.item == .network ? labelFont : valueFont, .foregroundColor: valueColor]
            let label = NSAttributedString(string: part.label, attributes: [.font: labelFont, .foregroundColor: color])
            let value = NSAttributedString(string: part.value, attributes: valueAttributes)
            return (label, value, ceil(max(label.size().width, value.size().width)))
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
                column.value.draw(at: NSPoint(x: x, y: bottom))
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
