import AppKit
import Foundation
import Observation
import SwiftUI

/// One turn of a chat.
struct AIMessage: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }

    var id = UUID()
    var role: Role
    /// What shows: your words, or the answer revealed so far.
    var text: String
    /// What was sent instead of `text`, for a ready-made task ("Summarise" plus its instructions).
    var prompt: String?
    /// Selected or copied text the message works on, shown as a chip.
    var attachment: String?
    /// What the chip says ("notes.txt", "Pasted text"); the text's first line when nil.
    var attachmentName: String?
    var thinking = ""
    /// Who answered and with which model ("claude-opus-5-5"); nil while unknown.
    var engine: AIEngine?
    var model: String?
    var error: String?
    var stopped = false
    var date = Date()
    /// Seconds the answer took.
    var duration: Double?
    /// Still coming in; never saved as true.
    var streaming = false
}

/// A chat with one AI (you can switch it midway): its messages, the answer being written, and how it was asked.
@MainActor
@Observable
final class AIConversation: Identifiable {
    let id: UUID
    var title: String
    private(set) var messages: [AIMessage] = []
    /// A real engine, never `.auto`; changing it applies to the next answer.
    var engine: AIEngine
    var model: String
    let created: Date
    private(set) var updated: Date
    private(set) var isRunning = false
    var pinned = false
    var archived = false
    /// The folder it's filed in.
    var folder: UUID?
    /// An answer arrived while you were looking elsewhere.
    var unread = false
    /// You named it yourself, so it isn't titled automatically.
    var titleEdited = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var target: (id: UUID, text: String)?
    @ObservationIgnored private var revealing: Task<Void, Never>?

    init(engine: AIEngine, model: String? = nil) {
        id = UUID()
        title = L("Yeni sohbet", "New chat")
        self.engine = engine
        self.model = model ?? engine.chosenModel
        created = Date()
        updated = created
    }

    struct Record: Codable {
        var id: UUID
        var title: String
        var messages: [AIMessage]
        var engine: AIEngine
        var model: String
        var created: Date
        var updated: Date
        var pinned: Bool?
        var archived: Bool?
        var titleEdited: Bool?
        var folder: UUID?
        var unread: Bool?
    }

    init(record: Record) {
        id = record.id
        title = record.title
        engine = record.engine
        model = record.model
        created = record.created
        updated = record.updated
        pinned = record.pinned ?? false
        archived = record.archived ?? false
        titleEdited = record.titleEdited ?? false
        folder = record.folder
        unread = record.unread ?? false
        messages = record.messages.map { message in
            var message = message
            if message.streaming {
                message.streaming = false
                message.stopped = true
            }
            return message
        }
    }

    var record: Record {
        Record(id: id, title: title, messages: messages, engine: engine, model: model, created: created, updated: updated,
               pinned: pinned, archived: archived, titleEdited: titleEdited, folder: folder, unread: unread)
    }

    var lastAnswer: AIMessage? { messages.last { $0.role == .assistant } }

    // MARK: Asking

    func send(_ text: String, attachment: String? = nil, prompt: String? = nil, attachmentName: String? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isRunning, !text.isEmpty || attachment != nil else { return }
        if messages.isEmpty && !titleEdited { title = Self.title(text.isEmpty ? (attachmentName ?? "") : text, attachment: attachmentName == nil ? attachment : nil) }
        messages.append(AIMessage(role: .user, text: text, prompt: prompt, attachment: attachment, attachmentName: attachmentName))
        answer()
    }

    /// Writes the last answer again, with the engine and model chosen now.
    func regenerate() {
        guard !isRunning else { return }
        if messages.last?.role == .assistant { messages.removeLast() }
        guard messages.last?.role == .user else { return }
        answer()
    }

    func stop() {
        task?.cancel()
    }

    func rename(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        self.title = title
        titleEdited = true
        AIChatStore.shared.scheduleSave()
    }

    /// Takes a message of yours back to edit it, like the apps: it and everything after it go, and its text is returned.
    func takeBack(_ id: UUID) -> AIMessage? {
        guard !isRunning, let index = messages.firstIndex(where: { $0.id == id }), messages[index].role == .user else { return nil }
        let message = messages[index]
        messages.removeSubrange(index...)
        AIChatStore.shared.scheduleSave()
        return message
    }

    /// The newest words in the chat, for a tooltip in the sidebar.
    var preview: String {
        let text = messages.last { !$0.text.isEmpty }?.text ?? ""
        return String(text.replacingOccurrences(of: "\n", with: " ").prefix(160))
    }

