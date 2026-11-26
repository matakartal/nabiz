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
        #expect(WhatsNew.items.contains { $0.id == "ai-chat" })
    }

    @Test func aiChatHasItsOwnShortcutAndTile() {
        #expect(Prefs.bool(Prefs.aiChatHotkey))
        #expect(HotKey.customizable.contains(.aiChat))
        let keys: [Int] = HotKey.Shortcut.allCases.filter { $0.window == nil }.map(\.key)
        #expect(keys.count == Set(keys).count)
        #expect(ToolKind.everyday.contains(.aiChat))
        #expect(ToolKind.everyday.count == 9)
    }
}
