// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

/// The calculator's maths and unit conversion. Currency needs live rates, so it is left to the app.
@MainActor
@Suite("Calculator")
struct CalculatorTests {
    init() {
        Prefs.registerDefaults()
        UserDefaults.standard.set("en", forKey: Prefs.language)
    }

    private func copy(_ text: String) -> String? { Calculator.evaluate(text)?.copy }

    @Test("Arithmetic", arguments: [
        ("12*4", "48"), ("(3+4)^2", "49"), ("2 x 3", "6"), ("10 - 2 - 3", "5"), ("-5 + 2", "-3"),
    ])
    func arithmetic(input: String, expected: String) {
        #expect(copy(input) == expected)
    }

    @Test("Percent adds a share of the left side")
    func percent() {
        #expect(copy("200 + %18") == "236")
        #expect(copy("200 + 18%") == "236")
        #expect(copy("200 - 10%") == "180")
    }

    @Test("Both decimal styles")
    func decimals() {
        #expect(copy("1.500,50 + 2") == "1,502.5")
        #expect(copy("1,234.5 + 0.5") == "1,235")
    }

    @Test("Nonsense and division by zero give nothing")
    func rejects() {
        #expect(Calculator.evaluate("10/0") == nil)
        #expect(Calculator.evaluate("hello") == nil)
        #expect(Calculator.evaluate("") == nil)
        #expect(Calculator.evaluate("42") == nil)
    }

    @Test("Units", arguments: [
        ("5 km mi", "3.1069"), ("100 f c", "37.7778"), ("37 c", "98.6"), ("2 gb mb", "2,048"),
        ("90 min h", "1.5"), ("3 ft in cm", "91.44"), ("180 lb kg", "81.6466"),
    ])
    func units(input: String, expected: String) {
        #expect(copy(input) == expected)
    }

    @Test("Units of different kinds don't convert")
    func mismatchedUnits() {
        #expect(Calculator.evaluate("5 km kg") == nil)
    }
}

@MainActor
@Suite("Calculator, more")
struct CalculatorMoreTests {
    init() {
        Prefs.registerDefaults()
        UserDefaults.standard.set("en", forKey: Prefs.language)
    }

    private func copy(_ text: String) -> String? { Calculator.evaluate(text)?.copy }

    @Test("Functions, constants, factorial, mod, implicit multiplication", arguments: [
        ("sqrt 16", "4"), ("√2 * √2", "2"), ("sin 30", "0.5"), ("cos(60)", "0.5"), ("log 1000", "3"), ("ln e", "1"),
        ("5!", "120"), ("17 mod 5", "2"), ("2pi", "6.28318531"), ("3(4+1)", "15"), ("abs(-7)", "7"), ("20% of 150", "30"),
        ("pi", "3.14159265"), ("5 bin + 1", "5,001"), ("2,5 milyon / 1000", "2,500"),
    ])
    func maths(input: String, expected: String) {
        #expect(copy(input) == expected)
    }

    @Test("Bases")
    func bases() {
        #expect(copy("255 hex") == "0xFF")
        #expect(copy("10 binary") == "0b1010")
        #expect(copy("0xff") == "255")
        #expect(copy("0b1010 + 1") == "11")
        #expect(Calculator.evaluateAll("255 hex").count == 4)
    }

    @Test("More units, with alternatives when no target is typed", arguments: [
        ("120 km/h mph", "74.5645"), ("3 dönüm m2", "3,000"), ("2 l ml", "2,000"), ("100 kcal kj", "418.4"),
        ("1 acre ha", "0.4047"), ("10 m/s km/h", "36"),
    ])
    func units(input: String, expected: String) {
        #expect(copy(input) == expected)
    }

    @Test("A lone unit offers a few more targets")
    func alternatives() {
        let results = Calculator.evaluateAll("5 km")
        #expect(results.count > 1)
        #expect(results.first?.note == "mi")
    }

    @Test("Raw copy has no grouping and full precision")
    func raw() {
        #expect(Calculator.evaluate("1024*2")?.raw == "2048")
        #expect(Calculator.evaluate("10/4")?.raw == "2.5")
    }

    @Test("A bare number or text gives nothing")
    func nothing() {
        #expect(Calculator.evaluate("42") == nil)
        #expect(Calculator.evaluate("safari") == nil)
        #expect(Calculator.evaluate("sqrt -1") == nil)
    }
}

@MainActor
@Suite("World clock and dates")
struct ClockDateTests {
    init() { UserDefaults.standard.set("en", forKey: Prefs.language) }

    // 2026-06-01 12:00 UTC
    private let now = Date(timeIntervalSince1970: 1_780_315_200)

    @Test("Cities, aliases and abbreviations resolve")
    func zones() {
        #expect(WorldClock.zone("tokyo")?.identifier == "Asia/Tokyo")
        #expect(WorldClock.zone("new york")?.identifier == "America/New_York")
        #expect(WorldClock.zone("londra")?.identifier == "Europe/London")
        #expect(WorldClock.zone("nyc")?.identifier == "America/New_York")
        #expect(WorldClock.zone("km") == nil)
    }

    @Test("A time in one city, shown in another")
    func conversion() throws {
        let result = try #require(WorldClock.evaluate("15:00 istanbul to tokyo", now: now)?.first)
        #expect(result.text.contains("Tokyo"))
        #expect(result.note == "+6 h")
        #expect(WorldClock.evaluate("5 km mi", now: now) == nil)
        #expect(WorldClock.evaluate("2 saat dk", now: now) == nil)
    }

    @Test("Date sums and spans")
    func dates() throws {
        let plus = try #require(DateMath.evaluate("2026-01-01 + 30 days", now: now)?.first)
        #expect(plus.text.contains("January 31, 2026"))
        let span = try #require(DateMath.evaluate("2026-12-31 - 2026-01-01", now: now)?.first)
        #expect(span.copy == "364")
        let until = try #require(DateMath.evaluate("days until 2026-06-11", now: now)?.first)
        #expect(until.copy == "10")
        #expect(DateMath.evaluate("31.02.2026", now: now) == nil)
        #expect(DateMath.evaluate("12.5", now: now) == nil)
    }
}
