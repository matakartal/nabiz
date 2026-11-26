// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Foundation
import Observation

/// The weather for one city, from Open-Meteo (free, no key, no account). Only the city's coordinates leave the Mac:
/// no location permission is asked, and the city comes from the time zone until you pick another in Settings.
@MainActor
@Observable
final class WeatherStore {
    static let shared = WeatherStore()

    struct Place: Codable, Equatable, Identifiable, Sendable {
        var name: String
        var detail: String
        var latitude: Double
        var longitude: Double
        var id: String { "\(latitude),\(longitude)" }
    }

    struct Day: Codable, Equatable, Identifiable, Sendable {
        var date: Date
        var code: Int
        var high: Double
        var low: Double
        /// 0…100.
        var rain: Int?
        var sunrise: Date?
        var sunset: Date?
        var id: Date { date }
    }

    struct Hour: Codable, Equatable, Sendable {
        var date: Date
        var rain: Int
        var code: Int
    }

    struct Report: Codable, Equatable, Sendable {
        var place: Place
        var fetched: Date
        var temperature: Double
        var feelsLike: Double
        var code: Int
        var isDay: Bool
        var humidity: Int?
        var wind: Double?
        var days: [Day]
        var hours: [Hour]
        var fahrenheit: Bool
        /// The city's offset from GMT, so day names and times read as they do there.
        var utcOffset: Int?

        var timeZone: TimeZone { utcOffset.flatMap { TimeZone(secondsFromGMT: $0) } ?? .current }
    }

    private(set) var report: Report?
    @ObservationIgnored private var loading = false
    /// When the last try ended, good or not: a success waits 15 minutes, a failure 2 (no request every tick offline).
    @ObservationIgnored private var triedAt: Date?
    @ObservationIgnored private var lastFailed = false
    /// The time-zone guess is tried once per launch; a zone like "Etc/GMT+3" names no city.
    @ObservationIgnored private var guessed = false
    @ObservationIgnored var onChange: (() -> Void)?