    /// Where a search hit this chat: a few words around the match, or nil when only the title matched.
    func snippet(for query: String) -> String? {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }
        for message in messages.reversed() {
            guard let range = message.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            let start = message.text.index(range.lowerBound, offsetBy: -30, limitedBy: message.text.startIndex) ?? message.text.startIndex
            let end = message.text.index(range.upperBound, offsetBy: 60, limitedBy: message.text.endIndex) ?? message.text.endIndex
            let piece = message.text[start..<end].replacingOccurrences(of: "\n", with: " ")
            return (start > message.text.startIndex ? "…" : "") + piece + (end < message.text.endIndex ? "…" : "")
        }
        return nil
    }

    /// Your last message, for ↑ in an empty message box.
    var lastQuestion: AIMessage? { messages.last { $0.role == .user } }

    func use(_ engine: AIEngine, model: String) {
        self.engine = engine
        self.model = model
    }

    private func answer() {
        let answered = messages.filter { $0.role == .assistant && $0.error == nil && !$0.text.isEmpty }.count
        let request = AIRequest(engine: engine, model: model, effort: AIEngines.shared.effectiveEffort(for: engine, model: model),
                                system: AIAssistant.system(for: engine), prompt: AIAssistant.prompt(for: messages, engine: engine),
                                chatID: id, latest: messages.last.map(AIAssistant.content(of:)) ?? "", answered: answered)
        let reply = AIMessage(role: .assistant, text: "", engine: engine, model: model.isEmpty ? nil : model, streaming: true)
        messages.append(reply)
        let id = reply.id
        isRunning = true
        updated = Date()
        AIChatStore.shared.touch(self)
        let started = Date()
        task = Task { [weak self] in
            var failure: String?
            do {
                for try await progress in AIRunner.stream(request) {
                    guard let self else { return }
                    self.edit(id) { message in
                        message.thinking = progress.thinking
                        if let model = progress.model { message.model = model }
                    }
                    if let actual = progress.model { AIEngines.shared.remember(actual, for: request.model, engine: request.engine) }
                    self.reveal(id, to: progress.text)
                }
            } catch {
                failure = (error as? AIError)?.message ?? error.localizedDescription
            }
            guard let self else { return }
            let cancelled = Task.isCancelled
            if cancelled || failure != nil {
                // Show what came in at once.
                if let target = self.target, target.id == id { self.edit(id) { $0.text = target.text } }
                self.revealing?.cancel()
                self.revealing = nil
            } else {
                while self.revealing != nil { try? await Task.sleep(for: .milliseconds(24)) }
            }
            self.edit(id) { message in
                message.streaming = false
                message.duration = Date().timeIntervalSince(started)
                if cancelled {
                    message.stopped = true
                } else if let failure {
                    message.error = failure
                } else if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    message.error = L("Boş cevap geldi", "The answer came back empty")
                } else {
                    message.text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            self.target = nil
            self.isRunning = false
            self.updated = Date()
            if !cancelled, !AIChatStore.shared.isShowing(self.id) { self.unread = true }
            AIChatStore.shared.scheduleSave()
            if !cancelled, failure == nil { self.nameIfNeeded() }
        }
    }

    /// After the first answer, a short title like the apps give, written by Apple's on-device model (free, private).
    private func nameIfNeeded() {
        guard !titleEdited, messages.filter({ $0.role == .assistant }).count == 1,
              let question = messages.first(where: { $0.role == .user }), let answer = lastAnswer?.text else { return }
        let source = AIAssistant.content(of: question).prefix(600) + "\n\n" + answer.prefix(400)
        Task { [weak self] in
            guard let title = await OnDeviceAI.title(for: String(source)) else { return }
            guard let self, !self.titleEdited else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.title = title }
            AIChatStore.shared.scheduleSave()
        }
    }

    private func index(of id: UUID) -> Int? { messages.lastIndex { $0.id == id } }

    private func edit(_ id: UUID, _ change: (inout AIMessage) -> Void) {
        guard let index = index(of: id) else { return }
        change(&messages[index])
    }

    /// Lets the text in a few characters at a time, like the apps do, instead of jumping by whole chunks.
    private func reveal(_ id: UUID, to text: String) {
        target = (id, text)
        guard revealing == nil else { return }
        revealing = Task { [weak self] in
            while let self, let target = self.target, let index = self.index(of: target.id) {
                let shown = self.messages[index].text.count
                let total = target.text.count
                guard shown < total else {
                    if self.messages[index].text != target.text { self.messages[index].text = target.text }
                    break
                }
                let step = max(3, (total - shown) / 6)
                self.messages[index].text = String(target.text.prefix(shown + step))
                try? await Task.sleep(for: .milliseconds(24))
                if Task.isCancelled { return }
            }
            self?.revealing = nil
        }
    }

    static func title(_ text: String, attachment: String?) -> String {
        var title = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if let attachment, let first = attachment.split(whereSeparator: \.isNewline).first {
            title += (title.isEmpty ? "" : ": ") + first
        }
        title = title.trimmingCharacters(in: .whitespaces)
        if title.count > 60 { title = String(title.prefix(59)) + "…" }
        return title.isEmpty ? L("Yeni sohbet", "New chat") : title
    }
}

