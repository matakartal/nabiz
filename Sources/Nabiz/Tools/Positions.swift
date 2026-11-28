// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Observation

/// One open perpetual position on Hyperliquid, as `clearinghouseState` reports it.
struct PerpPosition: Identifiable, Equatable, Sendable {
    /// Hyperliquid's coin name, with the dex prefix for HIP-3 markets ("BTC", "xyz:TSLA").
    let coin: String
    /// "" for the main dex.
    let dex: String
    /// Size in coins: positive for a long, negative for a short.
    let size: Double
    let entryPrice: Double?
    /// Size × mark price, in dollars.
    let positionValue: Double
    let unrealizedPnl: Double
    let returnOnEquity: Double
    /// Missing when the account can't be liquidated by this position (enough margin elsewhere).
    let liquidationPrice: Double?
    let leverage: Double
    let isolated: Bool
    let marginUsed: Double
    /// Hyperliquid's `cumFunding.sinceOpen`: positive means the position has paid funding, negative that it earned it.
    let fundingSinceOpen: Double

    var id: String { coin }
    var name: String { coin.split(separator: ":").last.map(String.init) ?? coin }
    var isLong: Bool { size > 0 }

    /// The mark price Hyperliquid worked the position's value and profit out at.
    var markPrice: Double? { size != 0 && positionValue > 0 ? positionValue / abs(size) : nil }

    var tradeURL: URL? { Hyperliquid.url("trade/\(coin)") }

    /// How far the price can still move against the position before it is liquidated, as a fraction of the mark
    /// (0.08 = 8%). 0 once the mark is at or past the line.
    func liquidationDistance(mark: Double? = nil) -> Double? {
        guard let liquidationPrice, liquidationPrice > 0, let mark = mark ?? markPrice, mark > 0 else { return nil }
        let gap = isLong ? mark - liquidationPrice : liquidationPrice - mark
        return max(gap / mark, 0)
    }

    var risk: LiquidationRisk { LiquidationRisk(distance: liquidationDistance()) }

    /// Funding for one hour at Hyperliquid's hourly `rate`: positive means this position pays, negative that it earns.
    func fundingPerHour(rate: Double) -> Double? { markPrice.map { size * $0 * rate } }
}

/// How close a position is to its liquidation price.
enum LiquidationRisk: Int, Comparable, Sendable {
    case safe, near, close

    /// Within 10% is near, within 3% is close; a warning only arms again once the price is back more than 15% away.
    static let nearLine = 0.10
    static let closeLine = 0.03
    static let rearmLine = 0.15

