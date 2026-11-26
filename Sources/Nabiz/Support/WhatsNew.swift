// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import Foundation

/// The short "New in this version" list the panel shows once, until it's closed.
/// Change `id` whenever the list changes, so people who closed the old one see the new one.
@MainActor
enum WhatsNew {
    static let id = "1.10-weather"

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
            Item(id: "weather", symbol: "cloud.sun", title: L("Hava durumu", "Weather"),
                 detail: L("Şehrinde şu an, yağmur ve önümüzdeki günler; konum izni istemez.",
                           "Now, rain on the way and the coming days for your city; no location permission."),
                 keys: "") { SettingsWindow.show(.weather) },
            Item(id: "web", symbol: "globe", title: L("AI sohbette web araması", "Web search in AI chat"),
                 detail: L("Claude, Codex ve Grok güncel bilgiyi kaynağıyla bulur.", "Claude, Codex and Grok find current facts, with sources."),
                 keys: Prefs.bool(Prefs.aiChatHotkey) ? HotKey.label(.aiChat) : "") { AIChatWindow.show() },
            Item(id: "dock", symbol: "dock.rectangle", title: L("Dock'ta göster", "Show in Dock"),
                 detail: L("İstersen Nabız Dock'ta ve ⌘⇥'de de durur.", "Optionally, Nabız sits in the Dock and ⌘⇥ too."),
                 keys: "") { SettingsWindow.show(.general) },
            Item(id: "ai-chat", symbol: "sparkles", title: L("AI sohbet", "AI chat"),
                 detail: L("Claude, Codex, Gemini, Grok ya da Apple'ın ücretsiz modeliyle, kendi aboneliklerinle.",
                           "Claude, Codex, Gemini, Grok or Apple's free model, on your own subscriptions."),
                 keys: Prefs.bool(Prefs.aiChatHotkey) ? HotKey.label(.aiChat) : "") { AIChatWindow.show() },
            Item(id: "shot", symbol: "camera.viewfinder", title: L("Ekran görüntüsü ve düzenleme", "Screenshots with markup"),
                 detail: L("Ok, kutu, yazı, numara, bulanıklaştırma ve çerçeve.", "Arrows, boxes, text, steps, blur and a frame."),
                 keys: Prefs.bool(Prefs.shotHotkey) ? HotKey.label(.screenshot) : "") { Capture.run(.area) },
            Item(id: "dictation", symbol: "mic", title: L("Dikte", "Dictation"),
                 detail: L("Konuş, imlecin olduğu yere yazılsın.", "Speak, and it's typed where the cursor is."),
                 keys: "") { SettingsWindow.show(.ai) },
            Item(id: "calendar", symbol: "calendar", title: L("Takvim", "Calendar"),
                 detail: L("Bugünkü toplantılar panelde, tek tıkla katıl.", "Today's meetings in the panel, one click to join."),
                 keys: "") { SettingsWindow.show(.calendar) },
        ]
    }
}
