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

@Suite("Notes")
struct NoteTests {
    @Test("Return continues checklists, bullets and numbers, and ends an empty item")
    func lists() {
        #expect(NoteMarkdown.onReturn("- [x] milk") == .next("\n- [ ] "))
        #expect(NoteMarkdown.onReturn("  * eggs") == .next("\n  * "))
        #expect(NoteMarkdown.onReturn("9. ninth") == .next("\n10. "))
        #expect(NoteMarkdown.onReturn("- [ ] ") == .end)
        #expect(NoteMarkdown.onReturn("- ") == .end)
        #expect(NoteMarkdown.onReturn("just text") == .plain)
        #expect(NoteMarkdown.onReturn("") == .plain)
    }

    @Test("⌘L adds or removes a checklist box, ⇧⌘L a bullet")
    func toggling() {
        #expect(NoteMarkdown.toggled("buy milk", .checklist) == "- [ ] buy milk")
        #expect(NoteMarkdown.toggled("- [x] buy milk", .checklist) == "buy milk")
        #expect(NoteMarkdown.toggled("- buy milk", .checklist) == "- [ ] buy milk")
        #expect(NoteMarkdown.toggled("  - buy milk", .bullet) == "  buy milk")
        #expect(NoteMarkdown.toggled("buy milk", .bullet) == "- buy milk")
    }

    @Test("The checkbox is found where a click can tick it")
    func checkbox() {
        #expect(NoteMarkdown.checkbox(in: "- [ ] milk") == NSRange(location: 2, length: 3))
        #expect(NoteMarkdown.checkbox(in: "  * [x] eggs") == NSRange(location: 4, length: 3))
        #expect(NoteMarkdown.checkbox(in: "- milk") == nil)
    }

    @Test("Title is the first line without Markdown; checklist counts ticks")
    func titleAndChecklist() {
        let note = Note(text: "\n# **Release** list\n- [x] one\n- [ ] two\n* [X] three")
        #expect(note.title == "Release list")
        #expect(note.checklist.done == 2)
        #expect(note.checklist.total == 3)
        #expect(Note(text: "- [ ] call Ali").title == "call Ali")
    }

    @MainActor
    @Test("Text changes apply only where they make sense")
    func transforms() {
        UserDefaults.standard.set("en", forKey: Prefs.language)
        #expect(TextTransform.upper.apply("istanbul") == "ISTANBUL")
        #expect(TextTransform.oneLine.apply("a\n  b\n\nc") == "a b c")
        #expect(TextTransform.trimmed.apply("  a   b \n c  ") == "a b\nc")
        #expect(TextTransform.json.apply(#"{"b":1,"a":[1,2]}"#)?.contains("\n") == true)
        #expect(TextTransform.json.apply("not json") == nil)
        #expect(TextTransform.base64Encode.apply("nabız") == "bmFixLF6")
        #expect(TextTransform.base64Decode.apply("bmFixLF6") == "nabız")
        #expect(TextTransform.base64Decode.apply("%%%") == nil)
        #expect(TextTransform.urlDecode.apply("a%20b") == "a b")
        #expect(TextTransform.lower.apply("abc") == nil)
    }
}