    init(distance: Double?) {
        guard let distance else { self = .safe; return }
        self = distance < Self.closeLine ? .close : distance < Self.nearLine ? .near : .safe
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One dex's clearinghouse: the main dex, or a HIP-3 dex with its own margin.
struct DexAccount: Equatable, Sendable {
    let dex: String
    let accountValue: Double
    let marginUsed: Double
    let withdrawable: Double
    let positions: [PerpPosition]

    /// Nothing on this dex: it is only looked at again in the occasional full scan.
    var isEmpty: Bool { positions.isEmpty && abs(accountValue) < 0.005 }

    /// `{"marginSummary": {"accountValue": "…", "totalMarginUsed": "…"}, "withdrawable": "…",
    /// "assetPositions": [{"type": "oneWay", "position": {"coin": "BTC", "szi": "-0.25", …}}]}`.
    init?(json: Any, dex: String) {
        guard let root = json as? [String: Any], let summary = root["marginSummary"] as? [String: Any],
              let value = MarketStore.number(summary["accountValue"]) else { return nil }
        self.dex = dex
        accountValue = value
        marginUsed = MarketStore.number(summary["totalMarginUsed"]) ?? 0
        withdrawable = MarketStore.number(root["withdrawable"]) ?? 0
        let entries = root["assetPositions"] as? [[String: Any]] ?? []
        positions = entries.compactMap { Self.position($0["position"] as? [String: Any], dex: dex) }
    }

    init(dex: String, accountValue: Double, marginUsed: Double, withdrawable: Double, positions: [PerpPosition]) {
        self.dex = dex
        self.accountValue = accountValue
        self.marginUsed = marginUsed
        self.withdrawable = withdrawable
        self.positions = positions
    }

    private static func position(_ entry: [String: Any]?, dex: String) -> PerpPosition? {
        guard let entry, var coin = entry["coin"] as? String, !coin.isEmpty,
              let size = MarketStore.number(entry["szi"]), size != 0 else { return nil }
        // Coins on a HIP-3 dex carry its prefix ("xyz:TSLA"), as the dex's market list does; add it if missing.
        if !dex.isEmpty && !coin.contains(":") { coin = "\(dex):\(coin)" }
        let leverage = entry["leverage"] as? [String: Any]
        let funding = entry["cumFunding"] as? [String: Any]
        let liquidation = MarketStore.number(entry["liquidationPx"])
        return PerpPosition(coin: coin, dex: dex, size: size,
                            entryPrice: MarketStore.number(entry["entryPx"]),
                            positionValue: abs(MarketStore.number(entry["positionValue"]) ?? 0),
                            unrealizedPnl: MarketStore.number(entry["unrealizedPnl"]) ?? 0,
                            returnOnEquity: MarketStore.number(entry["returnOnEquity"]) ?? 0,
                            liquidationPrice: liquidation.flatMap { $0 > 0 ? $0 : nil },
                            leverage: MarketStore.number(leverage?["value"]) ?? 1,
                            isolated: leverage?["type"] as? String == "isolated",
                            marginUsed: MarketStore.number(entry["marginUsed"]) ?? 0,
                            fundingSinceOpen: MarketStore.number(funding?["sinceOpen"]) ?? 0)
    }
}

/// The wallet across every dex it uses.
struct HyperliquidAccount: Equatable, Sendable {
    var dexes: [DexAccount]

    var accountValue: Double { dexes.reduce(0) { $0 + $1.accountValue } }
    var marginUsed: Double { dexes.reduce(0) { $0 + $1.marginUsed } }
    var withdrawable: Double { dexes.reduce(0) { $0 + $1.withdrawable } }
    /// Margin in use as a share of what the account is worth, over every dex.
    var marginRatio: Double? { accountValue > 0 ? marginUsed / accountValue : nil }
    /// Biggest first.
    var positions: [PerpPosition] { dexes.flatMap(\.positions).sorted { $0.positionValue > $1.positionValue } }
    var unrealizedPnl: Double { dexes.reduce(0) { $0 + $1.positions.reduce(0) { $0 + $1.unrealizedPnl } } }
    var nearLiquidation: Bool { dexes.contains { $0.positions.contains { $0.risk >= .near } } }
}

/// A wallet address as Hyperliquid takes it: "0x" and 40 hex digits.
enum HyperliquidAddress {
    /// The address in lower case, or nil when it isn't one. Spaces around it are ignored.
    static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count == 42, trimmed.hasPrefix("0x"),
              trimmed.dropFirst(2).allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return trimmed
    }

    static func isValid(_ text: String) -> Bool { normalized(text) != nil }
}

/// Warns once when a position comes within 10% of liquidation and once more within 3%; it arms again only after the
/// price is back more than 15% away, so a price wobbling around a line doesn't send a stream of notifications.
struct LiquidationWatch {
    private(set) var levels: [String: LiquidationRisk] = [:]

    /// Takes every open position's distance to liquidation and returns the ones that just moved into a closer band.
    mutating func update(_ distances: [String: Double]) -> [(coin: String, risk: LiquidationRisk)] {
        var alerts: [(coin: String, risk: LiquidationRisk)] = []
        for (coin, distance) in distances.sorted(by: { $0.key < $1.key }) {
            let warned = levels[coin] ?? .safe
            let now = LiquidationRisk(distance: distance)
            if now > warned {
                levels[coin] = now
                alerts.append((coin, now))
            } else if distance > LiquidationRisk.rearmLine {
                levels[coin] = .safe
            }
        }
        // A closed position (or one that lost its liquidation price) starts over.
        levels = levels.filter { distances[$0.key] != nil }
        return alerts
    }
}

/// Reads the open positions of a public wallet address from Hyperliquid's info API. Read-only: only the address is
/// sent, no key and no signature. The main dex is read every time; HIP-3 dexes the wallet doesn't use are only looked
/// at in a full scan every few minutes.
@MainActor
@Observable
final class PositionStore {
    static let shared = PositionStore()

