// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Observation

/// "Tell me when BTC goes above 65,000": one-shot alerts on Hyperliquid prices. An alert fires once when the price
/// crosses its line and then waits, greyed out, until it is re-armed or removed.
struct PriceAlert: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var market: String
    /// True: fires when the price rises to or above `price`; false: when it falls to or below.
    var above: Bool
    var price: Double
    var armed = true
    /// Arms itself again once the price moves back 0.5% past the line, instead of waiting to be re-armed.
    var repeats: Bool?
    var firedAt: Date?

    /// How far the price still has to go, as a fraction of the current price (0.032 = 3.2%).
    func distance(from now: Double) -> Double { now > 0 ? abs(price - now) / now : 0 }
}

@MainActor
@Observable
final class PriceAlerts {
    static let shared = PriceAlerts()
    private static let key = "priceAlerts"

    private(set) var alerts: [PriceAlert] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key) {
            alerts = (try? JSONDecoder().decode([PriceAlert].self, from: data)) ?? []
        }
    }

    /// Markets that need prices even when they aren't watched in the panel.
    var markets: Set<String> { Set(alerts.filter(\.armed).map(\.market)) }

    func add(market: String, above: Bool, price: Double, repeats: Bool = false) {
        alerts.append(PriceAlert(market: market, above: above, price: price, repeats: repeats))
        save()
        Notifier.shared.requestPermission(keepSetting: true)
    }

    func remove(_ alert: PriceAlert) {
        alerts.removeAll { $0.id == alert.id }
        save()
    }

    func rearm(_ alert: PriceAlert) {
        guard let index = alerts.firstIndex(where: { $0.id == alert.id }) else { return }
        alerts[index].armed = true
        alerts[index].firedAt = nil
        save()
    }

    func setRepeats(_ alert: PriceAlert, _ on: Bool) {
        guard let index = alerts.firstIndex(where: { $0.id == alert.id }) else { return }
        alerts[index].repeats = on
        save()
    }

    /// Called after every price update.
    func check(_ markets: [String: Market]) {
        var changed = false
        // Repeating alerts arm again once the price is clearly back on the other side.
        for index in alerts.indices where !alerts[index].armed && alerts[index].repeats == true {
            let alert = alerts[index]
            guard let price = markets[alert.market]?.price else { continue }
            if alert.above ? price < alert.price * 0.995 : price > alert.price * 1.005 {
                alerts[index].armed = true
                changed = true
            }
        }
        for index in alerts.indices where alerts[index].armed {
            let alert = alerts[index]
            guard let market = markets[alert.market] else { continue }
            let crossed = alert.above ? market.price >= alert.price : market.price <= alert.price
            guard crossed else { continue }
            alerts[index].armed = false
            alerts[index].firedAt = Date()
            changed = true
            let line = Format.price(alert.price), now = Format.price(market.price)
            Notifier.shared.post(
                id: "price-\(alert.id)",
                title: alert.above ? L("\(market.name) \(line) üstünde", "\(market.name) above \(line)")
                                   : L("\(market.name) \(line) altında", "\(market.name) below \(line)"),
                body: L("Şu an \(now) · 24 saatte \(Format.change(market.change).isEmpty ? "değişim yok" : Format.change(market.change))",
                        "Now \(now) · 24h \(Format.change(market.change).isEmpty ? "flat" : Format.change(market.change))"))
        }
        if changed { save() }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(alerts), forKey: Self.key)
    }
}
