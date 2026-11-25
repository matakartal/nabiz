import CoreGraphics
import Foundation
import Testing
@testable import Nabiz

@Suite("Launcher")
struct LauncherTests {
    @Test("Exact beats prefix beats word prefix beats initials beats substring")
    func ranking() throws {
        let exact = try #require(Fuzzy.score("safari", "Safari"))
        let prefix = try #require(Fuzzy.score("saf", "Safari"))
        let word = try #require(Fuzzy.score("studio", "Visual Studio Code"))
        let initials = try #require(Fuzzy.score("vsc", "Visual Studio Code"))
        let inside = try #require(Fuzzy.score("ari", "Safari"))
        #expect(exact > prefix)
        #expect(prefix > word)
        #expect(word > initials)
        #expect(initials > inside)
    }

    @Test("Turkish letters and accents match their plain forms")
    func folding() {
        #expect(Fuzzy.score("ekrani", "Ekranı kilitle") != nil)
        #expect(Fuzzy.score("cop", "Çöp Sepeti'ni boşalt") != nil)
        #expect(Fuzzy.score("ISIK", "ışık") != nil)
    }

    @Test("Letters in order match only from three letters, and nothing out of order")
    func subsequence() {
        #expect(Fuzzy.score("sfr", "Safari") != nil)
        #expect(Fuzzy.score("sf", "Safari") == nil)
        #expect(Fuzzy.score("rfs", "Safari") == nil)
        #expect(Fuzzy.score("", "Safari") == nil)
    }

    @Test("Aliases match only from the start of a word")
    func keywords() {
        #expect(Fuzzy.keyword("ayar", "settings ayarlar preferences") != nil)
        #expect(Fuzzy.keyword("sa", "settings ayarlar preferences") == nil)
        #expect(Fuzzy.keyword("bos", "trash çöp boşalt") != nil)
        #expect(Fuzzy.keyword("sal", "trash çöp boşalt") == nil)
    }

    @Test("A quicklink puts the encoded search where {query} is")
    func quicklink() {
        let link = Quicklink(keyword: "g", name: "Google", url: "https://www.google.com/search?q={query}")
        #expect(link.url(for: "nabız app")?.absoluteString == "https://www.google.com/search?q=nab%C4%B1z%20app")
        #expect(link.url(for: "")?.absoluteString == "https://www.google.com/search?q=")
    }

    @MainActor
    @Test("Snippets fill in the date and leave other text alone")
    func snippet() {
        let snippet = Snippet(keyword: "imza", name: "İmza", text: "Sevgiler,\nAta · {date}")
        #expect(snippet.expanded.hasPrefix("Sevgiler,\nAta · "))
        #expect(!snippet.expanded.contains("{date}"))
    }

    @Test("Window layouts split the usable screen")
    func windowLayouts() {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let window = CGSize(width: 400, height: 300)
        #expect(WindowAction.leftHalf.target(for: window, in: screen) == CGRect(x: 0, y: 0, width: 600, height: 800))
        #expect(WindowAction.rightHalf.target(for: window, in: screen) == CGRect(x: 600, y: 0, width: 600, height: 800))
        #expect(WindowAction.topHalf.target(for: window, in: screen) == CGRect(x: 0, y: 400, width: 1200, height: 400))
        #expect(WindowAction.center.target(for: window, in: screen) == CGRect(x: 400, y: 250, width: 400, height: 300))
        #expect(WindowAction.rightThird.target(for: window, in: screen) == CGRect(x: 800, y: 0, width: 400, height: 800))
        #expect(WindowAction.maximize.target(for: window, in: screen) == screen)
        // A window bigger than the next screen is shrunk to fit it.
        let big = CGSize(width: 2000, height: 1000)
        #expect(WindowAction.nextDisplay.target(for: big, in: screen) == screen)
    }

    @Test("Hex colours parse in long and short form")
    func hex() {
        #expect(Theme.RGBA.hex(0x1DB954).g > 0.7)
        #expect(ClipItem(kind: .color, text: "#FFF", date: .now).preview == "#FFF")
    }
}
