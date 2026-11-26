// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import NaturalLanguage
import Observation

/// An AI command of the user's own: a name and a prompt, run on the selected or copied text ("Write a polite reply").
struct AICommand: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// `{text}` is replaced by the text; without it, the text goes at the end.
    var prompt: String

    var commandID: String { "aicmd:\(id.uuidString)" }

    func fullPrompt(_ text: String) -> String {
        let body = prompt.contains("{text}") ? prompt.replacingOccurrences(of: "{text}", with: text) : "\(prompt)\n\n<text>\n\(text)\n</text>"
        return body + "\n\nReply with the result only: no introduction, no notes, no quotes around it."
    }

    static var examples: [AICommand] { [
        AICommand(name: L("Kibar bir yanıt yaz", "Write a polite reply"),
                  prompt: "Write a short, warm and polite reply to the message below, in the same language as the message."),
        AICommand(name: L("Maddelere ayır", "Turn into bullet points"),
                  prompt: "Turn the text below into short bullet points. Keep its language."),
        AICommand(name: L("Daha resmi yap", "Make it more formal"),
                  prompt: "Rewrite the text below in a more formal, professional tone. Keep its language and meaning."),
    ] }
}

@MainActor
@Observable
final class AICommandStore {
    static let shared = AICommandStore()
    private static let key = "aiCommands"

    var commands: [AICommand] = [] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(commands), forKey: Self.key) }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([AICommand].self, from: data) { commands = saved }
    }
}

/// "çevir hello", "translate merhaba": which way to translate, from the text's own language.
enum TranslateQuery {
    /// The text after the keyword, or nil when the query isn't a translation.
    static func text(in query: String) -> String? {
        let words = ["çevir ", "cevir ", "translate ", "tercüme ", "tercume "]
        let lower = query.lowercased()
        guard let word = words.first(where: { lower.hasPrefix($0) }) else { return nil }
        let rest = String(query.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    /// Turkish text goes to English, anything else to Turkish.
    static func task(for text: String) -> AITextTask {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let turkishLetters = text.contains { "çğıöşüÇĞİÖŞÜ".contains($0) }
        return recognizer.dominantLanguage == .turkish || turkishLetters ? .toEnglish : .toTurkish
    }
}
