// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import UserNotifications

extension Notification.Name {
    /// An answer finished (object: the chat's id; userInfo "stopped", "failed").
    static let aiAnswerFinished = Notification.Name("nabiz.aiAnswerFinished")
}

/// "Claude answered": a notification when an answer arrives while you're in another app or another chat. One per
/// chat (a newer one replaces it); clicking it opens the chat.
@MainActor
final class AINotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AINotifications()
    private static let prefix = "ai-chat-"
    private var asked = false

    static func answered(_ conversation: AIConversation) {
        guard AIChatStore.persists, Prefs.bool(Prefs.aiNotify), let answer = conversation.lastAnswer else { return }
        shared.post(conversation, answer)
    }

    private func post(_ conversation: AIConversation, _ answer: AIMessage) {
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = self }
        if !asked {
            asked = true
            Notifier.shared.requestPermission(keepSetting: true)
        }
        let content = UNMutableNotificationContent()
        let engine = answer.engine ?? conversation.engine
        if let error = answer.error {
            content.title = L("\(engine.shortName) cevap veremedi", "\(engine.shortName) couldn't answer")
            content.body = conversation.title + " · " + error
        } else {
            content.title = conversation.title
            let plain = answer.text.replacingOccurrences(of: "[#*`>_|]", with: "", options: .regularExpression)
                .split(whereSeparator: \.isNewline).joined(separator: " ")
            content.body = "\(engine.shortName): " + String(plain.prefix(140))
        }
        content.sound = .default
        content.threadIdentifier = "ai-chat"
        let id = Self.prefix + conversation.id.uuidString
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// Opening the chat removes its notification.
    static func clear(_ id: UUID) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [prefix + id.uuidString])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        completionHandler()
        Task { @MainActor in
            if identifier.hasPrefix(Self.prefix), let id = UUID(uuidString: String(identifier.dropFirst(Self.prefix.count))),
               let chat = AIChatStore.shared.conversation(id) {
                AIChatWindow.show()
                AIChatWindow.state.select(chat)
            }
        }
    }
}
