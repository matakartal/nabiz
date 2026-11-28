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
