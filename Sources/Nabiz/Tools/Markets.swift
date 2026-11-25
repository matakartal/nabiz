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
    @ObservationIgnored private var pricesAt: Date?
    @ObservationIgnored private var catalogAt: Date?
    @ObservationIgnored private var fetching = false

    var watchedIDs: [String] { Prefs.string(Prefs.watchedMarkets).split(separator: ",").map(String.init) }
    var watched: [Market] { watchedIDs.compactMap { markets[$0] } }

    func dexTitle(_ dex: String) -> String {
        dex.isEmpty ? "Hyperliquid" : (dexes.first { $0.id == dex }?.title ?? dex)
    }

    /// Prices of the watched markets, at most every `maxAge` seconds.
    func refreshWatched(maxAge: TimeInterval = 10) {
        guard !fetching, !watchedIDs.isEmpty else { return }
        if let pricesAt, Date().timeIntervalSince(pricesAt) < maxAge { return }
        let needed = Set(watchedIDs.map { $0.contains(":") ? String($0.split(separator: ":")[0]) : "" })
        fetching = true
        Task {
            await load(dexes: Array(needed))
            pricesAt = Date()
            fetching = false
        }
    }

    /// Every market on every dex, for choosing in Settings. At most hourly.
    func refreshCatalog() {
        guard !loadingCatalog else { return }
        if let catalogAt, Date().timeIntervalSince(catalogAt) < 3600, !markets.isEmpty { return }
        loadingCatalog = true
        Task {
            if let list = await Self.fetchDexes() { dexes = list }
            await load(dexes: dexes.isEmpty ? [""] : dexes.map(\.id))
            catalogAt = Date()
            loadingCatalog = false
        }
    }

    private func load(dexes names: [String]) async {
        await withTaskGroup(of: [Market]?.self) { group in
            for dex in names { group.addTask { await Self.fetchMarkets(dex: dex) } }
            for await list in group {
                for market in list ?? [] { markets[market.id] = market }
            }
        }
    }

    // MARK: API

    private static let endpoint = URL(string: "https://api.hyperliquid.xyz/info")!

    private static func post(_ body: [String: Any]) async -> Any? {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// `[null, {"name": "xyz", "fullName": "XYZ"}, …]`: null is the main dex.
    private static func fetchDexes() async -> [MarketDex]? {
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
        guard let reply = await post(["type": "metaAndAssetCtxs", "dex": dex]) as? [Any], reply.count == 2,
              let universe = (reply[0] as? [String: Any])?["universe"] as? [[String: Any]],
              let contexts = reply[1] as? [[String: Any]] else { return nil }
        return zip(universe, contexts).compactMap { asset, context in
            guard asset["isDelisted"] as? Bool != true, let name = asset["name"] as? String,
                  let price = number(context["markPx"]) ?? number(context["midPx"]), price > 0 else { return nil }
            return Market(id: name, dex: dex, price: price, prevDayPrice: number(context["prevDayPx"]),
                          volume: number(context["dayNtlVlm"]) ?? 0)
        }
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let text as String: Double(text)
        case let number as NSNumber: number.doubleValue
        default: nil
        }
    }
}
