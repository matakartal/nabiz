// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Foundation
import Testing
@testable import Nabiz

/// What the menu bar shows for the weather and currency items, from a fixed report and rate table.
@MainActor
@Suite("Menu bar text", .serialized)
struct MenuBarTextTests {
    private let keys = MenuBarItem.allCases.map(\.key) + [Prefs.baseCurrency, Prefs.watchedCurrencies, Prefs.barLabels, Prefs.language]

    private let report = WeatherStore.Report(
        place: .init(name: "Istanbul", detail: "Türkiye", latitude: 41.01, longitude: 28.95), fetched: Date(),
        temperature: 11.4, feelsLike: 9, code: 61, isDay: true, humidity: 71, wind: 9.4, days: [], hours: [], fahrenheit: false)
    private let rates: (String, String) -> Double? = { from, to in from == "USD" && to == "TRY" ? 38.4567 : nil }

    /// Runs `body` with only the given items on, then puts the user's settings back.
    private func with(_ items: [MenuBarItem], base: String = "TRY", watched: String = "TRY,USD,EUR", _ body: () throws -> Void) rethrows {
        Prefs.registerDefaults()
        let saved = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer { for (key, value) in saved { UserDefaults.standard.set(value, forKey: key) } }
        UserDefaults.standard.set("en", forKey: Prefs.language)
        for item in MenuBarItem.allCases { UserDefaults.standard.set(items.contains(item), forKey: item.key) }
        UserDefaults.standard.set(base, forKey: Prefs.baseCurrency)
        UserDefaults.standard.set(watched, forKey: Prefs.watchedCurrencies)
        UserDefaults.standard.set(true, forKey: Prefs.barLabels)
        try body()
    }

    private func parts(weather: WeatherStore.Report?) -> [MenuBarPart] {
        // A running timer or focus session would come first; only the items picked in Settings are checked here.
        MenuBarText.parts(monitor: nil, weather: weather, rate: rates).filter { $0.item != .timer }
    }

    @Test func showsTheTemperatureWithItsSymbol() throws {
        try with([.weather]) {
            let part = try #require(parts(weather: report).first)
            #expect(part.item == .weather && part.label == "Temp" && part.value == "11°")
            #expect(part.symbol == WeatherCode.symbol(61, day: true))
            #expect(NSImage(systemSymbolName: try #require(part.symbol), accessibilityDescription: nil) != nil)
        }
    }

    @Test func leavesTheWeatherOutUntilThereIsAReport() {
        with([.weather]) { #expect(parts(weather: nil).isEmpty) }
    }

    @Test func showsTheFirstWatchedCurrencyInTheBaseOne() throws {
        try with([.currency]) {
            let part = try #require(parts(weather: nil).first)
            // The base currency (TRY) is skipped; USD is the first other one.
            #expect(part.item == .currency && part.label == "USD")
            #expect(part.value == Format.number(38.4567, maxDigits: 2, minDigits: 2))
        }
    }

    @Test func leavesTheCurrencyOutWithoutARateOrAnotherCurrency() {
        with([.currency], watched: "TRY,EUR") { #expect(parts(weather: nil).isEmpty) }
        with([.currency], watched: "TRY") { #expect(parts(weather: nil).isEmpty) }
    }

    @Test func keepsTheSettingsOrder() {
        with([.weather, .currency]) {
            #expect(parts(weather: report).map(\.item) == [.currency, .weather])
        }
    }

    @Test func drawsTheSymbolIntoTheStackedImage() {
        with([.weather]) {
            let withSymbol = MenuBarText.image(parts: parts(weather: report), icon: nil, height: 22)
            var plain = parts(weather: report)
            plain[0].symbol = nil
            // The symbol takes room before the value, and the image stays a template the system tints.
            #expect(withSymbol.size.width > MenuBarText.image(parts: plain, icon: nil, height: 22).size.width)
            #expect(withSymbol.isTemplate)
        }
    }
}
