// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation

/// The short "New in this version" list the panel shows once, until it's closed.
/// Change `id` whenever the list changes, so people who closed the old one see the new one.
@MainActor
enum WhatsNew {
    static let id = "1.11-review"

    struct Item: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
        let keys: String
        let open: @MainActor () -> Void
    }

    /// Not on a fresh install (the welcome window already introduces the app), and not once closed.
    static func shouldShow(seen: String, onboarded: Bool) -> Bool {
        onboarded && seen != id && !items.isEmpty
    }

    static var items: [Item] {
        [
            Item(id: "accounts", symbol: "person.2", title: L("Birden çok AI hesabı", "Several AI accounts"),
                 detail: L("Her hesap kendi limitiyle; menü çubuğu en az kalanı gösterir.",
                           "Each account with its own limits; the menu bar shows the one with least left."),
                 keys: "") { SettingsWindow.show(.aiLimits) },
            Item(id: "snippets", symbol: "text.insert", title: L("Her uygulamada parçacık", "Snippets in any app"),
                 detail: L("; ve kısa adı yaz, metin açılsın. Ayarlardan aç.", "Type ; and a keyword to expand it. Turn it on in Settings."),
                 keys: "") { SettingsWindow.show(.snippets) },
            Item(id: "chat", symbol: "sparkles", title: L("AI sohbette talimatlar ve sürümler", "Instructions and versions in AI chat"),
                 detail: L("Kendi talimatların, klasör talimatları; yeniden yazınca eski cevap ‹ 1/2 › kalır.",
                           "Your own and per-folder instructions; writing again keeps the old answer as ‹ 1/2 ›."),
                 keys: "") { SettingsWindow.show(.aiChat) },
            Item(id: "launcher", symbol: "magnifyingglass", title: L("Daha akıllı başlatıcı", "A smarter launcher"),
                 detail: L("gh ⇥ ile ara, seçtiklerini öğrenir, Sistem Ayarları sayfalarını bulur, \"not …\" not kaydeder.",
                           "gh ⇥ to search, learns what you pick, finds System Settings pages, \"note …\" saves a note."),
                 keys: "") { SettingsWindow.show(.launcher) },
            Item(id: "recordings", symbol: "film.stack", title: L("Kayıt listesi", "Your recordings"),
                 detail: L("Eski kayıtlar boyutlarıyla; eski olanları tek seferde temizle.",
                           "Past recordings with their sizes; clear out old ones at once."),
                 keys: "") { SettingsWindow.show(.screenshot) },
        ]
    }
}
