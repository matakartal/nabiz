// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

@MainActor
@Suite("Format")
struct FormatTests {
    @Test("Percent sign goes first in Turkish, last in English")
    func percent() {
        UserDefaults.standard.set("tr", forKey: Prefs.language)
        #expect(Format.percent(0.34) == "%34")
        UserDefaults.standard.set("en", forKey: Prefs.language)
        #expect(Format.percent(0.34) == "34%")
        #expect(Format.percent(1.7) == "100%")
    }

    @Test("Durations")
    func duration() {
        UserDefaults.standard.set("en", forKey: Prefs.language)
        #expect(Format.duration(45 * 60) == "45m")
        #expect(Format.duration(3 * 3600 + 20 * 60) == "3h 20m")
        #expect(Format.duration(2 * 86_400 + 4 * 3600) == "2d 4h")
    }

    @Test("Prices: fewer decimals as they grow")
    func price() {
        UserDefaults.standard.set("en", forKey: Prefs.language)
        #expect(Format.price(60_104) == "60,104")
        #expect(Format.price(1_689) == "1,689.00")
        #expect(Format.price(70.556) == "70.56")
        #expect(Format.price(1.2609) == "1.261")
    }

    @Test("Daily change marks")
    func change() {
        UserDefaults.standard.set("en", forKey: Prefs.language)
        #expect(Format.change(0.012) == "▲ 1.2%")
        #expect(Format.change(-0.004) == "▼ 0.4%")
        #expect(Format.change(0.0001) == "")
        #expect(Format.change(nil) == "")
    }
}

@MainActor
@Suite("Updater")
struct UpdaterTests {
    @Test("Version comparison", arguments: [
        ("1.3.0", "1.2.0", true), ("1.10.0", "1.9.2", true), ("1.2", "1.2.0", false), ("1.2.0", "1.2.1", false), ("2", "1.99", true),
    ])
    func newer(a: String, b: String, expected: Bool) {
        #expect(Updater.isNewer(a, than: b) == expected)
    }
}
