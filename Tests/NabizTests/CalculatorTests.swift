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
