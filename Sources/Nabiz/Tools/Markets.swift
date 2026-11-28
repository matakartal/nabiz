// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Observation

/// A Hyperliquid perpetual: a main-dex crypto market ("BTC") or a HIP-3 market on a builder-deployed dex
/// ("xyz:TSLA", "para:BTCD") — stocks, indices, commodities and more.
struct Market: Identifiable, Sendable {
    /// The coin name Hyperliquid uses, prefixed with the dex for HIP-3 markets.
    let id: String
    /// "" for the main dex.
    let dex: String
    var price: Double
    var prevDayPrice: Double?
    /// 24-hour notional volume, used to list busy markets first.
    var volume: Double
    /// The hourly funding rate (0.0000125 = 0.00125% an hour): positive means longs pay shorts.
    var funding: Double? = nil

    var name: String { id.split(separator: ":").last.map(String.init) ?? id }

    var change: Double? {
        guard let prevDayPrice, prevDayPrice > 0 else { return nil }
        return price / prevDayPrice - 1
    }

    var tradeURL: URL? { URL(string: "https://app.hyperliquid.xyz/trade/\(id)") }
}

struct MarketDex: Identifiable, Sendable {
    /// "" for the main dex.
    let id: String
    let title: String
}

/// Prices from Hyperliquid's public info API (no key, no account). Only the dexes that hold a watched market are
/// polled for prices; the full catalog of every dex is loaded when Settings needs it.
@MainActor
@Observable
final class MarketStore {
    static let shared = MarketStore()

    private(set) var markets: [String: Market] = [:]
    private(set) var dexes: [MarketDex] = []
    private(set) var loadingCatalog = false
    /// The last fetch got nothing back (offline, or Hyperliquid unreachable).
    private(set) var failed = false
    @ObservationIgnored private var pricesAt: Date?
    @ObservationIgnored private var catalogAt: Date?
    @ObservationIgnored private var fetching = false
    /// Called after fresh prices land, so the menu bar redraws right away instead of on the next tick.
    @ObservationIgnored var onPrices: (() -> Void)?

    var watchedIDs: [String] { Prefs.string(Prefs.watchedMarkets).split(separator: ",").map(String.init) }
    var watched: [Market] { watchedIDs.compactMap { markets[$0] } }

    func dexTitle(_ dex: String) -> String {
        dex.isEmpty ? "Hyperliquid" : (dexes.first { $0.id == dex }?.title ?? dex)
    }

    /// Prices of the watched markets, at most every `maxAge` seconds.
    func refreshWatched(maxAge: TimeInterval = 10) {
        let ids = Set(watchedIDs).union(PriceAlerts.shared.markets).union(PositionStore.shared.coins)
        guard !fetching, !ids.isEmpty else { return }
        if let pricesAt, Date().timeIntervalSince(pricesAt) < maxAge { return }
        let needed = Set(ids.map { $0.contains(":") ? String($0.split(separator: ":")[0]) : "" })
        fetching = true
        Task {
            let ok = await load(dexes: Array(needed))
            failed = !ok
            if ok { PriceAlerts.shared.check(markets); onPrices?() }
            // A failed fetch is retried on the next tick instead of waiting out maxAge.
            pricesAt = ok ? Date() : nil
            fetching = false
        }
    }

    @ObservationIgnored private var cryptoAt: Date?

    /// Main-dex prices (BTC, ETH, SOL…) for the calculator's crypto conversions, at most once a minute.
    func refreshCrypto() {
        if let cryptoAt, Date().timeIntervalSince(cryptoAt) < 60 { return }
        cryptoAt = Date()
        Task { _ = await load(dexes: [""]) }
    }

    /// Tries again right away (the "Try again" row).
    func retry() {
        pricesAt = nil
        failed = false
        refreshWatched(maxAge: 0)
    }

    /// Every market on every dex, for choosing in Settings. At most hourly.
    func refreshCatalog() {
        guard !loadingCatalog else { return }
        if let catalogAt, Date().timeIntervalSince(catalogAt) < 3600, !markets.isEmpty { return }
        loadingCatalog = true
        Task {
            if let list = await Self.fetchDexes() { dexes = list }
            let ok = await load(dexes: dexes.isEmpty ? [""] : dexes.map(\.id))
            failed = !ok
            catalogAt = ok ? Date() : nil
            loadingCatalog = false
        }
    }

    /// True when at least one dex answered.
    @discardableResult
    private func load(dexes names: [String]) async -> Bool {
        var answered = false
        await withTaskGroup(of: [Market]?.self) { group in
            for dex in names { group.addTask { await Self.fetchMarkets(dex: dex) } }
            for await list in group {
                guard let list else { continue }
                answered = true
                for market in list { markets[market.id] = market }
            }
        }
        return answered
    }

    // MARK: API

    nonisolated private static let endpoint = URL(string: "https://api.hyperliquid.xyz/info")!

    nonisolated static func post(_ body: [String: Any]) async -> Any? {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// `[null, {"name": "xyz", "fullName": "XYZ"}, …]`: null is the main dex.
    nonisolated static func fetchDexes() async -> [MarketDex]? {
        guard let list = await post(["type": "perpDexs"]) as? [Any] else { return nil }
        return list.map { entry in
            guard let dex = entry as? [String: Any], let name = dex["name"] as? String else {
                return MarketDex(id: "", title: "Hyperliquid")
            }
            return MarketDex(id: name, title: dex["fullName"] as? String ?? name)
        }
    }

    /// `[{"universe": [{"name": "BTC", "isDelisted": …}]}, [{"markPx": "60104.0", "prevDayPx": …, "dayNtlVlm": …}]]`.
    private static func fetchMarkets(dex: String) async -> [Market]? {
        guard let reply = await post(["type": "metaAndAssetCtxs", "dex": dex]) else { return nil }
        return markets(from: reply, dex: dex)
    }

    nonisolated static func markets(from reply: Any, dex: String) -> [Market]? {
        guard let reply = reply as? [Any], reply.count == 2,
              let universe = (reply[0] as? [String: Any])?["universe"] as? [[String: Any]],
              let contexts = reply[1] as? [[String: Any]] else { return nil }
        return zip(universe, contexts).compactMap { asset, context in
            guard asset["isDelisted"] as? Bool != true, let name = asset["name"] as? String,
                  let price = number(context["markPx"]) ?? number(context["midPx"]), price > 0 else { return nil }
            return Market(id: name, dex: dex, price: price, prevDayPrice: number(context["prevDayPx"]),
                          volume: number(context["dayNtlVlm"]) ?? 0, funding: number(context["funding"]))
        }
    }

    nonisolated static func number(_ value: Any?) -> Double? {
        switch value {
        case let text as String: Double(text)
        case let number as NSNumber: number.doubleValue
        default: nil
        }
    }
}
