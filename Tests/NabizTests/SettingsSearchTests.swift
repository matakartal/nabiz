// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

/// Settings search finds single settings, not only pages, in either language, without accents and with a typo.
@MainActor
@Suite("Settings search")
struct SettingsSearchTests {
    init() {
        Prefs.registerDefaults()
        UserDefaults.standard.set("en", forKey: Prefs.language)
    }

    private func top(_ query: String) -> SettingsTarget? { SettingsIndex.search(query).first?.target }

    @Test func findsSettingsAcrossLanguagesAndAccents() {
        #expect(SettingsIndex.search("karanlik").contains { $0.target.anchor == "appearance.theme" })
        #expect(SettingsIndex.search("dark mode").contains { $0.target.anchor == "appearance.theme" })
        #expect(SettingsIndex.search("şifre").contains { $0.target.anchor == "clipboard.excluded" })
        #expect(top("yedek")?.page == .maintenance)
        #expect(top("btc") != nil)
        #expect(SettingsIndex.search("dock").contains { $0.target.anchor == "general.language" && $0.title == "Show in Dock" })
    }

    @Test func forgivesOneTypo() {
        #expect(SettingsIndex.search("pomodro").contains { $0.target.page == .focus })
        #expect(SettingsIndex.search("kısyaol").contains { $0.target.page == .shortcuts })
        #expect(SettingsIndex.typo("dikte", "dikde"))
        #expect(!SettingsIndex.typo("pil", "pil"))
    }

    @Test func everyWordHasToMatch() {
        #expect(SettingsIndex.search("pano temizle").first?.target.anchor == "clipboard.clear")
        #expect(SettingsIndex.search("zzzz").isEmpty)
        #expect(SettingsIndex.search("   ").isEmpty)
    }

    @Test func everyPageIsInTheSidebarOnce() {
        let listed = SettingsGroup.allCases.flatMap(\.pages)
        #expect(Set(listed) == Set(SettingsPage.allCases))
        #expect(listed.count == SettingsPage.allCases.count)
        #expect(SettingsPage.allCases.allSatisfy { $0 == .about || !$0.subtitle.isEmpty })
    }
}
