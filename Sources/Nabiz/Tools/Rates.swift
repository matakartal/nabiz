// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import Foundation
import Observation

/// Euro-based daily reference rates from the European Central Bank, via frankfurter.dev (free, no key).
/// Only this request leaves the Mac; it carries no user data. The last table is cached for offline use.
@MainActor
@Observable
final class RateStore {
    static let shared = RateStore()

    struct Table: Codable {
        var date: String
        /// Units of each currency per 1 EUR.
        var rates: [String: Double]
        /// The previous business day, for the daily change.
        var previous: [String: Double]?
    }

    /// The timeseries endpoint: `{"rates": {"2026-11-24": {...}, "2026-11-25": {...}}}`.
    private struct Series: Decodable {
        var rates: [String: [String: Double]]
    }

    private(set) var table: Table?
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var loading = false
    /// The last fetch failed and there is no cached table to fall back on.
    private(set) var failed = false
    @ObservationIgnored var onChange: (() -> Void)?

    private static let cacheKey = "rateCache"
    /// The last week, so the daily change survives weekends and holidays.
    private static var url: URL {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let day = start.formatted(.iso8601.year().month().day())
        return URL(string: "https://api.frankfurter.dev/v1/\(day)..")!
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey) {
            table = try? JSONDecoder().decode(Table.self, from: data)
        }
    }

    /// Codes that can be converted, EUR included.
    var codes: [String] {
        guard let rates = table?.rates else { return ["EUR", "GBP", "JPY", "TRY", "USD"] }
        return (Array(rates.keys) + ["EUR"]).sorted()
    }

    func refreshIfNeeded() {
        guard !loading, fetchedAt.map({ Date().timeIntervalSince($0) > 3600 }) ?? true else { return }
        loading = true
        Task {
            defer { loading = false }
            guard let (data, response) = try? await URLSession.shared.data(from: Self.url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let series = try? JSONDecoder().decode(Series.self, from: data),
                  let latestDay = series.rates.keys.max(), let latest = series.rates[latestDay]
            else {
                failed = table == nil
                return
            }
            failed = false
            let previousDay = series.rates.keys.filter { $0 < latestDay }.max()
            let fresh = Table(date: latestDay, rates: latest, previous: previousDay.flatMap { series.rates[$0] })
            table = fresh
            fetchedAt = Date()
            UserDefaults.standard.set(try? JSONEncoder().encode(fresh), forKey: Self.cacheKey)
            onChange?()
        }
    }

    func rate(_ code: String) -> Double? { code == "EUR" ? 1 : table?.rates[code] }

    /// How much 1 `code` in `base` moved since the previous business day: 0.004 = +0.4%.
    func change(_ code: String, in base: String) -> Double? {
        guard let previous = table?.previous, let now = convert(1, from: code, to: base) else { return nil }
        let a = code == "EUR" ? 1 : previous[code], b = base == "EUR" ? 1 : previous[base]
        guard let a, let b, a > 0, b > 0 else { return nil }
        return now / (b / a) - 1
    }

    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let a = rate(from), let b = rate(to), a > 0 else { return nil }
        return amount / a * b
    }
}
