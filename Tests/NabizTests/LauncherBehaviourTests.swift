// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

/// How the launcher keeps its selection, reads quicklinks, scripts and snippets, and learns what you pick.
@MainActor
@Suite("Launcher behaviour")
struct LauncherBehaviourTests {
    init() {
        Prefs.registerDefaults()
        UserDefaults.standard.set("en", forKey: Prefs.language)
    }

    private func rows(_ ids: [String]) -> [LauncherItem] {
        ids.map { LauncherItem(id: $0, icon: .symbol("circle"), title: $0, primaryTitle: "Run", primary: {}) }
    }

    @Test("The highlighted row stays put when rows arrive above it")
    func stableSelection() {
        let model = LauncherModel()
        #expect(model.resolvedSelection(rows(["a", "b", "c"])) == "a")
        // Files or an AI row arrive later and push the first row down: it stays the highlighted one.
        #expect(model.resolvedSelection(rows(["ai", "a", "b", "c"])) == "a")
        model.selectedID = "c"
        #expect(model.resolvedSelection(rows(["x", "y", "c"])) == "c")
        // The picked row is gone: back to the first shown.
        #expect(model.resolvedSelection(rows(["a", "b"])) == "a")
    }

    @Test("Deleting the selected row selects its neighbour")
    func neighbour() {
        let model = LauncherModel()
        model.selectNeighbour(of: "b", in: rows(["a", "b", "c"]))
        #expect(model.selectedID == "c")
        model.selectNeighbour(of: "c", in: rows(["a", "b", "c"]))
        #expect(model.selectedID == "b")
        model.selectNeighbour(of: "a", in: rows(["a"]))
        #expect(model.selectedID == nil)
    }

    @Test("Space right after a search keyword picks that quicklink")
    func spaceAfterKeyword() {
        let links = [Quicklink(keyword: "gh", name: "GitHub", url: "https://github.com/search?q={query}"),
                     Quicklink(keyword: "home", name: "Home", url: "https://example.com"),
                     Quicklink(keyword: "çevir", name: "Translate", url: "https://t.example/?q={query}")]
        #expect(LauncherModel.quicklink(forSpaceAfter: "gh ", in: links, translating: true)?.name == "GitHub")
        #expect(LauncherModel.quicklink(forSpaceAfter: "GH ", in: links, translating: true)?.name == "GitHub")
        #expect(LauncherModel.quicklink(forSpaceAfter: "gh", in: links, translating: true) == nil)
        #expect(LauncherModel.quicklink(forSpaceAfter: "gh x ", in: links, translating: true) == nil)
        // A link without {query} just opens; the translate words go to AI when it's on.
        #expect(LauncherModel.quicklink(forSpaceAfter: "home ", in: links, translating: true) == nil)
        #expect(LauncherModel.quicklink(forSpaceAfter: "çevir ", in: links, translating: true) == nil)
        #expect(LauncherModel.quicklink(forSpaceAfter: "çevir ", in: links, translating: false)?.name == "Translate")
    }

    @Test("Script headers give a title, an icon and up to three arguments")
    func scriptHeader() {
        let head = """
        #!/bin/zsh
        # @raycast.title Look up
        # @raycast.icon 🔎
        # @raycast.argument1 { "type": "text", "placeholder": "Word" }
        # @raycast.argument2 { "type": "text", "placeholder": "Language", "optional": true }
        # @nabiz.argument3 broken json
        """
        let script = Extensions.parse(head, path: "/tmp/x.sh", fallback: "x")
        #expect(script.title == "Look up")
        #expect(script.icon == "🔎")
        #expect(script.arguments.count == 3)
        #expect(script.arguments[0].placeholder == "Word")
        #expect(script.arguments[1].optional == true)
        #expect(script.arguments[2].placeholder == nil)
        #expect(Extensions.parse("echo hi", path: "/tmp/y.sh", fallback: "y").arguments.isEmpty)
    }