    private(set) var account: HyperliquidAccount?
    /// The last read got nothing back and there is nothing older to show.
    private(set) var failed = false
    /// Made-up positions for snapshots; nothing is fetched while they show.
    private(set) var isDemo = false
    @ObservationIgnored private var fetching = false
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var failedAt: Date?
    @ObservationIgnored private var fullScanAt: Date?
    @ObservationIgnored private var fetchedFor: String?
    @ObservationIgnored private var dexNames: [String]?
    @ObservationIgnored private var dexesAt: Date?
    @ObservationIgnored private var watch = LiquidationWatch()

    /// The address from Settings, when it is a valid one.
    var address: String? { HyperliquidAddress.normalized(Prefs.string(Prefs.hyperliquidAddress)) }

    /// Coins whose prices and funding MarketStore keeps along with the watched markets.
    var coins: Set<String> { Set(account?.positions.map(\.coin) ?? []) }

    /// Called on every monitor tick: every 10 s while the panel shows the positions; in the background every minute
    /// while there are positions to warn about (every 15 minutes with none, so a new one is noticed).
    func tick(panelOpen: Bool) {
        guard !isDemo else { return }
        guard address != nil else { refresh(); return }
        if panelOpen && Prefs.bool(Prefs.showPositions) {
            refresh(maxAge: 10)
            // Funding rates come with the market prices.
            if !coins.isEmpty { MarketStore.shared.refreshWatched(maxAge: 30) }
        } else if Prefs.bool(Prefs.liquidationAlerts) && Prefs.bool(Prefs.notifications) {
            refresh(maxAge: account.map { $0.positions.isEmpty ? 900 : 60 } ?? 60)
        }
    }

    /// Reads the positions, at most every `maxAge` seconds; every dex is scanned again after `fullScanAge` seconds.
    func refresh(maxAge: TimeInterval = 10, fullScanAge: TimeInterval = 300) {
        guard !isDemo else { return }
        guard let address else {
            // The address was cleared: forget its positions.
            if account != nil { account = nil }
            fetchedFor = nil
            return
        }
        if address != fetchedFor {
            account = nil
            failed = false
            fetchedAt = nil
            failedAt = nil
            fullScanAt = nil
            watch = LiquidationWatch()
            fetchedFor = address
        }
        guard !fetching else { return }
        let now = Date()
        if let fetchedAt, now.timeIntervalSince(fetchedAt) < maxAge { return }
        // After a failure, wait a little before trying again instead of asking on every tick.
        if let failedAt, now.timeIntervalSince(failedAt) < 15 { return }
        let full = account == nil || fullScanAt.map { now.timeIntervalSince($0) >= fullScanAge } ?? true
        fetching = true
        Task {
            let result = await load(address, full: full)
            fetching = false
            // The address changed while this was on its way: drop the answer.
            guard address == self.address, address == fetchedFor else { return }
            if let result {
                account = result
                failed = false
                failedAt = nil
                fetchedAt = Date()
                if full { fullScanAt = Date() }
                checkLiquidation(result)
            } else {
                failedAt = Date()
                failed = account == nil
            }
        }
    }

    /// The "Try again" row.
    func retry() {
        failedAt = nil
        failed = false
        refresh(maxAge: 0)
    }

    func showDemo() {
        isDemo = true
        account = Self.demo
    }

    /// Nil when the main dex didn't answer. A HIP-3 dex that didn't answer keeps what it had.
    private func load(_ address: String, full: Bool) async -> HyperliquidAccount? {
        var names = [""]
        if full {
            if dexNames == nil || dexesAt.map({ Date().timeIntervalSince($0) > 3600 }) ?? true,
               let list = await MarketStore.fetchDexes() {
                dexNames = list.map(\.id).filter { !$0.isEmpty }
                dexesAt = Date()
            }
            names += dexNames ?? []
        } else {
            names += account?.dexes.filter { !$0.dex.isEmpty && !$0.isEmpty }.map(\.dex) ?? []
        }
        var fresh: [String: DexAccount] = [:]
        await withTaskGroup(of: (String, DexAccount?).self) { group in
            for dex in names {
                group.addTask {
                    var body: [String: Any] = ["type": "clearinghouseState", "user": address]
                    if !dex.isEmpty { body["dex"] = dex }
                    return (dex, await MarketStore.post(body).flatMap { DexAccount(json: $0, dex: dex) })
                }
            }
            for await (dex, account) in group { if let account { fresh[dex] = account } }
        }
        guard let main = fresh[""] else { return nil }
        let old = account?.dexes ?? []
        let others = names.dropFirst().compactMap { dex in fresh[dex] ?? old.first { $0.dex == dex } }.filter { !$0.isEmpty }
        return HyperliquidAccount(dexes: [main] + others)
    }

