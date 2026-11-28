// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

/// Hyperliquid positions: reading `clearinghouseState`, the margin and liquidation numbers, the warning's
/// hysteresis, the closed header's summary and the wallet address check.
@MainActor
@Suite("Positions")
struct PositionsTests {
    init() {
        Prefs.registerDefaults()
        UserDefaults.standard.set("en", forKey: Prefs.language)
    }

    /// The main dex. The envelope (`marginSummary`, `withdrawable`, `time`…) is a real answer for the HLP vault
    /// (0xdfc24b…f303), trimmed; that address holds no positions itself, so the entries follow the shape in
    /// Hyperliquid's API documentation.
    private let mainDex = #"""
    {"marginSummary":{"accountValue":"11690274.6089290008","totalNtlPos":"0.0","totalRawUsd":"11690274.6089290008","totalMarginUsed":"477.867397"},
     "crossMarginSummary":{"accountValue":"11689796.7415319998","totalNtlPos":"0.0","totalRawUsd":"11689796.7415319998","totalMarginUsed":"0.0"},
     "crossMaintenanceMarginUsed":"0.0","withdrawable":"11689796.7415319998","time":1795889019167,
     "assetPositions":[
      {"type":"oneWay","position":{"coin":"BTC","cumFunding":{"allTime":"514.085417","sinceChange":"0.0","sinceOpen":"12.5"},
       "entryPx":"58200.0","leverage":{"type":"cross","value":20},"liquidationPx":"52100.0","marginUsed":"1485.35","maxLeverage":40,
       "positionValue":"29707.0","returnOnEquity":"0.5206","szi":"0.5","unrealizedPnl":"607.0"}},
      {"type":"oneWay","position":{"coin":"ETH","cumFunding":{"allTime":"-20.1","sinceChange":"0.0","sinceOpen":"-3.2"},
       "entryPx":"1700.0","leverage":{"rawUsd":"17105.0","type":"isolated","value":10},"liquidationPx":"1790.5","marginUsed":"1645.0",
       "maxLeverage":25,"positionValue":"16452.3","returnOnEquity":"0.3304","szi":"-10.0","unrealizedPnl":"547.7"}},
      {"type":"oneWay","position":{"coin":"SOL","cumFunding":{"allTime":"0.0","sinceChange":"0.0","sinceOpen":"0.0"},
       "entryPx":"140.0","leverage":{"type":"cross","value":3},"liquidationPx":null,"marginUsed":"1400.0","maxLeverage":20,
       "positionValue":"4200.0","returnOnEquity":"0.0","szi":"30.0","unrealizedPnl":"0.0"}}
     ]}
    """#

    /// A HIP-3 dex (`"dex": "xyz"`): one coin with its prefix, one without, one without a liquidation price at all.
    private let xyzDex = #"""
    {"marginSummary":{"accountValue":"2100.0","totalNtlPos":"16695.0","totalRawUsd":"-14595.0","totalMarginUsed":"1989.5"},
     "crossMarginSummary":{"accountValue":"0.0","totalNtlPos":"0.0","totalRawUsd":"0.0","totalMarginUsed":"0.0"},
     "crossMaintenanceMarginUsed":"0.0","withdrawable":"110.5","time":1795889032327,
     "assetPositions":[
      {"type":"oneWay","position":{"coin":"xyz:TSLA","cumFunding":{"allTime":"1.0","sinceChange":"0.0","sinceOpen":"1.0"},
       "entryPx":"401.2","leverage":{"rawUsd":"-14000.0","type":"isolated","value":10},"liquidationPx":"387.0","marginUsed":"1591.6",
       "maxLeverage":20,"positionValue":"15916.0","returnOnEquity":"-0.0807","szi":"40.0","unrealizedPnl":"-132.0"}},
      {"type":"oneWay","position":{"coin":"NVDA","entryPx":"190.0","leverage":{"type":"isolated","value":5},"marginUsed":"397.9",
       "positionValue":"779.0","returnOnEquity":"0.02","szi":"-4.1","unrealizedPnl":"0.0"}}
     ]}
    """#

    /// A real answer for a dex the wallet doesn't use.
    private let emptyDex = #"""
    {"marginSummary":{"accountValue":"0.0","totalNtlPos":"0.0","totalRawUsd":"0.0","totalMarginUsed":"0.0"},
     "crossMarginSummary":{"accountValue":"0.0","totalNtlPos":"0.0","totalRawUsd":"0.0","totalMarginUsed":"0.0"},
     "crossMaintenanceMarginUsed":"0.0","withdrawable":"0.0","assetPositions":[],"time":1795889032327}
    """#

    private func dex(_ text: String, _ name: String) throws -> DexAccount {
        let json = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require(DexAccount(json: json, dex: name))
    }

    private func position(size: Double, mark: Double, liquidation: Double?, pnl: Double = 0) -> PerpPosition {
        PerpPosition(coin: "BTC", dex: "", size: size, entryPrice: mark, positionValue: abs(size) * mark, unrealizedPnl: pnl,
                     returnOnEquity: 0, liquidationPrice: liquidation, leverage: 5, isolated: false, marginUsed: 0,
                     fundingSinceOpen: 0)
    }

    @Test func readsTheClearinghouseState() throws {
        let main = try dex(mainDex, "")
        #expect(abs(main.accountValue - 11_690_274.608929) < 0.001)
        #expect(main.marginUsed == 477.867397)
        #expect(abs(main.withdrawable - 11_689_796.741532) < 0.001)
        #expect(main.positions.map(\.coin) == ["BTC", "ETH", "SOL"])
        let btc = main.positions[0], eth = main.positions[1], sol = main.positions[2]
        #expect(btc.isLong && btc.size == 0.5 && btc.leverage == 20 && !btc.isolated)
        #expect(btc.entryPrice == 58_200 && btc.liquidationPrice == 52_100 && btc.fundingSinceOpen == 12.5)
        #expect(btc.markPrice == 59_414)
        #expect(!eth.isLong && eth.size == -10 && eth.isolated && eth.leverage == 10 && eth.fundingSinceOpen == -3.2)
        #expect(eth.returnOnEquity == 0.3304 && eth.unrealizedPnl == 547.7)
        // null liquidation price: nothing to warn about.
        #expect(sol.liquidationPrice == nil && sol.liquidationDistance() == nil && sol.risk == .safe)
    }

    @Test func hip3CoinsKeepTheirDex() throws {
        let xyz = try dex(xyzDex, "xyz")
        #expect(xyz.positions.map(\.coin) == ["xyz:TSLA", "xyz:NVDA"])
        #expect(xyz.positions.map(\.name) == ["TSLA", "NVDA"])
        #expect(xyz.positions[0].tradeURL?.absoluteString == "https://app.hyperliquid.xyz/trade/xyz:TSLA")
        #expect(xyz.positions[1].liquidationPrice == nil && xyz.positions[1].fundingSinceOpen == 0)
        #expect(!xyz.isEmpty)
    }

    @Test func anEmptyOrBrokenAnswer() throws {
        let empty = try dex(emptyDex, "flx")
        #expect(empty.isEmpty && empty.positions.isEmpty)
        #expect(DexAccount(json: ["error": "bad user"], dex: "") == nil)
        #expect(DexAccount(json: [Any](), dex: "") == nil)
        // A position without a size (or a closed one at 0) is left out, not shown as an empty row.
        let zero: [String: Any] = ["marginSummary": ["accountValue": "5.0"], "assetPositions": [["position": ["coin": "BTC", "szi": "0.0"]]]]
        #expect(try #require(DexAccount(json: zero, dex: "")).positions.isEmpty)
    }

    @Test func marginIsSummedOverDexes() throws {
        let account = HyperliquidAccount(dexes: [try dex(mainDex, ""), try dex(xyzDex, "xyz"), try dex(emptyDex, "flx")])
        let ratio = try #require(account.marginRatio)
        #expect(abs(ratio - (477.867397 + 1989.5) / (11_690_274.608929 + 2100)) < 1e-12)
        #expect(account.positions.map(\.coin) == ["BTC", "ETH", "xyz:TSLA", "SOL", "xyz:NVDA"])
        #expect(abs(account.unrealizedPnl - (607 + 547.7 - 132)) < 1e-9)

        let small = HyperliquidAccount(dexes: [
            DexAccount(dex: "", accountValue: 800, marginUsed: 200, withdrawable: 600, positions: []),
            DexAccount(dex: "xyz", accountValue: 200, marginUsed: 140, withdrawable: 60, positions: []),
        ])
        #expect(small.marginRatio == 0.34)
        #expect(PositionText.accountSubtitle(small) == "margin 34%")
        UserDefaults.standard.set("tr", forKey: Prefs.language)
        defer { UserDefaults.standard.set("en", forKey: Prefs.language) }
        #expect(PositionText.accountSubtitle(small) == "marj %34")
        // Nothing in the account: no ratio, no subtitle.
        #expect(HyperliquidAccount(dexes: []).marginRatio == nil)
    }

    @Test func liquidationDistance() {
        #expect(position(size: 1, mark: 100, liquidation: 90).liquidationDistance() == 0.1)
        #expect(abs((position(size: -1, mark: 100, liquidation: 103).liquidationDistance() ?? 0) - 0.03) < 1e-12)
        // Past the line it is 0, never negative.
        #expect(position(size: 1, mark: 100, liquidation: 104).liquidationDistance() == 0)
        #expect(position(size: 1, mark: 100, liquidation: nil).liquidationDistance() == nil)
        #expect(position(size: 1, mark: 100, liquidation: 88).risk == .safe)
        #expect(position(size: 1, mark: 100, liquidation: 90.5).risk == .near)
        #expect(position(size: -1, mark: 100, liquidation: 102.5).risk == .close)
    }

    @Test func liquidationWarningsHaveHysteresis() {
        var watch = LiquidationWatch()
        func step(_ distance: Double) -> [LiquidationRisk] { watch.update(["BTC": distance]).map(\.risk) }
        #expect(step(0.20) == [])
        #expect(step(0.09) == [.near])
        #expect(step(0.08) == [])
        // Back between 10% and 15%: not armed again yet.
        #expect(step(0.12) == [])
        #expect(step(0.09) == [])
        #expect(step(0.02) == [.close])
        #expect(step(0.05) == [])
        #expect(step(0.025) == [])
        // Past 15% it arms again.
        #expect(step(0.16) == [])
        #expect(step(0.09) == [.near])
        // Straight from safe to very close: one warning, the closer one.
        var jump = LiquidationWatch()
        #expect(jump.update(["ETH": 0.30]).isEmpty)
        #expect(jump.update(["ETH": 0.01]).map(\.risk) == [.close])
        // A closed position starts over when it opens again.
        #expect(jump.update([:]).isEmpty && jump.levels.isEmpty)
        #expect(jump.update(["ETH": 0.05]).map(\.risk) == [.near])
    }

    @Test func theClosedHeaderSummary() throws {
        #expect(PositionSummary.closed(nil).text == "")
        let near = HyperliquidAccount(dexes: [try dex(mainDex, "")])
        #expect(PositionSummary.closed(near) == ("Near liquidation", .warning))
        let up = HyperliquidAccount(dexes: [DexAccount(dex: "", accountValue: 1000, marginUsed: 100, withdrawable: 900,
                                                       positions: [position(size: 1, mark: 100, liquidation: 50, pnl: 476)])])
        #expect(PositionSummary.closed(up) == ("+$476.00", .up))
        let down = HyperliquidAccount(dexes: [DexAccount(dex: "", accountValue: 1000, marginUsed: 100, withdrawable: 900,
                                                         positions: [position(size: -1, mark: 100, liquidation: nil, pnl: -1376.4)])])
        #expect(PositionSummary.closed(down) == ("−$1,376", .down))
        let none = HyperliquidAccount(dexes: [DexAccount(dex: "", accountValue: 250.5, marginUsed: 0, withdrawable: 250.5, positions: [])])
        #expect(PositionSummary.closed(none) == ("$250.50", .muted))
    }

    @Test func rowWordsInBothLanguages() throws {
        let btc = try dex(mainDex, "").positions[0]
        #expect(PositionText.subtitle(btc) == "Long 20x · 0.5 · liq 52,100")
        #expect(Format.dollars(12_345.6) == "$12,346")
        #expect(PositionText.notification(btc, risk: .near).title == "BTC is 12.3% from liquidation")
        UserDefaults.standard.set("tr", forKey: Prefs.language)
        defer { UserDefaults.standard.set("en", forKey: Prefs.language) }
        #expect(PositionText.subtitle(btc) == "Long 20x · 0,5 · liq 52.100")
        #expect(Format.dollars(12_345.6) == "12.346 $")
        #expect(Format.dollars(-3.2, signed: true) == "−3,20 $")
        let eth = try dex(mainDex, "").positions[1]
        #expect(PositionText.subtitle(eth) == "Short 10x · 10 · liq 1.790,5")
    }

    @Test func fundingComesWithTheMarket() throws {
        // A real `metaAndAssetCtxs` answer, trimmed to BTC.
        let reply = try JSONSerialization.jsonObject(with: Data(#"""
        [{"universe":[{"szDecimals":5,"name":"BTC","maxLeverage":40,"marginTableId":56}]},
         [{"funding":"0.0000045628","openInterest":"34765.686","prevDayPx":"59929.0","dayNtlVlm":"1369990288.2108709812",
           "premium":"-0.00043746","oraclePx":"59434.0","markPx":"59407.0","midPx":"59407.5","impactPxs":["59407.0","59408.0"]}]]
        """#.utf8))
        let market = try #require(MarketStore.markets(from: reply, dex: "")?.first)
        #expect(market.id == "BTC" && market.price == 59_407 && market.funding == 0.0000045628)
        // Positive funding: a long pays, a short earns.
        let long = position(size: 2, mark: 50_000, liquidation: nil)
        #expect(abs((long.fundingPerHour(rate: 0.00001) ?? 0) - 1) < 1e-9)
        #expect((position(size: -2, mark: 50_000, liquidation: nil).fundingPerHour(rate: 0.00001) ?? 0) < 0)
    }

    @Test func addressCheck() {
        let address = "0xdfc24b077bc1425ad1dea75bcb6f8158e10df303"
        #expect(HyperliquidAddress.normalized(address) == address)
        #expect(HyperliquidAddress.normalized("  0xDFC24B077BC1425AD1DEA75BCB6F8158E10DF303\n") == address)
        #expect(!HyperliquidAddress.isValid(""))
        #expect(!HyperliquidAddress.isValid(String(address.dropFirst(2))))
        #expect(!HyperliquidAddress.isValid(String(address.dropLast())))
        #expect(!HyperliquidAddress.isValid(address + "0"))
        #expect(!HyperliquidAddress.isValid("0xdfc24b077bc1425ad1dea75bcb6f8158e10df30g"))
        #expect(!HyperliquidAddress.isValid("0x dfc24b077bc1425ad1dea75bcb6f8158e10df30"))
    }

    @Test func positionsComeRightAfterMarkets() {
        let saved = UserDefaults.standard.string(forKey: Prefs.sectionOrder)
        defer { UserDefaults.standard.set(saved, forKey: Prefs.sectionOrder) }
        let all = PanelSection.allCases
        #expect(all.firstIndex(of: .positions) == all.firstIndex(of: .markets).map { $0 + 1 })
        // An order saved before positions existed, with markets moved to the top.
        UserDefaults.standard.set("markets,system,advice,simulators,ports,projects,docker,displays,ai,calendar,weather,memory,cpu,currency,tools",
                                  forKey: Prefs.sectionOrder)
        let order = PanelSection.ordered
        #expect(order.prefix(2) == [.markets, .positions])
        #expect(order.count == all.count)
    }
}