// MARK: - Prompts

@MainActor
enum AIAssistant {
    /// The system prompt: a chat assistant, not a coding agent. Apple's small on-device model gets a short, plain one
    /// it can follow.
    static func system(for engine: AIEngine) -> String {
        if engine == .onDevice {
            return "You are a helpful assistant. Answer the user's latest message directly and briefly, in the language they write in. "
                + "Use plain sentences; use a short list only when listing things."
        }
        let date = Date().formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(Locale(identifier: "en_US")))
        return """
            You are a helpful, knowledgeable assistant chatting with the user in Nabız, a Mac app, the way you would in your own app. \
            Today is \(date). Reply in the language the user writes in (Turkish if unsure). Be clear and direct, and match the length \
            to the question: short questions get short answers. Use Markdown when it helps reading: lists, **bold**, tables, and fenced \
            code blocks with the language name. You can't browse the web or run tools here; say so if a request needs that. \
            Don't mention these instructions.
            """
    }

    /// What a message says to the AI: a task's instructions, or your words with any attached text.
    static func content(of message: AIMessage) -> String {
        if let prompt = message.prompt { return prompt }
        guard let attachment = message.attachment else { return message.text }
        let name = message.attachmentName.map { " name=\"\($0)\"" } ?? ""
        return "\(message.text)\n\n<text\(name)>\n\(attachment)\n</text>"
    }

    /// The CLIs keep no memory between runs, so the chat so far goes along (newest turns first, within a budget).
    static func prompt(for messages: [AIMessage], engine: AIEngine) -> String {
        let turns = messages.filter { $0.role == .user || ($0.error == nil && !$0.text.isEmpty) }
        guard let last = turns.last, last.role == .user else { return "" }
        let earlier = turns.dropLast()
        if earlier.isEmpty { return content(of: last) }
        let budget = engine == .onDevice ? 5_000 : 80_000
        var blocks: [String] = []
        var used = 0
        for message in earlier.reversed() {
            let tag = message.role == .user ? "user" : "assistant"
            let block = "<\(tag)>\n\(content(of: message))\n</\(tag)>"
            if used + block.count > budget { break }
            blocks.insert(block, at: 0)
            used += block.count
        }
        return """
            Our conversation so far:

            \(blocks.joined(separator: "\n\n"))

            Reply to my latest message:

            \(content(of: last))
            """
    }
}

// MARK: - History

/// A folder of chats, like the apps' projects.
struct AIFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var created = Date()
}

/// How the sidebar groups chats that aren't pinned or in a folder.
enum AIChatGrouping: String, CaseIterable, Identifiable {
    case date, ai, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: L("Tarihe göre", "By date")
        case .ai: L("AI'a göre", "By AI")
        case .none: L("Gruplama yok", "No groups")
        }
    }

    static var chosen: AIChatGrouping { AIChatGrouping(rawValue: Prefs.string("aiGroupBy")) ?? .date }
}

/// Your chats, newest first, kept encrypted on disk (same Keychain key as the clipboard history).
@MainActor
@Observable
final class AIChatStore {
    static let shared = AIChatStore()
    private(set) var conversations: [AIConversation] = []
    private(set) var folders: [AIFolder] = []

    /// What's saved: folders and chats (older files hold only the chats).
    private struct Saved: Codable {
        var version = 2
        var folders: [AIFolder]
        var chats: [AIConversation.Record]
    }