    @Test("A typed keyword after the prefix picks its snippet, the longest when several fit")
    func snippetTrigger() throws {
        let short = Snippet(keyword: "sig", name: "Short", text: "S")
        let long = Snippet(keyword: "sig2", name: "Long", text: "L")
        let hit = try #require(SnippetExpander.match("hello ;sig", prefix: ";", in: [short, long]))
        #expect(hit.0.name == "Short")
        #expect(hit.1 == 4)
        #expect(SnippetExpander.match("hello ;sig2", prefix: ";", in: [short, long])?.0.name == "Long")
        #expect(SnippetExpander.match("hello sig", prefix: ";", in: [short]) == nil)
        // Without a prefix, only at the start of a word.
        #expect(SnippetExpander.match("a sig", prefix: "", in: [short]) != nil)
        #expect(SnippetExpander.match("design sig", prefix: "", in: [short]) != nil)
        #expect(SnippetExpander.match("designsig", prefix: "", in: [short]) == nil)
        #expect(SnippetExpander.match(";", prefix: ";", in: [Snippet(keyword: "", name: "Empty", text: "")]) == nil)
    }

    @Test("{cursor} marks where the cursor goes after pasting")
    func cursorPlaceholder() {
        let snippet = Snippet(keyword: "x", name: "x", text: "Hi {cursor}, thanks")
        let (text, back) = snippet.expandedWithCursor
        #expect(text == "Hi , thanks")
        #expect(back == ", thanks".count)
        #expect(Snippet(keyword: "y", name: "y", text: "plain").expandedWithCursor.cursorBack == 0)
        #expect(Snippet(keyword: "z", name: "z", text: "a{cursor}b{cursor}c").expandedWithCursor.text == "abc")
    }

    @Test("What was picked for some letters ranks first for them next time, fading with age")
    func learnsPicks() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        var memory = PickMemory()
        memory.record("s", "app:/Applications/Slack.app", now: now)
        memory.record("S ", "app:/Applications/Slack.app", now: now)
        let fresh = memory.bonus(for: "s", now: now)["app:/Applications/Slack.app"] ?? 0
        #expect(fresh == 300)
        let later = memory.bonus(for: "s", now: now.addingTimeInterval(PickMemory.halfLife))["app:/Applications/Slack.app"] ?? 0
        #expect(later == 150)
        #expect(memory.bonus(for: "sa", now: now).isEmpty)
        // Only a handful of items are kept per query.
        for index in 0..<10 { memory.record("x", "cmd:\(index)", now: now.addingTimeInterval(Double(index))) }
        #expect(memory.picks["x"]?.count == 5)
    }

    @Test("Recents order by how often and how lately")
    func frecency() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let uses: [String: LauncherUse] = [
            "often": LauncherUse(count: 6, last: now.addingTimeInterval(-3 * 86_400)),
            "once-now": LauncherUse(count: 1, last: now),
            "old": LauncherUse(count: 6, last: now.addingTimeInterval(-60 * 86_400)),
        ]
        #expect(Recents.ordered(uses, now: now) == ["often", "once-now", "old"])
    }

    @Test("A quick note is the text after note or not")
    func quickNote() {
        #expect(LauncherModel.quickNote("note buy milk") == "buy milk")
        #expect(LauncherModel.quickNote("Not süt al") == "süt al")
        #expect(LauncherModel.quickNote("note") == nil)
        #expect(LauncherModel.quickNote("note   ") == nil)
        #expect(LauncherModel.quickNote("notes") == nil)
    }

    @Test("System Settings pages answer in both languages")
    func panes() {
        func top(_ query: String) -> String? {
            SystemPane.all.compactMap { pane -> (Int, String)? in
                let best = [Fuzzy.score(query, pane.title), Fuzzy.keyword(query, pane.keywords)].compactMap { $0 }.max()
                return best.map { ($0, pane.en) }
            }.max { $0.0 < $1.0 }?.1
        }
        #expect(top("wifi") == "Wi-Fi")
        #expect(top("displays") == "Displays")
        #expect(top("ekranlar") == "Displays")
        #expect(top("gizlilik") != nil)
        #expect(top("privacy") != nil)
        #expect(SystemPane.all.allSatisfy { $0.url != nil })
        #expect(Set(SystemPane.all.map(\.id)).count == SystemPane.all.count)
    }

    @Test("A script asks for its values one at a time")
    func scriptArgumentSteps() {
        let script = Extensions.parse("# @raycast.argument1 {\"placeholder\": \"A\"}\n# @raycast.argument2 {\"placeholder\": \"B\"}",
                                      path: "/tmp/z.sh", fallback: "z")
        var argument = LauncherArgument(target: .script(script))
        #expect(!argument.isLast)
        #expect(argument.placeholder == "A")
        argument.values = ["one"]
        #expect(argument.isLast)
        #expect(argument.placeholder == "B")
    }
}