    private func checkLiquidation(_ account: HyperliquidAccount) {
        guard Prefs.bool(Prefs.liquidationAlerts) && Prefs.bool(Prefs.notifications) else {
            // Off: forget what was warned about, so turning it on warns about a position that is already close.
            watch = LiquidationWatch()
            return
        }
        let positions = account.positions
        var distances: [String: Double] = [:]
        for position in positions { distances[position.coin] = position.liquidationDistance() }
        for alert in watch.update(distances) {
            guard let position = positions.first(where: { $0.coin == alert.coin }) else { continue }
            let text = PositionText.notification(position, risk: alert.risk)
            Notifier.shared.post(id: "liquidation-\(position.coin)", title: text.title, body: text.body)
        }
    }

    /// Positions for `--snapshot … --positions`: one safe, one near and one close to liquidation, one with none.
    static let demo = HyperliquidAccount(dexes: [
        DexAccount(dex: "", accountValue: 16_320.40, marginUsed: 5_180.20, withdrawable: 9_870.15, positions: [
            PerpPosition(coin: "BTC", dex: "", size: 0.25, entryPrice: 58_200, positionValue: 15_026, unrealizedPnl: 476,
                         returnOnEquity: 0.158, liquidationPrice: 47_900, leverage: 5, isolated: false, marginUsed: 3_005.2,
                         fundingSinceOpen: 4.12),
            PerpPosition(coin: "ETH", dex: "", size: -4, entryPrice: 2_310, positionValue: 9_616, unrealizedPnl: -376,
                         returnOnEquity: -0.391, liquidationPrice: 2_560, leverage: 10, isolated: false, marginUsed: 961.6,
                         fundingSinceOpen: -1.85),
            PerpPosition(coin: "SOL", dex: "", size: 30, entryPrice: 141.2, positionValue: 4_237.5, unrealizedPnl: 1.5,
                         returnOnEquity: 0.001, liquidationPrice: nil, leverage: 3, isolated: false, marginUsed: 1_412.5,
                         fundingSinceOpen: 0.3),
        ]),
        DexAccount(dex: "xyz", accountValue: 2_100, marginUsed: 1_530.8, withdrawable: 569.2, positions: [
            PerpPosition(coin: "xyz:TSLA", dex: "xyz", size: 40, entryPrice: 401.2, positionValue: 15_307.6, unrealizedPnl: -740.4,
                         returnOnEquity: -0.484, liquidationPrice: 372.5, leverage: 10, isolated: true, marginUsed: 1_530.8,
                         fundingSinceOpen: 2.05),
        ]),
    ])
}

/// The words the panel and notifications use for an account and its positions.
enum PositionText {
    /// "Long 5x · 0,25 · liq 52.100".
    static func subtitle(_ position: PerpPosition) -> String {
        // Turkish traders say long, short and liq too.
        var parts = ["\(position.isLong ? "Long" : "Short") \(leverage(position.leverage))", Format.number(abs(position.size), maxDigits: 5)]
        if let liquidation = position.liquidationPrice { parts.append("liq \(Format.price(liquidation))") }
        return parts.joined(separator: " · ")
    }

    /// "margin 34%"; empty for an account worth nothing.
    static func accountSubtitle(_ account: HyperliquidAccount) -> String {
        guard let ratio = account.marginRatio else { return "" }
        return L("marj \(Format.percent(ratio))", "margin \(Format.percent(ratio))")
    }