    private static let cacheKey = "weatherCache"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey) {
            report = try? JSONDecoder().decode(Report.self, from: data)
        }
    }

    /// Fahrenheit only by choice, by macOS's own temperature setting, or for a US region in an American time zone
    /// (an en_US Mac in Istanbul still reads Celsius).
    static var fahrenheit: Bool {
        switch Prefs.string(Prefs.weatherUnit) {
        case "f": return true
        case "c": return false
        default:
            return systemFahrenheit(unit: UserDefaults.standard.string(forKey: "AppleTemperatureUnit"),
                                    usRegion: Locale.current.measurementSystem == .us, timeZone: TimeZone.current.identifier)
        }
    }

    nonisolated static func systemFahrenheit(unit: String?, usRegion: Bool, timeZone: String) -> Bool {
        if let unit { return unit == "Fahrenheit" }
        return usRegion && (timeZone.hasPrefix("America/") || timeZone.hasPrefix("Pacific/Honolulu") || timeZone.hasPrefix("US/"))
    }

    /// The chosen city; nil until one is picked or found from the time zone.
    static var place: Place? {
        guard let data = UserDefaults.standard.data(forKey: Prefs.weatherPlace) else { return nil }
        return try? JSONDecoder().decode(Place.self, from: data)
    }

    static func choose(_ place: Place?) {
        UserDefaults.standard.set(place.flatMap { try? JSONEncoder().encode($0) }, forKey: Prefs.weatherPlace)
        shared.triedAt = nil
        shared.refreshIfNeeded()
    }

    /// "Europe/Istanbul" → "Istanbul": a good first guess without asking for the location.
    nonisolated static func cityFromTimeZone(_ identifier: String = TimeZone.current.identifier) -> String? {
        guard identifier.contains("/"), let last = identifier.split(separator: "/").last else { return nil }
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// Every 15 minutes at most; right away when the city or the unit changed.
    func refreshIfNeeded() {
        let wait: TimeInterval = lastFailed ? 120 : 900
        let stale = triedAt.map { Date().timeIntervalSince($0) > wait } ?? true
        let changed = report.map { $0.place != Self.place || $0.fahrenheit != Self.fahrenheit } ?? true
        guard !loading, stale || (changed && Self.place != nil) else { return }
        if Self.place == nil && guessed && !stale { return }
        loading = true
        Task {
            defer { loading = false }
            if Self.place == nil, !guessed, let city = Self.cityFromTimeZone() {
                guessed = true
                let found = await Self.search(city).first
                // Only if nothing was picked in Settings meanwhile.
                if let found, Self.place == nil {
                    UserDefaults.standard.set(try? JSONEncoder().encode(found), forKey: Prefs.weatherPlace)
                }
            }
            guard let place = Self.place else { triedAt = Date(); lastFailed = true; return }
            let fahrenheit = Self.fahrenheit
            let fresh = await Self.fetch(place, fahrenheit: fahrenheit)
            triedAt = Date()
            guard let fresh else { lastFailed = true; return }
            lastFailed = false
            // The city or unit changed while this was on its way: the next tick fetches the right one.
            guard fresh.place == Self.place, fahrenheit == Self.fahrenheit else { triedAt = nil; return }
            report = fresh
            UserDefaults.standard.set(try? JSONEncoder().encode(fresh), forKey: Self.cacheKey)
            onChange?()
        }
    }

    /// Cities matching the name, for Settings.
    nonisolated static func search(_ name: String) async -> [Place] {
        let query = name.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2,
              var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search") else { return [] }
        components.queryItems = [URLQueryItem(name: "name", value: query), URLQueryItem(name: "count", value: "8"),
                                 URLQueryItem(name: "language", value: Prefs.isTurkish ? "tr" : "en"),
                                 URLQueryItem(name: "format", value: "json")]
        guard let url = components.url, let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { result in
            guard let name = result["name"] as? String, let latitude = result["latitude"] as? Double,
                  let longitude = result["longitude"] as? Double else { return nil }
            let detail = [result["admin1"] as? String, result["country"] as? String].compactMap { $0 }
                .filter { $0 != name }.joined(separator: ", ")
            return Place(name: name, detail: detail, latitude: latitude, longitude: longitude)
        }
    }

    nonisolated static func fetch(_ place: Place, fahrenheit: Bool) async -> Report? {
        guard var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", place.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,relative_humidity_2m,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "precipitation_probability,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: fahrenheit ? "mph" : "kmh"),
        ]
        guard let url = components.url, let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data, place: place, fahrenheit: fahrenheit)
    }

    nonisolated static func parse(_ data: Data, place: Place, fahrenheit: Bool, now: Date = Date()) -> Report? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = object["current"] as? [String: Any],
              let temperature = (current["temperature_2m"] as? NSNumber)?.doubleValue,
              let code = (current["weather_code"] as? NSNumber)?.intValue else { return nil }
        func dates(_ list: Any?) -> [Date] { (list as? [NSNumber] ?? []).map { Date(timeIntervalSince1970: $0.doubleValue) } }
        func ints(_ list: Any?) -> [Int?] { (list as? [Any] ?? []).map { ($0 as? NSNumber)?.intValue } }
        func doubles(_ list: Any?) -> [Double?] { (list as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue } }

        var days: [Day] = []
        if let daily = object["daily"] as? [String: Any] {
            let when = dates(daily["time"]), codes = ints(daily["weather_code"])
            let highs = doubles(daily["temperature_2m_max"]), lows = doubles(daily["temperature_2m_min"])
            let rain = ints(daily["precipitation_probability_max"])
            let rises = dates(daily["sunrise"]), sets = dates(daily["sunset"])
            for index in when.indices {
                guard codes.indices.contains(index), let code = codes[index], highs.indices.contains(index), let high = highs[index],
                      lows.indices.contains(index), let low = lows[index] else { continue }
                days.append(Day(date: when[index], code: code, high: high, low: low,
                                rain: rain.indices.contains(index) ? rain[index] : nil,
                                sunrise: rises.indices.contains(index) ? rises[index] : nil,
                                sunset: sets.indices.contains(index) ? sets[index] : nil))
            }
        }
        var hours: [Hour] = []
        if let hourly = object["hourly"] as? [String: Any] {
            let when = dates(hourly["time"]), rain = ints(hourly["precipitation_probability"]), codes = ints(hourly["weather_code"])
            for index in when.indices where when[index] > now.addingTimeInterval(-3600) && when[index] < now.addingTimeInterval(24 * 3600) {
                guard rain.indices.contains(index), let chance = rain[index], codes.indices.contains(index), let code = codes[index] else { continue }
                hours.append(Hour(date: when[index], rain: chance, code: code))
            }
        }
        return Report(place: place, fetched: now, temperature: temperature,
                      feelsLike: (current["apparent_temperature"] as? NSNumber)?.doubleValue ?? temperature,
                      code: code, isDay: (current["is_day"] as? NSNumber)?.intValue != 0,
                      humidity: (current["relative_humidity_2m"] as? NSNumber)?.intValue,
                      wind: (current["wind_speed_10m"] as? NSNumber)?.doubleValue,
                      days: days, hours: hours, fahrenheit: fahrenheit,
                      utcOffset: (object["utc_offset_seconds"] as? NSNumber)?.intValue)
    }

    /// Opens Apple's Weather app (or the forecast on the web where it isn't installed).
    static func openWeatherApp() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.weather") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        } else if let place = shared.report?.place,
                  let url = URL(string: "https://open-meteo.com/en/docs#latitude=\(place.latitude)&longitude=\(place.longitude)") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension WeatherStore.Report {
    /// "Today", "Tomorrow" or the weekday, by the date in the city (a cached report from yesterday says so).
    func dayName(_ date: Date, now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: now) { return L("Bugün", "Today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return L("Yarın", "Tomorrow")
        }
        var style = Date.FormatStyle.dateTime.weekday(.wide).locale(Format.locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// A time of day as the city's clock shows it.
    func clock(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened).locale(Format.locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// Days from today on (a cached report can start yesterday).
    var upcomingDays: [WeatherStore.Day] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: Date())
        return days.filter { calendar.startOfDay(for: $0.date) >= today }
    }

    /// The first hour of the next 12 with a 50% or higher chance of rain or snow, if it isn't already raining.
    var nextRain: WeatherStore.Hour? {
        guard !WeatherCode.isWet(code) else { return nil }
        let end = Date().addingTimeInterval(12 * 3600)
        return hours.first { $0.date > Date() && $0.date < end && $0.rain >= 50 }
    }

    /// The next sunrise or sunset still ahead today (or tomorrow's sunrise).
    var nextSun: (rise: Bool, date: Date)? {
        let now = Date()
        for day in days {
            if let rise = day.sunrise, rise > now { return (true, rise) }
            if let set = day.sunset, set > now { return (false, set) }
        }
        return nil
    }
}

/// WMO weather codes as Open-Meteo reports them: words and SF Symbols like Apple's Weather app.
enum WeatherCode {
    static func title(_ code: Int) -> String {
        switch code {
        case 0: L("Açık", "Clear")
        case 1: L("Çoğunlukla açık", "Mostly clear")
        case 2: L("Parçalı bulutlu", "Partly cloudy")
        case 3: L("Bulutlu", "Cloudy")
        case 45, 48: L("Sisli", "Foggy")
        case 51, 53, 55: L("Çiseleme", "Drizzle")
        case 56, 57: L("Dondurucu çiseleme", "Freezing drizzle")
        case 61: L("Hafif yağmur", "Light rain")
        case 63: L("Yağmurlu", "Rain")
        case 65: L("Kuvvetli yağmur", "Heavy rain")
        case 66, 67: L("Dondurucu yağmur", "Freezing rain")
        case 71: L("Hafif kar", "Light snow")
        case 73: L("Karlı", "Snow")
        case 75: L("Yoğun kar", "Heavy snow")
        case 77: L("Kar taneleri", "Snow grains")
        case 80, 81: L("Sağanak", "Showers")
        case 82: L("Kuvvetli sağanak", "Heavy showers")
        case 85, 86: L("Kar sağanağı", "Snow showers")
        case 95: L("Gök gürültülü fırtına", "Thunderstorm")
        case 96, 99: L("Dolulu fırtına", "Thunderstorm with hail")
        default: L("Bilinmiyor", "Unknown")
        }
    }

    static func symbol(_ code: Int, day: Bool = true) -> String {
        switch code {
        case 0: day ? "sun.max" : "moon.stars"
        case 1, 2: day ? "cloud.sun" : "cloud.moon"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51, 53, 55, 56, 57: "cloud.drizzle"
        case 61, 63, 66: "cloud.rain"
        case 65, 67, 82: "cloud.heavyrain"
        case 80, 81: day ? "cloud.sun.rain" : "cloud.moon.rain"
        case 71, 73, 75, 77, 85, 86: "cloud.snow"
        case 95: "cloud.bolt.rain"
        case 96, 99: "cloud.hail"
        default: "cloud"
        }
    }

    static func isWet(_ code: Int) -> Bool { code >= 51 }
}

extension Format {
    /// "14°": rounded, no unit, like the system's own weather.
    static func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }
}