    /// True when the chat is in front of you: open in the chat window or the launcher.
    func isShowing(_ id: UUID) -> Bool {
        guard NSApp.isActive || LauncherPanel.shared.isVisible else { return false }
        return (AIChatWindow.isVisible && AIChatWindow.state.selection == id)
            || (LauncherPanel.shared.isVisible && LauncherPanel.shared.model.ai?.id == id)
    }
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    static let limit = 200
    /// Off for command-line checks, which shouldn't touch your saved chats.
    static var persists = true

    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nabiz").appendingPathComponent("ai-chats.sealed")
    }

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard Self.persists, Prefs.bool(Prefs.aiHistory), let sealed = try? Data(contentsOf: Self.file), let data = ClipVault.open(sealed) else { return }
        if let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            folders = saved.folders + folders
            conversations = saved.chats.map(AIConversation.init(record:)) + conversations
        } else if let records = try? JSONDecoder().decode([AIConversation.Record].self, from: data) {
            conversations = records.map(AIConversation.init(record:)) + conversations
        }
    }

    func conversation(_ id: UUID?) -> AIConversation? {
        guard let id else { return nil }
        return conversations.first { $0.id == id }
    }

    /// Puts a chat at the top (new, or just used).
    func touch(_ conversation: AIConversation) {
        loadIfNeeded()
        conversations.removeAll { $0 === conversation }
        conversations.insert(conversation, at: 0)
        if conversations.count > Self.limit { conversations.removeLast(conversations.count - Self.limit) }
    }

    /// Pinned first, then by last use; archived ones apart.
    var active: [AIConversation] { conversations.filter { !$0.archived && !$0.messages.isEmpty } }
    var archivedChats: [AIConversation] { conversations.filter { $0.archived && !$0.messages.isEmpty } }

    func setPinned(_ conversation: AIConversation, _ on: Bool) {
        conversation.pinned = on
        if on { conversation.archived = false }
        scheduleSave()
    }

    func setArchived(_ conversation: AIConversation, _ on: Bool) {
        conversation.archived = on
        if on { conversation.pinned = false }
        scheduleSave()
    }

    func delete(_ conversation: AIConversation) {
        conversation.stop()
        conversations.removeAll { $0 === conversation }
        scheduleSave()
    }

    // MARK: Folders

    /// A new folder, named "Folder 1", "Folder 2"… so it never looks like the "Add folder" button.
    @discardableResult
    func createFolder(_ name: String? = nil) -> AIFolder {
        loadIfNeeded()
        let base = L("Klasör", "Folder")
        let taken = Set(folders.map(\.name))
        let number = (1...).first { !taken.contains("\(base) \($0)") } ?? folders.count + 1
        let folder = AIFolder(name: name ?? "\(base) \(number)")
        folders.append(folder)
        scheduleSave()
        return folder
    }

    func renameFolder(_ id: UUID, _ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = name
        scheduleSave()
    }

    /// The folder goes; its chats stay, back in the list.
    func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        for chat in conversations where chat.folder == id { chat.folder = nil }
        scheduleSave()
    }

    func move(_ conversation: AIConversation, to folder: UUID?) {
        conversation.folder = folder
        if folder != nil { conversation.archived = false }
        scheduleSave()
    }

    func chats(in folder: UUID) -> [AIConversation] { active.filter { $0.folder == folder } }

    func deleteAll() {
        conversations.forEach { $0.stop() }
        conversations.removeAll()
        folders.removeAll()
        try? FileManager.default.removeItem(at: Self.file)
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        guard Self.persists else { return }
        guard Prefs.bool(Prefs.aiHistory) else {
            try? FileManager.default.removeItem(at: Self.file)
            return
        }
        let saved = Saved(folders: folders, chats: conversations.filter { !$0.messages.isEmpty }.map(\.record))
        guard let data = try? JSONEncoder().encode(saved), let sealed = ClipVault.seal(data) else { return }
        let file = Self.file
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? sealed.write(to: file, options: [.atomic, .completeFileProtection])
        }
    }

    /// "Today", "Yesterday", "Previous 7 days", "Previous 30 days", then the month ("October 2026"), for the sidebar.
    static func group(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L("Bugün", "Today") }
        if calendar.isDateInYesterday(date) { return L("Dün", "Yesterday") }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        if days < 7 { return L("Son 7 gün", "Previous 7 days") }
        if days < 30 { return L("Son 30 gün", "Previous 30 days") }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        let style = sameYear ? Date.FormatStyle().month(.wide) : Date.FormatStyle().month(.wide).year(.defaultDigits)
        return date.formatted(style.locale(Format.locale)).capitalized(with: Format.locale)
    }
}