    /// Everything that didn't fit on the row, for its tooltip.
    static func details(_ position: PerpPosition, fundingRate: Double?) -> String {
        var parts: [String] = []
        if let entry = position.entryPrice { parts.append(L("Giriş \(Format.price(entry))", "Entry \(Format.price(entry))")) }
        if let mark = position.markPrice { parts.append(L("mark fiyatı \(Format.price(mark))", "mark \(Format.price(mark))")) }
        parts.append(L("değer \(Format.dollars(position.positionValue))", "value \(Format.dollars(position.positionValue))"))
        let margin = Format.dollars(position.marginUsed)
        parts.append(position.isolated ? L("izole marj \(margin)", "isolated margin \(margin)") : L("marj \(margin)", "margin \(margin)"))
        parts.append("ROE \(Format.signedPercent(position.returnOnEquity))")
        if let rate = fundingRate, let hourly = position.fundingPerHour(rate: rate) {
            let amount = Format.dollars(abs(hourly))
            parts.append(hourly >= 0 ? L("fonlama: saatte \(amount) ödüyorsun", "funding: you pay \(amount)/h")
                                     : L("fonlama: saatte \(amount) alıyorsun", "funding: you earn \(amount)/h"))
        }
        let since = Format.dollars(abs(position.fundingSinceOpen))
        parts.append(position.fundingSinceOpen >= 0 ? L("açılıştan beri \(since) fonlama ödendi", "\(since) funding paid since open")
                                                    : L("açılıştan beri \(since) fonlama alındı", "\(since) funding earned since open"))
        if let liquidation = position.liquidationPrice, let distance = position.liquidationDistance() {
            let away = Format.percent(distance, digits: 1)
            parts.append(L("likidasyon \(Format.price(liquidation)) (\(away) uzakta)", "liquidation \(Format.price(liquidation)) (\(away) away)"))
        } else {
            parts.append(L("likidasyon fiyatı yok", "no liquidation price"))
        }
        parts.append(L("Hyperliquid'de açmak için tıkla", "click to open on Hyperliquid"))
        return parts.joined(separator: " · ")
    }

    static func notification(_ position: PerpPosition, risk: LiquidationRisk) -> (title: String, body: String) {
        let away = Format.percent(position.liquidationDistance() ?? 0, digits: 1)
        let title = risk == .close
            ? L("\(position.name) likidasyona çok yakın (\(away))", "\(position.name) is very close to liquidation (\(away))")
            : L("\(position.name) likidasyona \(away) uzakta", "\(position.name) is \(away) from liquidation")
        let mark = position.markPrice.map(Format.price) ?? "–"
        let liquidation = position.liquidationPrice.map(Format.price) ?? "–"
        let body = "\(subtitle(position)) · " + L("mark fiyatı \(mark), likidasyon \(liquidation)", "mark \(mark), liquidation \(liquidation)")
        return (title, body)
    }

    /// "5x", "2.5x".
    static func leverage(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))x" : Format.number(value, maxDigits: 1) + "x"
    }
}

/// What a closed Positions header says: a warning near liquidation, otherwise the open profit or loss.
enum PositionSummary {
    enum Tone: Equatable { case muted, up, down, warning }

    static func closed(_ account: HyperliquidAccount?) -> (text: String, tone: Tone) {
        guard let account else { return ("", .muted) }
        if account.nearLiquidation { return (L("Likidasyona yakın", "Near liquidation"), .warning) }
        if account.positions.isEmpty { return (Format.dollars(account.accountValue), .muted) }
        let pnl = account.unrealizedPnl
        guard abs(pnl) >= 0.005 else { return (Format.dollars(0), .muted) }
        return (Format.dollars(pnl, signed: true), pnl > 0 ? .up : .down)
    }
}

extension Format {
    /// "$12,345" / "12.345 $", with cents under a thousand; `signed` adds a plus to gains ("+$476").
    static func dollars(_ value: Double, signed: Bool = false) -> String {
        let digits = abs(value) >= 1000 ? 0 : 2
        let text = number(abs(value), maxDigits: digits, minDigits: digits)
        let zero = abs(value) < 0.005
        let sign = zero ? "" : value < 0 ? "−" : signed ? "+" : ""
        return Prefs.isTurkish ? sign + text + " $" : sign + "$" + text
    }

    /// "%2,6" / "2.6%": like `percent`, with decimals and without the 0–100% clamp.
    static func percent(_ fraction: Double, digits: Int) -> String {
        let text = number(fraction * 100, maxDigits: digits, minDigits: digits)
        return Prefs.isTurkish ? "%" + text : text + "%"
    }

    /// "+%15,8" / "−39.1%".
    static func signedPercent(_ fraction: Double) -> String {
        let text = percent(abs(fraction), digits: 1)
        return (fraction < 0 ? "−" : "+") + text
    }
}
