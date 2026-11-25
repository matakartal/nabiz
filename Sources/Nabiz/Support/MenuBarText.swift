import AppKit

/// One thing shown in the menu bar: a short label and its value.
struct MenuBarPart {
    let item: MenuBarItem
    let label: String
    let value: String
}

/// What the status item shows, built from the items the user picked in Settings.
/// Two layouts: stacked (label over value, two lines, narrow) or a single line.
@MainActor
enum MenuBarText {
    static var stacked: Bool { Prefs.string(Prefs.barStyle) != "line" }

    static func parts(monitor: Monitor?) -> [MenuBarPart] {
        MenuBarItem.allCases.filter { Prefs.bool($0.key) }.compactMap { part(for: $0, monitor: monitor) }
    }

    /// The single-line text: "CPU 34%  RAM 81%".
    static func compose(monitor: Monitor?) -> String {
        let labels = Prefs.bool(Prefs.barLabels)
        return parts(monitor: monitor).map { part in
            switch part.item {
            case .network: "\(part.label) \(part.value)"
            case .currency where !labels: Format.symbol(part.label) + part.value
            default: labels ? "\(part.label) \(part.value)" : part.value
            }
        }
        .joined(separator: "  ")
    }

    private static func part(for item: MenuBarItem, monitor: Monitor?) -> MenuBarPart? {
        let system = monitor?.system
        func make(_ label: String, _ value: String?) -> MenuBarPart? { value.map { MenuBarPart(item: item, label: label, value: $0) } }

        switch item {
        case .cpu:
            return make("CPU", system.map { Format.percent($0.cpu) })
        case .ram:
            return make("RAM", system.map { Format.percent($0.memoryFraction) })
        case .gpu:
            return make("GPU", system?.gpu.map { Format.percent($0) })
        case .swap:
            return make(L("Takas", "Swap"), system.map { Format.bytes($0.swapUsed) })
        case .network:
            guard let network = monitor?.network else { return nil }
            return make("↓" + Format.rate(network.down), "↑" + Format.rate(network.up))
        case .disk:
            return make("Disk", system?.diskFree.map { Format.bytes($0) })
        case .battery:
            guard let battery = monitor?.battery else { return nil }
            return make(L("Pil", "Battery"), Format.percent(Double(battery.percent) / 100) + (battery.charging ? "⚡︎" : ""))
        case .ai:
            guard let status = AILimitsStore.shared.statuses.first(where: { !$0.limits.isEmpty }),
                  let top = status.headline else { return nil }
            return make(status.provider.shortName, top.shortText)
        case .market:
            let store = MarketStore.shared
            let chosen = Prefs.string(Prefs.barMarketID)
            guard let market = store.markets[chosen] ?? store.watched.first else { return nil }
            return make(market.name, Format.price(market.price))
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
        let color = NSColor.black
        let columns = parts.map { part -> (label: NSAttributedString, value: NSAttributedString, width: CGFloat) in
            // The network column is two small lines (down over up); the rest are a small label over a bold value.
            let valueAttributes: [NSAttributedString.Key: Any] = [.font: part.item == .network ? labelFont : valueFont, .foregroundColor: color]
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
                icon.draw(in: NSRect(x: 0, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
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
        image.isTemplate = true
        return image
    }
}
