import Foundation

/// The short "New in this version" list the panel shows once, until it's closed.
/// Change `id` whenever the list changes, so people who closed the old one see the new one.
@MainActor
enum WhatsNew {
    static let id = "1.9-ai"

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
