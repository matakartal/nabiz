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
}
