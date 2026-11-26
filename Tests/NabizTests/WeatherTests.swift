// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

/// The weather: reading Open-Meteo's answer, the city guess and where the new panel section lands.
@MainActor
@Suite("Weather")
struct WeatherTests {
    init() {
        Prefs.registerDefaults()
        UserDefaults.standard.set("en", forKey: Prefs.language)
    }

    private let place = WeatherStore.Place(name: "Istanbul", detail: "Türkiye", latitude: 41.01, longitude: 28.95)

    @Test func readsTheForecast() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let hour: (Int) -> Int = { 1_800_000_000 + $0 * 3600 }
        let json: [String: Any] = [
            "current": ["temperature_2m": 14.4, "apparent_temperature": 12.1, "weather_code": 2, "is_day": 1,
                        "relative_humidity_2m": 71, "wind_speed_10m": 9.5],
            "hourly": ["time": [hour(0), hour(1), hour(2), hour(30)], "precipitation_probability": [10, 20, 70, 90],
                       "weather_code": [2, 3, 61, 63]],
            "daily": ["time": [hour(-10), hour(14)], "weather_code": [2, 61], "temperature_2m_max": [18.2, 15.0],
                      "temperature_2m_min": [9.4, NSNull()], "precipitation_probability_max": [10, 80],
                      "sunrise": [hour(-4), hour(20)], "sunset": [hour(6), hour(31)]],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let report = try #require(WeatherStore.parse(data, place: place, fahrenheit: false, now: now))
        #expect(Format.degrees(report.temperature) == "14°")
        #expect(Format.degrees(report.feelsLike) == "12°")
        #expect(report.isDay && report.code == 2 && report.humidity == 71)
        // A day with a missing low is skipped, not shown as 0°.
        #expect(report.days.count == 1)
        // Hours more than a day ahead are dropped.
        #expect(report.hours.map(\.rain) == [10, 20, 70])
    }

    @Test func namesDaysByTheCitysClock() throws {
        // 2026-11-28 00:30 in Auckland (+13) is still the 27th in UTC.
        let json: [String: Any] = ["current": ["temperature_2m": 20, "weather_code": 0, "is_day": 1], "utc_offset_seconds": 46_800]
        let report = try #require(WeatherStore.parse(try JSONSerialization.data(withJSONObject: json), place: place, fahrenheit: false))
        #expect(report.timeZone.secondsFromGMT() == 46_800)
        let now = ISO8601DateFormatter().date(from: "2026-11-27T11:30:00Z")!
        let midnight = ISO8601DateFormatter().date(from: "2026-11-27T11:00:00Z")!
        #expect(report.dayName(midnight, now: now) == "Today")
        #expect(report.dayName(midnight.addingTimeInterval(86_400), now: now) == "Tomorrow")
        #expect(report.dayName(midnight.addingTimeInterval(2 * 86_400), now: now) == "Monday")
    }

    @Test func rejectsABrokenAnswer() {
        #expect(WeatherStore.parse(Data("{}".utf8), place: place, fahrenheit: false) == nil)
        #expect(WeatherStore.parse(Data("not json".utf8), place: place, fahrenheit: false) == nil)
    }

    @Test func guessesTheCityFromTheTimeZone() {
        #expect(WeatherStore.cityFromTimeZone("Europe/Istanbul") == "Istanbul")
        #expect(WeatherStore.cityFromTimeZone("America/New_York") == "New York")
        #expect(WeatherStore.cityFromTimeZone("America/Argentina/Buenos_Aires") == "Buenos Aires")
        #expect(WeatherStore.cityFromTimeZone("UTC") == nil)
    }

    @Test func celsiusUnlessTheMacSaysOtherwise() {
        #expect(!WeatherStore.systemFahrenheit(unit: nil, usRegion: true, timeZone: "Europe/Istanbul"))
        #expect(WeatherStore.systemFahrenheit(unit: nil, usRegion: true, timeZone: "America/New_York"))
        #expect(!WeatherStore.systemFahrenheit(unit: nil, usRegion: false, timeZone: "America/New_York"))
        #expect(WeatherStore.systemFahrenheit(unit: "Fahrenheit", usRegion: false, timeZone: "Europe/Istanbul"))
        #expect(!WeatherStore.systemFahrenheit(unit: "Celsius", usRegion: true, timeZone: "America/Chicago"))
    }

    @Test func wordsAndSymbolsForEveryCode() {
        for code in [0, 1, 2, 3, 45, 48, 51, 56, 61, 63, 65, 66, 71, 75, 77, 80, 82, 85, 95, 99] {
            #expect(WeatherCode.title(code) != "Unknown")
            #expect(!WeatherCode.symbol(code).isEmpty)
        }
        #expect(WeatherCode.symbol(0, day: false) == "moon.stars")
        #expect(!WeatherCode.isWet(3) && WeatherCode.isWet(61))
        #expect(Format.degrees(-0.4) == "0°")
    }

    @Test func aNewSectionLandsWhereItBelongs() {
        let saved = UserDefaults.standard.string(forKey: Prefs.sectionOrder)
        defer { UserDefaults.standard.set(saved, forKey: Prefs.sectionOrder) }
        // An order saved before the weather existed, with tools moved to the top.
        UserDefaults.standard.set("tools,system,advice,simulators,ports,projects,docker,displays,ai,calendar,memory,cpu,markets,currency",
                                  forKey: Prefs.sectionOrder)
        let order = PanelSection.ordered
        #expect(order.count == PanelSection.allCases.count)
        #expect(order.firstIndex(of: .weather) == order.firstIndex(of: .calendar).map { $0 + 1 })
        #expect(order.first == .tools)
        UserDefaults.standard.set("", forKey: Prefs.sectionOrder)
        #expect(PanelSection.ordered == PanelSection.allCases)
    }
}
