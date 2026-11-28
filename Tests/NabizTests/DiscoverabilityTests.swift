// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

/// The ways in to features: the "New" list, the AI chat shortcut and tile.
@MainActor
@Suite("Discoverability")
struct DiscoverabilityTests {
    init() {
        Prefs.registerDefaults()
        UserDefaults.standard.set("en", forKey: Prefs.language)
    }

    @Test func whatsNewShowsOnceForPeopleWhoUpdate() {
        #expect(WhatsNew.shouldShow(seen: "", onboarded: true))
        #expect(WhatsNew.shouldShow(seen: "older", onboarded: true))
        #expect(!WhatsNew.shouldShow(seen: WhatsNew.id, onboarded: true))
        #expect(!WhatsNew.shouldShow(seen: "", onboarded: false))
        #expect(WhatsNew.items.contains { $0.id == "accounts" })
    }

    @Test func aiChatHasItsOwnShortcutAndTile() {
        #expect(Prefs.bool(Prefs.aiChatHotkey))
        #expect(HotKey.customizable.contains(.aiChat))
        let keys: [Int] = HotKey.Shortcut.allCases.filter { $0.window == nil }.map(\.key)
        #expect(keys.count == Set(keys).count)
        #expect(ToolKind.everyday.contains(.aiChat))
        #expect(ToolKind.everyday.count == 11)
    }

    @Test func dockIconBringsAFullMenuBar() {
        #expect(!Prefs.bool(Prefs.showInDock))
        let dock = AppDelegate.mainMenu(dock: true)
        #expect(dock.items.count == 3)
        #expect(dock.items[0].submenu?.items.contains { $0.keyEquivalent == "q" } == true)
        #expect(dock.items[2].submenu?.items.contains { $0.keyEquivalent == "w" } == true)
        let bare = AppDelegate.mainMenu(dock: false)
        #expect(bare.items.count == 1)
        #expect(bare.items[0].submenu?.items.contains { $0.keyEquivalent == "w" } == true)
        #expect(bare.items[0].submenu?.items.contains { $0.keyEquivalent == "q" } == false)
    }
}
