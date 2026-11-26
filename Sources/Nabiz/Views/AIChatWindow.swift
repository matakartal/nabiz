// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - Window

/// The AI chat window, shaped like the AI apps: one bar along the top level with the window buttons (sidebar and
/// new-chat buttons on the left, the chat's title and menu on the right), your chats on the left (pinned, folders,
/// by date or by AI), the conversation on the right and the message box at the bottom.
@MainActor
enum AIChatWindow {
    private static var window: NSWindow?
    static let state = AIChatState()

    static var isVisible: Bool { window?.isVisible == true }

    /// The shortcut: opens the window, or closes it when it is already in front.
    static func toggle() {
        if let window, window.isVisible, window.isKeyWindow { window.performClose(nil) } else { show() }
    }

    /// Opens a chat, or a new one with nothing given.
    static func show(_ conversation: AIConversation? = nil) {
        AIEngines.shared.refreshIfNeeded()
        AIChatStore.shared.loadIfNeeded()
        if let conversation {
            AIChatStore.shared.touch(conversation)
            state.select(conversation)
        } else if !isVisible {
            state.newChat()
        }
        if window == nil {
            let controller = NSHostingController(rootView: AIChatView(state: state))
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            WindowChrome.apply(window)
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 1000, height: 700))
            window.setFrameAutosaveName("NabizAIChat")
            if window.frame.origin == .zero { window.center() }
            self.window = window
        }
        window?.title = L("Nabız · AI", "Nabız · AI")
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            NSRunningApplication.current.activate(from: front, options: [])
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        state.conversation?.unread = false
        state.focusComposer += 1
    }
}

/// Text you add to a message: a file, a long paste, the clipboard.
struct AIAttachment: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var text: String
    var symbol = "doc.plaintext"
    /// An image's file name in `AIImages.folder`; `text` is then what was read from it.
    var image: String?
}

@MainActor
@Observable
final class AIChatState {
    var selection: UUID? {
        didSet {
            guard selection != oldValue else { return }
            // Leaving a chat mid-edit puts its messages back; each chat keeps its own half-written message.
            cancelEdit()
            finding = false
            sideDraft = ""
            drafts[oldValue] = Draft(text: draft, attachments: attachments)
            let next = drafts.removeValue(forKey: selection) ?? Draft()
            draft = next.text
            attachments = next.attachments
            if let chat = conversation, chat.unread { chat.unread = false; AIChatStore.shared.scheduleSave() }
            if let selection { AINotifications.clear(selection) }
        }
    }
    /// Messages written while an answer was still coming, sent one by one as each answer finishes.
    var queued: [UUID: [Queued]] = [:]
    @ObservationIgnored private var finished: NSObjectProtocol?

    struct Queued: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var attachment: String?
        var attachmentName: String?
        var images: [String] = []
    }

    init() {
        finished = NotificationCenter.default.addObserver(forName: .aiAnswerFinished, object: nil, queue: .main) { [weak self] note in
            guard let id = note.object as? UUID else { return }
            let paused = (note.userInfo?["stopped"] as? Bool ?? false) || (note.userInfo?["failed"] as? Bool ?? false)
            MainActor.assumeIsolated {
                guard !paused, let self else { return }
                if self.queued[id]?.isEmpty ?? true { self.suggestNext(for: id) }
                self.sendQueued(in: id)
            }
        }
    }

    /// The next waiting message goes out (after a stop or an error the queue waits for you).
    func sendQueued(in chat: UUID) {
        guard var list = queued[chat], !list.isEmpty, let conversation = AIChatStore.shared.conversation(chat),
              !conversation.isRunning else { return }
        let next = list.removeFirst()
        queued[chat] = list.isEmpty ? nil : list
        conversation.send(next.text, attachment: next.attachment, attachmentName: next.attachmentName, images: next.images)
    }

    /// Stops the answer being written and sends this waiting message now.
    func sendNow(_ item: Queued) {
        guard let conversation, var list = queued[conversation.id], let index = list.firstIndex(of: item) else { return }
        list.remove(at: index)
        list.insert(item, at: 0)
        queued[conversation.id] = list
        if conversation.isRunning { conversation.stop() } else { sendQueued(in: conversation.id) }
        // A stop pauses the queue, so this one goes out by hand once the answer has ended.
        Task { @MainActor in
            for _ in 0..<100 where conversation.isRunning { try? await Task.sleep(for: .milliseconds(30)) }
            sendQueued(in: conversation.id)
        }
    }

    /// Back into the box to change it.
    func editQueued(_ item: Queued) {
        guard let conversation else { return }
        queued[conversation.id]?.removeAll { $0 == item }
        if queued[conversation.id]?.isEmpty == true { queued[conversation.id] = nil }
        draft = item.text
        focusComposer += 1
    }

    func removeQueued(_ item: Queued) {
        guard let conversation else { return }
        queued[conversation.id]?.removeAll { $0 == item }
        if queued[conversation.id]?.isEmpty == true { queued[conversation.id] = nil }
        AIImages.remove(item.images)
    }

    /// The grey "what you might say next" in the empty box, by chat (Apple's on-device model writes it; Tab takes it).
    var suggestions: [UUID: String] = [:]

    func suggestNext(for chat: UUID) {
        guard Prefs.bool(Prefs.aiSuggest), let conversation = AIChatStore.shared.conversation(chat),
              let answer = conversation.lastAnswer, answer.error == nil, !answer.text.isEmpty,
              let question = conversation.lastQuestion else { return }
        Task { @MainActor in
            guard let next = await OnDeviceAI.suggestion(question: AIAssistant.content(of: question), answer: answer.text),
                  conversation.lastAnswer?.id == answer.id else { return }
            suggestions[chat] = next
        }
    }

    /// Side chats, one per main chat: questions on the side that see the main chat but don't go in it.
    var sideChats: [UUID: AIConversation] = [:]
    var sideOpen = false
    var sideDraft = ""

    var side: AIConversation? { selection.flatMap { sideChats[$0] } }

    func toggleSide() {
        guard conversation != nil else { return }
        withAnimation(.easeOut(duration: 0.2)) { sideOpen.toggle() }
    }

    func sendSide() {
        let text = sideDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let main = conversation else { return }
        let chat: AIConversation
        if let existing = sideChats[main.id] {
            guard !existing.isRunning else { return }
            chat = existing
        } else {
            chat = AIConversation(engine: main.engine, model: main.model)
            sideChats[main.id] = chat
        }
        // The main chat as it is now, each time (it may have moved on).
        chat.sideContext = Self.background(of: main)
        sideDraft = ""
        chat.send(text)
    }

    func resetSide() {
        guard let id = selection else { return }
        sideChats[id]?.stop()
        sideChats[id] = nil
    }

    /// The main chat for a side chat: its summary and its newest messages, within a budget.
    static func background(of chat: AIConversation) -> String {
        var blocks: [String] = []
        var used = 0
        for message in chat.promptMessages.reversed() where message.error == nil && !message.text.isEmpty {
            let tag = message.role == .user ? "user" : "assistant"
            let block = "<\(tag)>\n\(AIAssistant.content(of: message))\n</\(tag)>"
            if used + block.count > 40_000 { break }
            blocks.insert(block, at: 0)
            used += block.count
        }
        let summary = chat.summary.map { "<summary_of_earlier_part>\n\($0)\n</summary_of_earlier_part>\n\n" } ?? ""
        return "<main_chat title=\"\(chat.title)\">\n\(summary)\(blocks.joined(separator: "\n\n"))\n</main_chat>"
    }

    /// Quotes text into the box (as a Markdown quote), to ask about it.
    func quote(_ text: String) {
        let quoted = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
        guard !quoted.isEmpty else { return }
        draft = (draft.isEmpty ? "" : draft.trimmingCharacters(in: .newlines) + "\n\n") + quoted + "\n\n"
        focusComposer += 1
    }

    /// ⇧⌘' or the quote button: what you selected in the chat; the whole answer when nothing is selected.
    func quoteSelection(fallback: String? = nil) {
        if let selected = TranscriptSelection.read(), !selected.isEmpty { quote(selected) } else if let fallback { quote(fallback) }
    }

    /// ⌘1…⌘9: the chats in the sidebar's order (pinned first).
    func jump(to number: Int) {
        let store = AIChatStore.shared
        let list = store.active.filter(\.pinned) + store.active.filter { !$0.pinned }
        guard list.indices.contains(number - 1) else { return }
        select(list[number - 1])
    }

    /// A new chat from this point of the open one.
    func fork(at message: AIMessage) {
        guard let conversation, let branch = conversation.fork(at: message.id) else { return }
        select(branch)
    }
    var draft = ""
    var attachments: [AIAttachment] = []
    /// What you'd written in other chats (nil: the new chat).
    private var drafts: [UUID?: Draft] = [:]
    /// A message of yours being edited: what left the chat, to put back if you cancel.
    var editing: (chat: UUID, removed: [AIMessage], draft: Draft)?
    /// Shows the drop outline while a file is dragged over the window.
    var dropping = false
    /// Find in the open chat (⌘F): the words, the messages that have them, and the one shown.
    var finding = false {
        didSet { if !finding { findQuery = ""; findMatches = []; findIndex = 0 } }
    }
    var findQuery = ""
    var findMatches: [UUID] = []
    var findIndex = 0
    /// Bumped to put the cursor in the find field.
    var focusFind = 0
    /// Bumped to put the cursor in the sidebar search (⌘K).
    var focusSearch = 0

    var findTarget: UUID? { finding && findMatches.indices.contains(findIndex) ? findMatches[findIndex] : nil }

    func startFind() {
        finding = true
        focusFind += 1
    }

    /// Looks again (new words, or new messages); starts at the newest match, since you're usually at the bottom.
    func updateFind() {
        let query = findQuery.trimmingCharacters(in: .whitespaces)
        guard let conversation, !query.isEmpty else { findMatches = []; findIndex = 0; return }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        findMatches = conversation.messages.filter { message in
            message.text.range(of: query, options: options) != nil || message.attachment?.range(of: query, options: options) != nil
        }.map(\.id)
        findIndex = max(0, findMatches.count - 1)
    }

    /// -1: the match above, 1: the one below (wrapping around).
    func findStep(_ by: Int) {
        guard !findMatches.isEmpty else { return }
        findIndex = (findIndex + by + findMatches.count) % findMatches.count
    }

    /// ⌘⇧C: the newest answer to the clipboard.
    func copyLastAnswer() {
        guard let text = conversation?.lastAnswer?.text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Monitor.panelActions.flash(L("Son cevap kopyalandı", "Last answer copied"))
    }

    struct Draft {
        var text = ""
        var attachments: [AIAttachment] = []
    }
    var query = ""
    /// For a chat not started yet.
    var engine: AIEngine = .onDevice
    var model = ""
    /// A new chat started from a folder goes into it.
    var newChatFolder: UUID?
    /// Bumped to put the cursor in the message box.
    var focusComposer = 0
    var renaming: UUID?
    var renamingFolder: UUID?
    var showArchive = false
    var pendingDelete: AIConversation?
    var pendingFolderDelete: AIFolder?

    var conversation: AIConversation? { AIChatStore.shared.conversation(selection) }

    func newChat(in folder: UUID? = nil) {
        selection = nil
        newChatFolder = folder
        engine = AIEngines.shared.resolve(AIEngine.chosen) ?? .onDevice
        model = engine.chosenModel
        focusComposer += 1
    }

    func select(_ conversation: AIConversation) {
        if conversation.archived { showArchive = true }
        selection = conversation.id
        focusComposer += 1
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    /// Sends what's in the box (or the given text) to the open chat, starting one if needed.
    func send(_ text: String? = nil, attachment: String? = nil, prompt: String? = nil, attachmentName: String? = nil) {
        let fromBox = text == nil
        let text = text ?? draft
        var attachment = attachment
        var attachmentName = attachmentName
        let images = fromBox ? attachments.compactMap(\.image) : []
        if fromBox, !attachments.isEmpty {
            attachment = attachments.count == 1 ? attachments[0].text
                : attachments.map { "<\($0.name)>\n\($0.text)\n</\($0.name)>" }.joined(separator: "\n\n")
            attachmentName = attachments.map(\.name).joined(separator: ", ")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil else { return }
        if fromBox {
            draft = ""
            attachments = []
        }
        editing = nil
        if let selection { suggestions[selection] = nil }
        let conversation: AIConversation
        if let current = self.conversation {
            conversation = current
        } else {
            conversation = AIConversation(engine: engine, model: model)
            conversation.folder = newChatFolder
            AIChatStore.shared.touch(conversation)
            selection = conversation.id
        }
        guard conversation.isRunning else {
            conversation.send(text, attachment: attachment, prompt: prompt, attachmentName: attachmentName, images: images)
            return
        }
        // Sent while it writes: it waits its turn, and goes out when this answer is done ("Send now" stops it instead).
        queued[conversation.id, default: []].append(Queued(text: text, attachment: attachment, attachmentName: attachmentName, images: images))
    }

    /// Puts a message of yours back in the box to change and send again.
    /// Until you send, the edit can be cancelled (esc, or "Cancel" over the box) and the chat comes back as it was.
    func edit(_ message: AIMessage) {
        cancelEdit()
        guard let conversation, let removed = conversation.takeBack(message.id), let taken = removed.first else { return }
        editing = (conversation.id, removed, Draft(text: draft, attachments: attachments))
        draft = taken.text
        if let images = taken.images, !images.isEmpty {
            // Images come back as images; their text goes along again when sent.
            let names = taken.attachmentName?.components(separatedBy: ", ") ?? []
            attachments = images.enumerated().map { index, image in
                AIAttachment(name: names.indices.contains(index) ? names[index] : L("Görsel", "Image"),
                             text: index == 0 ? (taken.attachment ?? "") : "", symbol: "photo", image: image)
            }
        } else {
            attachments = taken.attachment.map { [AIAttachment(name: taken.attachmentName ?? L("Ek", "Attachment"), text: $0)] } ?? []
        }
        focusComposer += 1
    }

    func escape() {
        if finding { finding = false } else if let conversation, conversation.isRunning { conversation.stop() } else { cancelEdit() }
    }

    func cancelEdit() {
        guard let editing else { return }
        self.editing = nil
        AIChatStore.shared.conversation(editing.chat)?.putBack(editing.removed)
        if selection == editing.chat {
            draft = editing.draft.text
            attachments = editing.draft.attachments
        }
    }

    /// Everything attached together stays under this, so a question never gets too big for the AI.
    static let attachmentLimit = 400_000

    func attach(file url: URL) {
        let name = url.lastPathComponent
        if AIImages.isImage(url) {
            attach(image: NSImage(contentsOf: url), name: name)
            return
        }
        let used = attachments.reduce(0) { $0 + $1.text.utf8.count }
        guard let text = Self.readText(url) else {
            Monitor.panelActions.flash(L("\(name) eklenemiyor; metin, kod, PDF ve görsel eklenebilir",
                                         "\(name) can't be attached; text, code, PDF and image files can"))
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Monitor.panelActions.flash(L("\(name) boş", "\(name) is empty"))
            return
        }
        guard used + text.utf8.count <= Self.attachmentLimit else {
            Monitor.panelActions.flash(L("\(name) çok büyük (en fazla 400 KB metin)", "\(name) is too big (400 KB of text at most)"))
            return
        }
        attachments.append(AIAttachment(name: name, text: text, symbol: url.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "doc.plaintext"))
    }

    /// An image goes in at once; the text in it is read on this Mac meanwhile (for the AIs that can't see images).
    func attach(image: NSImage?, name: String) {
        guard let image, let stored = AIImages.store(image) else {
            Monitor.panelActions.flash(L("\(name) açılamadı", "Couldn't open \(name)"))
            return
        }
        let attachment = AIAttachment(name: name, text: AIImages.describe(""), symbol: "photo", image: stored)
        attachments.append(attachment)
        Task { @MainActor in
            let text = await AIImages.text(in: stored)
            if let index = attachments.firstIndex(where: { $0.id == attachment.id }) { attachments[index].text = AIImages.describe(text) }
        }
    }

    /// A file's text: a PDF's words, or a text file in UTF-8 (or Latin-1 when it has no zero bytes). Nil for anything else.
    static func readText(_ url: URL) -> String? {
        if url.pathExtension.lowercased() == "pdf" {
            return PDFDocument(url: url)?.string
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count <= 4_000_000 else { return nil }
        if data.contains(0) { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    func archive(_ conversation: AIConversation) {
        let archiving = !conversation.archived
        if archiving && selection == conversation.id { newChat() }
        withAnimation(.easeOut(duration: 0.2)) { AIChatStore.shared.setArchived(conversation, archiving) }
    }

    func newFolder(moving conversation: AIConversation? = nil) {
        let folder = AIChatStore.shared.createFolder()
        if let conversation { AIChatStore.shared.move(conversation, to: folder.id) }
        showArchive = false
        query = ""
        renamingFolder = folder.id
    }

    /// The whole chat as Markdown, for copying out.
    static func markdown(_ conversation: AIConversation) -> String {
        var lines = ["# \(conversation.title)", ""]
        for message in conversation.messages where !(message.role == .assistant && message.text.isEmpty) {
            if message.role == .user {
                lines.append("**\(L("Sen", "You")):** \(message.text)")
                if let name = message.attachmentName { lines.append("_\(L("Ek", "Attached")): \(name)_") }
            } else {
                lines.append("**\(AIEngines.shared.displayName(message.model ?? "", engine: message.engine ?? conversation.engine)):**")
                lines.append(message.text)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

struct AIChatView: View {
    @Bindable var state: AIChatState
    @AppStorage("aiSidebarVisible") private var sidebarVisible = true
    @AppStorage("aiSidebarWidth") private var sidebarWidth = 260.0
    private let store = AIChatStore.shared

    var body: some View {
        UnifiedSplitView(sidebarVisible: $sidebarVisible, sidebarWidth: $sidebarWidth) {
            AIChatSidebar(state: state)
        } detail: {
            AIChatDetail(state: state)
        } sidebarBar: {
            BarButton(symbol: "sidebar.left", help: L("Kenar çubuğu (⌃⌘S)", "Sidebar (⌃⌘S)")) { toggleSidebar() }
            BarButton(symbol: "square.and.pencil", help: L("Yeni sohbet (⌘N)", "New chat (⌘N)")) { state.newChat() }
        } detailBar: {
            AIChatTitleBar(state: state)
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(MenuMaterial().ignoresSafeArea())
        .appearanceRoot(opaqueFill: Theme.surface)
        .background {
            Group {
                Button("") { state.newChat() }.keyboardShortcut("n", modifiers: .command)
                Button("") { toggleSidebar() }.keyboardShortcut("s", modifiers: [.command, .control])
                Button("") { state.newFolder() }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("") { if state.conversation != nil { state.startFind() } }.keyboardShortcut("f", modifiers: .command)
                Button("") { state.findStep(1) }.keyboardShortcut("g", modifiers: .command)
                Button("") { state.findStep(-1) }.keyboardShortcut("g", modifiers: [.command, .shift])
                Button("") { state.copyLastAnswer() }.keyboardShortcut("c", modifiers: [.command, .shift])
                Button("") { state.toggleSide() }.keyboardShortcut("s", modifiers: [.command, .option])
                Button("") { state.focusSearch += 1 }.keyboardShortcut("k", modifiers: .command)
                Button("") { state.quoteSelection() }.keyboardShortcut("'", modifiers: [.command, .shift])
                ForEach(1..<10) { number in
                    Button("") { state.jump(to: number) }.keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                }
                Button("") { if let chat = state.conversation { state.pendingDelete = chat } }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }
            .hidden()
        }
        .confirmationDialog(L("Sohbet silinsin mi?", "Delete this chat?"), isPresented: Binding(
            get: { state.pendingDelete != nil }, set: { if !$0 { state.pendingDelete = nil } })) {
            Button(L("Sil", "Delete"), role: .destructive) {
                if let chat = state.pendingDelete {
                    if state.selection == chat.id { state.newChat() }
                    store.delete(chat)
                }
                state.pendingDelete = nil
            }
        } message: {
            Text(L("\"\(state.pendingDelete?.title ?? "")\" kalıcı olarak silinir. Saklamak istersen arşivle.",
                   "\"\(state.pendingDelete?.title ?? "")\" will be deleted for good. Archive it to keep it."))
        }
        .confirmationDialog(L("Klasör silinsin mi?", "Delete this folder?"), isPresented: Binding(
            get: { state.pendingFolderDelete != nil }, set: { if !$0 { state.pendingFolderDelete = nil } })) {
            Button(L("Klasörü sil", "Delete folder"), role: .destructive) {
                if let folder = state.pendingFolderDelete { withAnimation(.easeOut(duration: 0.2)) { store.deleteFolder(folder.id) } }
                state.pendingFolderDelete = nil
            }
        } message: {
            Text(L("Klasör gider, içindeki sohbetler listede kalır.", "The folder goes; its chats stay in the list."))
        }
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.22)) { sidebarVisible.toggle() }
    }
}

// MARK: - Title bar

/// The chat's place and name, Claude-style: "Folder / Title ⌄" opens the chat's menu; click the title to rename.
private struct AIChatTitleBar: View {
    @Bindable var state: AIChatState
    @State private var name = ""
    @FocusState private var editing: Bool

    var body: some View {
        let conversation = state.conversation
        HStack(spacing: Theme.Spacing.s) {
            if let folderID = conversation?.folder ?? (conversation == nil ? state.newChatFolder : nil),
               let folder = AIChatStore.shared.folders.first(where: { $0.id == folderID }) {
                Label(folder.name, systemImage: "folder")
                    .font(Theme.body).foregroundStyle(Theme.textMuted).lineLimit(1)
                Text(verbatim: "/").font(Theme.body).foregroundStyle(Theme.textMuted.opacity(0.6))
            }
            if let conversation, state.renaming == conversation.id {
                InlineRenameField(text: $name, font: Theme.nsFont(size: 13, weight: .semibold),
                                  commit: { commit(conversation) }, cancel: { state.renaming = nil })
                    .framed()
                    .frame(maxWidth: 360)
                    .onAppear { name = conversation.title }
            } else if let conversation, !conversation.messages.isEmpty {
                Menu {
                    AIChatActions(conversation: conversation, state: state)
                } label: {
                    Text(verbatim: conversation.title).font(Theme.bodyStrong).lineLimit(1).foregroundStyle(Theme.text)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
                .tint(Theme.text)
                .fixedSize()
                .contentTransition(.opacity)
                .help(L("Sohbet menüsü", "Chat menu"))
            } else {
                Text(L("Yeni sohbet", "New chat")).font(Theme.bodyStrong).foregroundStyle(Theme.text)
            }
            Spacer(minLength: 0)
            // Like Claude's top right: share, pin and the chat's menu.
            if let conversation, !conversation.messages.isEmpty {
                HStack(spacing: BarButton.spacing) {
                    if conversation.isRunning {
                        AIBrandMark(engine: conversation.engine, size: 14, animating: true)
                            .frame(width: BarButton.size.width, height: BarButton.size.height)
                            .help(L("\(conversation.engine.shortName) yazıyor", "\(conversation.engine.shortName) is writing"))
                    }
                    BarButton(symbol: "bubble.left.and.text.bubble.right", help: L("Yan sohbet (⌥⌘S)", "Side chat (⌥⌘S)"),
                              active: state.sideOpen) { state.toggleSide() }
                    BarMenu(symbol: "square.and.arrow.up", help: L("Paylaş", "Share")) { ShareActions(conversation: conversation) }
                    BarButton(symbol: conversation.pinned ? "pin.fill" : "pin",
                              help: conversation.pinned ? L("Sabitlemeyi kaldır", "Unpin") : L("Sabitle", "Pin"), active: conversation.pinned) {
                        withAnimation(.easeOut(duration: 0.2)) { AIChatStore.shared.setPinned(conversation, !conversation.pinned) }
                    }
                    BarMenu(symbol: "ellipsis", help: L("Daha fazla", "More")) { AIChatActions(conversation: conversation, state: state) }
                }
            }
        }
    }

    private func commit(_ conversation: AIConversation) {
        conversation.rename(name)
        state.renaming = nil
    }
}

/// Copy the chat, save it as a note or to a Markdown file.
private struct ShareActions: View {
    let conversation: AIConversation

    var body: some View {
        let markdown = AIChatState.markdown(conversation)
        Button(L("Markdown olarak kopyala", "Copy as Markdown"), systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(markdown, forType: .string)
            Monitor.panelActions.flash(L("Sohbet kopyalandı", "Chat copied"))
        }
        if let answer = conversation.lastAnswer?.text, !answer.isEmpty {
            Button(L("Son cevabı kopyala", "Copy the last answer"), systemImage: "text.quote") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(answer, forType: .string)
            }
        }
        Divider()
        Button(L("Not olarak kaydet", "Save as note"), systemImage: "note.text.badge.plus") {
            if Prefs.string(Prefs.notesApp) == "apple" { AppleNotes.create(markdown) } else { NoteWindow.show(NoteStore.shared.create(markdown)) }
        }
        Button(L("Dosyaya kaydet…", "Save to a file…"), systemImage: "square.and.arrow.down") {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = conversation.title.replacingOccurrences(of: "/", with: "-") + ".md"
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Sidebar

/// Your chats: search, then pinned, folders (drop chats on them), and the rest by date, by AI or in one list; the
/// archive at the bottom with how to group. Every section folds; rows show pin, archive and ⋯ on hover, a dot when
/// an answer arrived while you were away, and where a search matched.
private struct AIChatSidebar: View {
    @Bindable var state: AIChatState
    @AppStorage("aiGroupBy") private var grouping = AIChatGrouping.date.rawValue
    @AppStorage("aiCollapsed") private var collapsed = ""
    private let store = AIChatStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSearchField(text: $state.query, focusTrigger: state.focusSearch) {}
                .padding(.horizontal, Theme.sidebarInset)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xs)
            if state.showArchive {
                Button { withAnimation(.easeOut(duration: 0.2)) { state.showArchive = false } } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "chevron.left")
                        Text(L("Arşiv", "Archive")).font(Theme.bodyStrong)
                        Spacer()
                    }
                    .foregroundStyle(Theme.text)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.sidebarInset + Theme.Spacing.s)
                .padding(.vertical, Theme.Spacing.xs)
            }
            list
            footer
        }
    }

    private var searching: Bool { !state.query.trimmingCharacters(in: .whitespaces).isEmpty }

    private func matches(_ chat: AIConversation) -> Bool {
        let query = state.query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || Fuzzy.contains(query, chat.title) || chat.messages.contains { Fuzzy.contains(query, $0.text) }
    }

    private func expanded(_ key: String) -> Binding<Bool> {
        Binding(get: { !collapsed.split(separator: ",").contains { $0 == key } }, set: { open in
            var keys = collapsed.split(separator: ",").map(String.init).filter { $0 != key }
            if !open { keys.append(key) }
            collapsed = keys.joined(separator: ",")
        })
    }

    @ViewBuilder private var list: some View {
        let pool = (state.showArchive ? store.archivedChats : store.active).filter(matches)
        if pool.isEmpty && (searching || state.showArchive || store.folders.isEmpty) {
            Text(searching ? L("Sonuç yok", "No results")
                 : state.showArchive ? L("Arşiv boş.", "The archive is empty.")
                 : L("Sohbetlerin burada görünür.", "Your chats show up here."))
                .font(Theme.small).foregroundStyle(Theme.textMuted)
                .padding(.horizontal, Theme.sidebarInset + Theme.Spacing.s)
                .padding(.top, Theme.Spacing.s)
            Spacer()
        } else {
            List(selection: $state.selection) {
                if searching || state.showArchive {
                    Section {
                        ForEach(pool) { row($0) }
                    } header: {
                        if searching { header(L("\(pool.count) sonuç", "\(pool.count) results")) }
                    }
                } else {
                    let pinned = pool.filter(\.pinned)
                    if !pinned.isEmpty {
                        Section(isExpanded: expanded("pinned")) { ForEach(pinned) { row($0) } } header: { header(L("Sabitlenenler", "Pinned")) }
                    }
                    Section(isExpanded: expanded("folders")) {
                        ForEach(store.folders) { folder in
                            AIFolderGroup(folder: folder, state: state, expanded: expanded("folder:\(folder.id)"))
                        }
                        NewFolderRow { state.newFolder() }
                    } header: {
                        header(L("Klasörler", "Folders"))
                    }
                    groups(pool.filter { !$0.pinned && $0.folder == nil })
                }
            }
            .listStyle(.sidebar)
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)
            .onDeleteCommand { if let chat = state.conversation { state.archive(chat) } }
            .onKeyPress(.return) {
                guard state.renaming == nil, let id = state.selection else { return .ignored }
                state.renaming = id
                return .handled
            }
            .animation(.easeOut(duration: 0.2), value: pool.map(\.id))
        }
    }

    @ViewBuilder private func groups(_ chats: [AIConversation]) -> some View {
        switch AIChatGrouping(rawValue: grouping) ?? .date {
        case .date:
            let order = chats.map { AIChatStore.group($0.updated) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            ForEach(order, id: \.self) { group in
                Section(isExpanded: expanded("date:\(group)")) {
                    ForEach(chats.filter { AIChatStore.group($0.updated) == group }) { row($0) }
                } header: { header(group) }
            }
        case .ai:
            ForEach(AIEngine.order.filter { engine in chats.contains { $0.engine == engine } }) { engine in
                Section(isExpanded: expanded("ai:\(engine.rawValue)")) {
                    ForEach(chats.filter { $0.engine == engine }) { row($0) }
                } header: {
                    HStack(spacing: 6) {
                        AIBrandMark(engine: engine, size: 11)
                        header(engine.title)
                    }
                }
            }
        case .none:
            Section(isExpanded: expanded("all")) { ForEach(chats) { row($0) } } header: { header(L("Sohbetler", "Chats")) }
        }
    }

    private func header(_ title: String) -> some View {
        Text(verbatim: title).font(Theme.smallStrong).foregroundStyle(Theme.textMuted)
    }

    private func row(_ chat: AIConversation) -> some View {
        AIChatRow(conversation: chat, state: state, snippet: searching ? chat.snippet(for: state.query) : nil)
            .tag(chat.id)
            .draggable(chat.id.uuidString)
            .contextMenu { AIChatActions(conversation: chat, state: state) }
    }

    /// Archive, and how the list is grouped.
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: Theme.Spacing.xs) {
                let count = store.archivedChats.count
                Button { withAnimation(.easeOut(duration: 0.2)) { state.showArchive.toggle() } } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: state.showArchive ? "tray.full" : "archivebox")
                        Text(state.showArchive ? L("Sohbetlere dön", "Back to chats") : L("Arşiv", "Archive"))
                        if count > 0 && !state.showArchive {
                            Text(verbatim: "\(count)").monospacedDigit()
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Theme.track, in: Capsule())
                        }
                    }
                    .font(Theme.body)
                    .foregroundStyle(Theme.textMuted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Menu {
                    Section(L("Grupla", "Group")) {
                        ForEach(AIChatGrouping.allCases) { option in
                            Toggle(option.title, isOn: Binding(get: { grouping == option.rawValue }, set: { _ in
                                withAnimation(.easeOut(duration: 0.2)) { grouping = option.rawValue }
                            }))
                        }
                    }
                    Divider()
                    Button(L("Yeni klasör", "New folder"), systemImage: "folder.badge.plus") { state.newFolder() }
                    Button(L("Tüm bölümleri aç", "Expand all sections"), systemImage: "rectangle.expand.vertical") { collapsed = "" }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .tint(Theme.textMuted)
                .fixedSize()
                .help(L("Gruplama ve klasörler", "Grouping and folders"))
            }
            .padding(.horizontal, Theme.sidebarInset + Theme.Spacing.s)
            .frame(height: 38)
        }
    }
}

/// The sidebar's grid: every row puts its icon in the same 16 pt column and its text in the same column after it;
/// chats inside a folder move one step in, so their icons sit under the folder's name.
enum SidebarGrid {
    static let icon: CGFloat = 16
    static let gap: CGFloat = 8
    static let row: CGFloat = 26
    static var indent: CGFloat { icon + gap }
    /// The column at the row's end for a pin, a dot, a count or a chevron, so they all centre on one line.
    static let trailing: CGFloat = 14
}

/// A folder in the sidebar, on the same grid as the chats: its icon, its name, how many chats; click to open or
/// close. On hover a chevron shows where it opens, plus a new chat inside it and its menu. Takes dropped chats.
private struct AIFolderGroup: View {
    let folder: AIFolder
    @Bindable var state: AIChatState
    @Binding var expanded: Bool
    @State private var hovering = false
    @State private var targeted = false
    @State private var name = ""
    private let store = AIChatStore.shared

    var body: some View {
        let chats = store.chats(in: folder.id)
        header(chats.count)
            .selectionDisabled()
            .contextMenu { actions }
            .dropDestination(for: String.self) { items, _ in
                let moved = items.compactMap(UUID.init(uuidString:)).compactMap(store.conversation)
                withAnimation(.easeOut(duration: 0.2)) {
                    moved.forEach { store.move($0, to: folder.id) }
                    expanded = true
                }
                return !moved.isEmpty
            } isTargeted: { targeted = $0 }
        if expanded {
            ForEach(chats) { chat in
                AIChatRow(conversation: chat, state: state, snippet: nil)
                    .padding(.leading, SidebarGrid.indent)
                    .tag(chat.id)
                    .draggable(chat.id.uuidString)
                    .contextMenu { AIChatActions(conversation: chat, state: state) }
            }
            if chats.isEmpty {
                Text(L("Sohbetleri buraya sürükle", "Drag chats here"))
                    .font(Theme.small).foregroundStyle(Theme.textMuted)
                    .padding(.leading, SidebarGrid.indent)
                    .frame(height: SidebarGrid.row)
                    .selectionDisabled()
            }
        }
    }

    private func header(_ count: Int) -> some View {
        HStack(spacing: SidebarGrid.gap) {
            Image(systemName: targeted || expanded ? "folder.fill" : "folder")
                .font(.system(size: 13))
                .foregroundStyle(targeted ? Theme.accent : Theme.textMuted)
                .frame(width: SidebarGrid.icon, height: SidebarGrid.icon)
            if state.renamingFolder == folder.id {
                InlineRenameField(text: $name, commit: commit, cancel: { state.renamingFolder = nil })
                    .framed()
                    .onAppear { name = folder.name }
            } else {
                Text(verbatim: folder.name).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
            }
            Spacer(minLength: 0)
            if state.renamingFolder != folder.id {
                if hovering {
                    HStack(spacing: 2) {
                        RowButton(symbol: "square.and.pencil", help: L("Bu klasörde yeni sohbet", "New chat in this folder")) {
                            state.newChat(in: folder.id)
                        }
                        Menu { actions } label: { Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold)) }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .tint(Theme.textMuted)
                            .fixedSize()
                            .frame(width: 22, height: 22)
                    }
                    .transition(.opacity)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: SidebarGrid.trailing)
                    .opacity(hovering ? 1 : 0)
                    .overlay {
                        if !hovering && count > 0 {
                            Text(verbatim: "\(count)").font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted).fixedSize()
                        }
                    }
            }
        }
        .frame(height: SidebarGrid.row)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() } }
        .onHover { over in withAnimation(.easeOut(duration: 0.12)) { hovering = over } }
    }

    @ViewBuilder private var actions: some View {
        Button(L("Bu klasörde yeni sohbet", "New chat in this folder"), systemImage: "square.and.pencil") { state.newChat(in: folder.id) }
        Button(L("Yeniden adlandır", "Rename"), systemImage: "pencil") { state.renamingFolder = folder.id }
        Divider()
        Button(L("Klasörü sil…", "Delete folder…"), systemImage: "trash", role: .destructive) { state.pendingFolderDelete = folder }
    }

    private func commit() {
        guard state.renamingFolder == folder.id else { return }
        store.renameFolder(folder.id, name)
        state.renamingFolder = nil
    }
}

/// "Add folder" at the end of the folders, on the same grid as a folder row: a plus in the icon column, the words in
/// the text column, muted until hovered.
private struct NewFolderRow: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SidebarGrid.gap) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 13))
                    .frame(width: SidebarGrid.icon, height: SidebarGrid.icon)
                Text(L("Klasör ekle", "Add folder")).font(Theme.body)
                Spacer(minLength: 0)
                Text(verbatim: "⇧⌘N").font(Theme.small).opacity(hovering ? 1 : 0)
            }
            .foregroundStyle(hovering ? Theme.text : Theme.textMuted)
            .frame(height: SidebarGrid.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .onHover { hovering = $0 }
    }
}

/// Pin, rename, move to a folder, copy, archive and delete: the same in the row's ⋯ menu, its right-click menu and
/// the title bar.
private struct AIChatActions: View {
    let conversation: AIConversation
    let state: AIChatState
    private let store = AIChatStore.shared

    var body: some View {
        if !conversation.archived {
            Button(conversation.pinned ? L("Sabitlemeyi kaldır", "Unpin") : L("Sabitle", "Pin"),
                   systemImage: conversation.pinned ? "pin.slash" : "pin") {
                withAnimation(.easeOut(duration: 0.2)) { store.setPinned(conversation, !conversation.pinned) }
            }
        }
        Button(L("Yeniden adlandır", "Rename"), systemImage: "pencil") {
            state.selection = conversation.id
            state.renaming = conversation.id
        }
        if conversation.promptMessages.count >= 2 {
            Button(L("Özetle ve sürdür", "Summarize and continue"), systemImage: "rectangle.compress.vertical") {
                Task { await conversation.compact() }
            }
            .disabled(conversation.isRunning || conversation.compacting)
        }
        Menu {
            ForEach(store.folders) { folder in
                Toggle(isOn: Binding(get: { conversation.folder == folder.id }, set: { _ in
                    withAnimation(.easeOut(duration: 0.2)) { store.move(conversation, to: folder.id) }
                })) { Label(folder.name, systemImage: "folder") }
            }
            if !store.folders.isEmpty { Divider() }
            Button(L("Yeni klasör…", "New folder…"), systemImage: "folder.badge.plus") { state.newFolder(moving: conversation) }
            if conversation.folder != nil {
                Button(L("Klasörden çıkar", "Remove from folder"), systemImage: "folder.badge.minus") {
                    withAnimation(.easeOut(duration: 0.2)) { store.move(conversation, to: nil) }
                }
            }
        } label: {
            Label(L("Klasöre taşı", "Move to folder"), systemImage: "folder")
        }
        Button(L("Markdown olarak kopyala", "Copy as Markdown"), systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(AIChatState.markdown(conversation), forType: .string)
        }
        Divider()
        Button(conversation.archived ? L("Arşivden çıkar", "Unarchive") : L("Arşivle", "Archive"),
               systemImage: conversation.archived ? "tray.and.arrow.up" : "archivebox") {
            state.archive(conversation)
        }
        Button(L("Sil…", "Delete…"), systemImage: "trash", role: .destructive) { state.pendingDelete = conversation }
    }
}

/// A chat in the sidebar: its AI's mark (moving while it answers), the title (and where a search matched), a dot
/// for a new answer, and on hover pin, archive and ⋯. Hover for the last words of the chat.
private struct AIChatRow: View {
    let conversation: AIConversation
    @Bindable var state: AIChatState
    let snippet: String?
    @State private var hovering = false
    @State private var name = ""
    @FocusState private var editing: Bool
    private let store = AIChatStore.shared

    var body: some View {
        HStack(spacing: SidebarGrid.gap) {
            AIBrandMark(engine: conversation.engine, size: 14, animating: conversation.isRunning)
                .frame(width: SidebarGrid.icon, height: SidebarGrid.icon)
            VStack(alignment: .leading, spacing: 1) {
                if state.renaming == conversation.id {
                    InlineRenameField(text: $name, commit: commit, cancel: { state.renaming = nil })
                        .framed()
                        .onAppear { name = conversation.title }
                } else {
                    Text(verbatim: conversation.title).lineLimit(1).font(conversation.unread ? Theme.bodyStrong : Theme.body)
                        .foregroundStyle(conversation.archived ? Theme.textMuted : Theme.text)
                }
                if let snippet {
                    Text(verbatim: snippet).font(.system(size: 10.5)).foregroundStyle(Theme.textMuted).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if hovering && state.renaming != conversation.id {
                HStack(spacing: 2) {
                    if !conversation.archived {
                        RowButton(symbol: conversation.pinned ? "pin.slash" : "pin",
                                  help: conversation.pinned ? L("Sabitlemeyi kaldır", "Unpin") : L("Sabitle", "Pin")) {
                            withAnimation(.easeOut(duration: 0.2)) { store.setPinned(conversation, !conversation.pinned) }
                        }
                    }
                    RowButton(symbol: conversation.archived ? "tray.and.arrow.up" : "archivebox",
                              help: conversation.archived ? L("Arşivden çıkar", "Unarchive") : L("Arşivle (⌫)", "Archive (⌫)")) {
                        state.archive(conversation)
                    }
                    Menu {
                        AIChatActions(conversation: conversation, state: state)
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .tint(Theme.textMuted)
                    .fixedSize()
                    .frame(width: 22, height: 22)
                    .help(L("Daha fazla", "More"))
                }
                .transition(.opacity)
            } else if !conversation.isRunning, conversation.lastAnswer?.error != nil, conversation.messages.last?.role == .assistant {
                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 10)).foregroundStyle(Theme.warning.fill)
                    .frame(width: SidebarGrid.trailing)
                    .help(conversation.lastAnswer?.error ?? "")
            } else if conversation.unread {
                Circle().fill(conversation.engine.brand.multicolor ? AnyShapeStyle(conversation.engine.brand.gradient) : AnyShapeStyle(Theme.accent))
                    .frame(width: 7, height: 7)
                    .frame(width: SidebarGrid.trailing)
                    .help(L("Yeni cevap", "New answer"))
            } else if conversation.pinned && state.renaming != conversation.id {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Theme.textMuted)
                    .frame(width: SidebarGrid.trailing)
            }
        }
        .frame(minHeight: SidebarGrid.row)
        .contentShape(Rectangle())
        .onHover { over in withAnimation(.easeOut(duration: 0.12)) { hovering = over } }
        .help(conversation.preview + "\n" + conversation.updated.formatted(.relative(presentation: .named).locale(Format.locale)))
    }

    private func commit() {
        guard state.renaming == conversation.id else { return }
        conversation.rename(name)
        state.renaming = nil
    }
}

private struct RowButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? Theme.text : Theme.textMuted)
                .frame(width: 22, height: 22)
                .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

// MARK: - Detail

/// The open chat (or a new one): the messages and the message box.
private struct AIChatDetail: View {
    @Bindable var state: AIChatState

    var body: some View {
        let conversation = state.conversation
        let engine = conversation?.engine ?? state.engine
        // The side chat sits beside the chat (never over it), which narrows to make room, down to a readable width.
        GeometryReader { geometry in
        let sideWidth = max(260, min(360, geometry.size.width - 440))
        HStack(spacing: 0) {
        VStack(spacing: 0) {
            if let conversation, !conversation.messages.isEmpty {
                if state.finding {
                    // Above the chat, not over it, so the match it shows is never hidden behind it.
                    HStack {
                        Spacer(minLength: 0)
                        FindBar(state: state)
                    }
                    .padding(.top, Theme.Spacing.s)
                    .padding(.trailing, Theme.Spacing.l)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                AITranscriptView(conversation: conversation, state: state)
            } else {
                AIWelcome(engine: engine, state: state)
            }
            AIComposer(state: state)
                .frame(maxWidth: 780)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
            if state.sideOpen, conversation != nil {
                SideChatPanel(state: state, width: sideWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        }
        .animation(.easeOut(duration: 0.15), value: state.finding)
        .overlay {
            if state.dropping {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .background(Theme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        Label(L("Eklemek için bırak", "Drop to attach"), systemImage: "paperclip")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, Theme.Spacing.l)
                            .frame(height: 36)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .padding(Theme.Spacing.m)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: state.dropping)

        // esc while reading (not only in the box): stop the answer, or cancel an edit.
        .onExitCommand { state.escape() }
        .onDrop(of: [.fileURL], isTargeted: $state.dropping) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in state.attach(file: url) }
                }
            }
            return true
        }
    }
}

/// ⌘F: find words in the open chat. ↩ the match above, ⇧↩ below, esc closes.
private struct FindBar: View {
    @Bindable var state: AIChatState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                .frame(width: 16)
            TextField(L("Sohbette ara", "Find in chat"), text: $state.findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(width: 170)
                .focused($focused)
                .onSubmit { state.findStep(NSEvent.modifierFlags.contains(.shift) ? 1 : -1) }
                .onExitCommand { state.finding = false }
            Text(verbatim: count)
                .font(.system(size: 11.5)).monospacedDigit()
                .foregroundStyle(Theme.textMuted)
                .fixedSize()
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 16).padding(.horizontal, 2)
            step("chevron.up", L("Önceki (↩)", "Previous (↩)"), -1)
            step("chevron.down", L("Sonraki (⇧↩)", "Next (⇧↩)"), 1)
            Button { state.finding = false } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textMuted)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Kapat (esc)", "Close (esc)"))
        }
        .padding(.leading, Theme.Spacing.s + 2)
        .padding(.trailing, Theme.Spacing.xs)
        .frame(height: 34)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.hairline) }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .onAppear { focused = true; state.updateFind() }
        .onChange(of: state.focusFind) { _, _ in focused = true }
        .onChange(of: state.findQuery) { _, _ in state.updateFind() }
        .onChange(of: state.conversation?.messages.count) { _, _ in state.updateFind() }
    }

    private var count: String {
        if state.findQuery.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        if state.findMatches.isEmpty { return L("Sonuç yok", "No results") }
        return "\(state.findIndex + 1)/\(state.findMatches.count)"
    }

    private func step(_ symbol: String, _ help: String, _ by: Int) -> some View {
        Button { state.findStep(by) } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                .foregroundStyle(state.findMatches.isEmpty ? Theme.textMuted.opacity(0.5) : Theme.text)
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.findMatches.isEmpty)
        .help(help)
    }
}

/// The empty chat: the AI's mark, a greeting and a few ways to start.
private struct AIWelcome: View {
    let engine: AIEngine
    @Bindable var state: AIChatState

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            AIBrandMark(engine: engine, size: 48)
            Text(verbatim: greeting)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(L("\(engine.shortName) ile sohbet et", "Chat with \(engine.shortName)") + subtitle)
                .font(Theme.body).foregroundStyle(Theme.textMuted)
            FlowChips(chips: chips)
                .frame(maxWidth: 640)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
    }

    private var subtitle: String {
        engine == .onDevice ? L(" · ücretsiz, bu Mac'te, internetsiz", " · free, on this Mac, offline") : ""
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        let hello = switch hour {
        case 5..<12: L("Günaydın", "Good morning")
        case 12..<18: L("İyi günler", "Good afternoon")
        default: L("İyi akşamlar", "Good evening")
        }
        return name.isEmpty ? hello : "\(hello), \(name)"
    }

    private var chips: [StarterChip] {
        var list: [StarterChip] = []
        if let copied = ClipboardHistory.shared.items.first(where: { $0.text != nil && $0.kind == .text })?.text,
           !SecretText.looksSecret(copied) {
            list.append(StarterChip(title: L("Panodakini özetle", "Summarise what I copied"), symbol: "text.append") {
                state.send(AITextTask.summarize.title, attachment: copied, prompt: AITextTask.summarize.prompt(copied),
                           attachmentName: L("Kopyalanan metin", "Copied text"))
            })
        }
        list.append(StarterChip(title: L("Basitçe açıkla", "Explain simply"), symbol: "lightbulb") { fill(L("Bana basitçe açıkla: ", "Explain simply: ")) })
        list.append(StarterChip(title: L("E-posta yaz", "Write an email"), symbol: "envelope") { fill(L("Kısa ve kibar bir e-posta yaz: ", "Write a short, polite email: ")) })
        list.append(StarterChip(title: L("Kodu incele", "Review code"), symbol: "chevron.left.forwardslash.chevron.right") {
            fill(L("Bu kodu incele, hataları ve iyileştirmeleri söyle:\n", "Review this code and point out bugs and improvements:\n"))
        })
        list.append(StarterChip(title: L("Fikir üret", "Brainstorm"), symbol: "sparkles") { fill(L("Şunun için 5 fikir ver: ", "Give me 5 ideas for: ")) })
        return list
    }

    /// Starters that need your words only fill the message box.
    private func fill(_ text: String) {
        state.draft = text
        state.focusComposer += 1
    }
}

private struct StarterChip: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let action: () -> Void
}

/// Starter chips that wrap onto a second line when the window is narrow.
private struct FlowChips: View {
    let chips: [StarterChip]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.s) { ForEach(chips) { ChipButton(chip: $0) } }
            VStack(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) { ForEach(chips.prefix(3)) { ChipButton(chip: $0) } }
                HStack(spacing: Theme.Spacing.s) { ForEach(chips.dropFirst(3)) { ChipButton(chip: $0) } }
            }
        }
    }
}

private struct ChipButton: View {
    let chip: StarterChip
    @State private var hovering = false

    var body: some View {
        Button(action: chip.action) {
            Label(chip.title, systemImage: chip.symbol)
                .font(Theme.small)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .background(hovering ? Theme.hover : Theme.track, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.hairline) }
                .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Composer

/// The message box, like the apps': files and long pastes become cards above the text, ↩ sends, ⌥↩ adds a line,
/// ↑ in an empty box edits your last message, esc stops. At the bottom: add (+), the AI and model, how hard it
/// thinks, and the send button in the AI's colours, which turns into stop while it writes. Frosted like the window.
struct AIComposer: View {
    @Bindable var state: AIChatState
    @FocusState private var focused: Bool
    @AppStorage("panelStyle") private var style = "material"

    var body: some View {
        let conversation = state.conversation
        let engine = conversation?.engine ?? state.engine
        let model = conversation?.model ?? state.model
        let brand = engine.brand
        let running = conversation?.isRunning == true
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(spacing: Theme.Spacing.s) {
            if let limit = AIChatStore.shared.liveLimits[engine], limit.status != .allowed,
               limit.status == .warning || (limit.resetsAt ?? .distantFuture) > Date() {
                LimitBanner(engine: engine, limit: limit, state: state)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if let editing = state.editing, editing.chat == conversation?.id {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "pencil").font(.system(size: 11, weight: .semibold))
                        Text(L("Mesajını düzenliyorsun; gönderince bu noktadan devam eder",
                               "Editing your message; sending continues from here"))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button(L("Vazgeç", "Cancel")) { withAnimation(.easeOut(duration: 0.15)) { state.cancelEdit() } }
                            .buttonStyle(TextButtonStyle(font: .system(size: 12, weight: .medium), color: Theme.accent))
                            .help("esc")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 2)
                    .transition(.opacity)
                }
                if !state.attachments.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: Theme.Spacing.s) {
                            ForEach(state.attachments) { attachment in
                                AttachmentCard(attachment: attachment) {
                                    withAnimation(.easeOut(duration: 0.15)) { state.attachments.removeAll { $0.id == attachment.id } }
                                    if let image = attachment.image, state.editing == nil { AIImages.remove([image]) }
                                }
                            }
                        }
                        .padding(.top, 6)
                        .padding(.trailing, 6)
                    }
                    .scrollIndicators(.never)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if let conversation, let waiting = state.queued[conversation.id], !waiting.isEmpty {
                    QueuedList(items: waiting, state: state, running: running)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                let suggestion = conversation.flatMap { state.suggestions[$0.id] }
                TextField(running ? L("\(engine.shortName) yazıyor… ↩ sıraya ekler", "\(engine.shortName) is writing… ↩ queues it")
                          : suggestion.map { "\($0.count > 90 ? $0.prefix(88) + "…" : $0)   ⇥" } ?? L("\(engine.shortName)'a yaz…", "Message \(engine.shortName)…"),
                          text: $state.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...12)
                    .lineSpacing(3)
                    .tint(brand.multicolor ? brand.colors[1] : brand.tint)
                    .focused($focused)
                    .onSubmit { state.send() }
                    .onExitCommand { state.escape() }
                    .onKeyPress(.tab) {
                        // Tab takes the suggestion into the box, to send as it is or change.
                        guard state.draft.isEmpty, let conversation, let next = state.suggestions[conversation.id] else { return .ignored }
                        state.draft = next
                        state.suggestions[conversation.id] = nil
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard state.draft.isEmpty, let conversation, let last = conversation.lastQuestion, !conversation.isRunning else { return .ignored }
                        state.edit(last)
                        return .handled
                    }
                    .onChange(of: state.draft) { old, new in takeLongPaste(old, new) }
                    .padding(.horizontal, 2)
                    .padding(.top, 2)
                HStack(spacing: Theme.Spacing.s) {
                    AddMenu(state: state)
                    AIModelMenu(engine: Binding(get: { conversation?.engine ?? state.engine }, set: { engine in
                        let model = engine.chosenModel
                        if let conversation { conversation.use(engine, model: model) } else { state.engine = engine; state.model = model }
                    }), model: Binding(get: { conversation?.model ?? state.model }, set: { model in
                        if let conversation { conversation.use(conversation.engine, model: model) } else { state.model = model }
                    }), pill: true)
                    if let conversation, let usage = conversation.usage, usage.fraction != nil {
                        ContextMeter(usage: usage, engine: engine, conversation: conversation)
                    }
                    Spacer(minLength: 0)
                    if state.draft.count > 1_000 {
                        Text(verbatim: state.draft.count.formatted()).font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted)
                    }
                    AISendButton(engine: engine, running: running && !state.canSend, enabled: state.canSend) {
                        // While it writes: the stop button, or ↑ to queue what you've typed.
                        if running && !state.canSend { conversation?.stop() } else { state.send() }
                    }
                }
            }
            .padding(Theme.Spacing.m)
            .background {
                if style == "opaque" { shape.fill(Theme.surfaceRaised) } else { shape.fill(.regularMaterial) }
            }
            .overlay {
                if focused && !running {
                    // The AI's own colours: Apple's and Gemini's gradient, Claude's coral, Codex's blue.
                    shape.strokeBorder(brand.multicolor ? AnyShapeStyle(brand.ring) : AnyShapeStyle(brand.tint), lineWidth: 1.2)
                        .opacity(brand.multicolor ? 0.75 : 0.5)
                } else {
                    shape.strokeBorder(Theme.hairline)
                }
            }
            .shadow(color: .black.opacity(focused ? 0.10 : 0.05), radius: focused ? 16 : 10, y: 4)
            .overlay { AIGlow(engine: engine, active: running, cornerRadius: 22) }
            .animation(.easeOut(duration: 0.18), value: focused)
            .animation(.easeOut(duration: 0.18), value: state.attachments)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            Text(footnote(engine))
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textMuted.opacity(0.8))
                .lineLimit(1)
        }
        .onAppear { focused = true }
        .onChange(of: state.focusComposer) { _, _ in focused = true }
    }

    private func footnote(_ engine: AIEngine) -> String {
        let keys = L("↩ gönder · ⌥↩ yeni satır · ↑ son mesajı düzenle", "↩ send · ⌥↩ new line · ↑ edit last message")
        let note = engine == .onDevice ? L("Cihaz içi: metin bu Mac'ten çıkmaz", "On-device: text never leaves this Mac")
                                       : L("AI hata yapabilir; önemli bilgileri kontrol et", "AI can make mistakes; check what matters")
        return keys + "   ·   " + note
    }

    /// A long paste becomes a card, like the apps do, so the box stays readable.
    private func takeLongPaste(_ old: String, _ new: String) {
        guard new.count - old.count > 1_500 else { return }
        let prefix = zip(old, new).prefix { $0 == $1 }.count
        let suffix = zip(old.reversed(), new.reversed()).prefix { $0 == $1 }.count
        let start = new.index(new.startIndex, offsetBy: prefix)
        let end = new.index(new.endIndex, offsetBy: -min(suffix, new.count - prefix))
        guard start < end else { return }
        let pasted = String(new[start..<end])
        state.attachments.append(AIAttachment(name: L("Yapıştırılan metin", "Pasted text"), text: pasted, symbol: "doc.on.clipboard"))
        state.draft = old
    }
}

/// An attached file or paste in the box: its name, size and a ×.
private struct AttachmentCard: View {
    let attachment: AIAttachment
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if let image = attachment.image, let picture = NSImage(contentsOf: AIImages.url(image)) {
                Image(nsImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Image(systemName: attachment.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 30, height: 30)
                    .background(Theme.track, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: attachment.name).font(Theme.small.weight(.medium)).foregroundStyle(Theme.text).lineLimit(1)
                Text(attachment.image != nil ? L("Görsel", "Image")
                     : L("\(attachment.text.split(whereSeparator: \.isNewline).count) satır", "\(attachment.text.split(whereSeparator: \.isNewline).count) lines"))
                    .font(.system(size: 10)).foregroundStyle(Theme.textMuted)
            }
            .frame(maxWidth: 160, alignment: .leading)
        }
        .padding(Theme.Spacing.xs + 2)
        .padding(.trailing, Theme.Spacing.s)
        .background(Theme.field.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline) }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(Theme.textMuted)
                        .background(Circle().fill(Theme.surfaceRaised))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .help(L("Kaldır", "Remove"))
            }
        }
        .onHover { hovering = $0 }
        .help(attachment.image != nil ? attachment.name : String(attachment.text.prefix(300)))
    }
}

/// Where a long chat was summarized: from here on the AI gets the summary instead of the messages above.
private struct SummaryDivider: View {
    let summary: String
    let size: CGFloat
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                Button { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "rectangle.compress.vertical")
                        Text(L("Buraya kadarı özetlendi", "Summarized up to here"))
                        Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: size * 0.6))
                    }
                    .font(.system(size: size * 0.78))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("AI bundan sonra yukarıdaki mesajlar yerine bu özeti görür", "From here the AI sees this summary instead of the messages above"))
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
            if open {
                MarkdownView(text: summary, size: size * 0.88, tint: Theme.accent)
                    .padding(size * 0.8)
                    .background(Theme.track, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    .transition(.opacity)
            }
        }
    }
}

/// Questions on the side (⌥⌘S): sees the main chat, answers apart, never goes in it. "Add to chat" quotes an answer
/// into the main box.
private struct SideChatPanel: View {
    @Bindable var state: AIChatState
    let width: CGFloat
    @FocusState private var focused: Bool

    var body: some View {
        let side = state.side
        let main = state.conversation
        let engine = side?.engine ?? main?.engine ?? .onDevice
        HStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(width: 1)
            VStack(spacing: 0) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "bubble.left.and.text.bubble.right").foregroundStyle(Theme.textMuted)
                    Text(L("Yan sohbet", "Side chat")).font(Theme.bodyStrong)
                    Spacer(minLength: 0)
                    if side != nil {
                        RowButton(symbol: "arrow.counterclockwise", help: L("Baştan başla", "Start over")) { state.resetSide() }
                    }
                    RowButton(symbol: "xmark", help: L("Kapat (⌥⌘S)", "Close (⌥⌘S)")) { state.toggleSide() }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .frame(height: 40)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                if let side, !side.messages.isEmpty {
                    AITranscriptView(conversation: side, compact: true)
                    if let answer = side.lastAnswer, !answer.text.isEmpty, !side.isRunning {
                        Button {
                            state.quote(answer.text)
                        } label: {
                            Label(L("Ana sohbete ekle", "Add to the main chat"), systemImage: "arrow.uturn.left")
                        }
                        .buttonStyle(TextButtonStyle(font: .system(size: 12, weight: .medium), color: Theme.accent))
                        .help(L("Son cevabı ana sohbetin mesaj kutusuna alıntılar", "Quotes the last answer into the main chat's box"))
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                } else {
                    VStack(spacing: Theme.Spacing.s) {
                        Spacer()
                        Image(systemName: "bubble.left.and.text.bubble.right").font(.system(size: 26)).foregroundStyle(Theme.textMuted.opacity(0.6))
                        Text(L("Ana sohbeti bozmadan bir şey sor: bir terimi açıklat, bir cevabı kontrol ettir, başka bir yol iste. Yan sohbet ana sohbeti görür ama ona eklenmez.",
                               "Ask something without derailing the main chat: explain a term, check an answer, try another way. The side chat sees the main chat but isn't added to it."))
                            .font(Theme.small).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.l)
                        Spacer()
                    }
                }
                HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
                    TextField(L("Yan soru…", "Side question…"), text: $state.sideDraft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .lineLimit(1...6)
                        .focused($focused)
                        .onSubmit { state.sendSide() }
                        .onExitCommand { if side?.isRunning == true { side?.stop() } else { state.toggleSide() } }
                    AISendButton(engine: engine, running: side?.isRunning == true,
                                 enabled: !state.sideDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        if side?.isRunning == true { side?.stop() } else { state.sendSide() }
                    }
                }
                .padding(Theme.Spacing.s + 2)
                .background(Theme.field.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline) }
                .padding(Theme.Spacing.s)
            }
            .frame(width: width)
        }
        .onAppear { focused = true }
    }
}

/// Text you selected in the chat, read from the view holding it; or, failing that, copied and the clipboard put back.
@MainActor
enum TranscriptSelection {
    static func read() -> String? {
        guard let window = NSApp.keyWindow else { return nil }
        if let view = window.firstResponder as? NSTextView {
            // The message box: its selection isn't a quote.
            if view.isFieldEditor { return nil }
            let range = view.selectedRange()
            return range.length > 0 ? (view.string as NSString).substring(with: range) : nil
        }
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        let before = pasteboard.changeCount
        guard NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil), pasteboard.changeCount != before,
              let text = pasteboard.string(forType: .string) else { return nil }
        // Put back what was there, marked as a scratch copy so clipboard histories (Nabız's too) skip it.
        pasteboard.clearContents()
        if let first = saved.first { first.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) }
        pasteboard.writeObjects(saved)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Messages waiting for the answer being written; each goes out in turn. Send now stops the answer for it.
private struct QueuedList: View {
    let items: [AIChatState.Queued]
    let state: AIChatState
    let running: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items) { item in
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "clock").font(.system(size: 11)).foregroundStyle(Theme.textMuted).frame(width: 16)
                    Text(verbatim: item.text.isEmpty ? (item.attachmentName ?? L("Ek", "Attachment")) : item.text)
                        .font(.system(size: 12.5)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: Theme.Spacing.s)
                    Button(L("Şimdi gönder", "Send now")) { state.sendNow(item) }
                        .buttonStyle(TextButtonStyle(font: .system(size: 11.5, weight: .medium), color: Theme.accent))
                        .help(running ? L("Yazılan cevabı durdurup bunu gönderir", "Stops the answer being written and sends this")
                                      : L("Bunu şimdi gönderir", "Sends this now"))
                    RowButton(symbol: "pencil", help: L("Düzenle", "Edit")) { state.editQueued(item) }
                    RowButton(symbol: "xmark", help: L("Sıradan çıkar", "Remove")) { state.removeQueued(item) }
                }
                .frame(height: 26)
            }
            if !running {
                // After a stop or an error the queue waits for you.
                Button(L("Sıradakileri gönder", "Send the queued messages")) {
                    if let id = state.conversation?.id { state.sendQueued(in: id) }
                }
                .buttonStyle(TextButtonStyle(font: .system(size: 11.5, weight: .medium), color: Theme.accent))
                .padding(.leading, 24)
            }
        }
        .padding(.horizontal, 2)
    }
}

/// How full the chat is for the model: a small ring; click for the numbers.
private struct ContextMeter: View {
    let usage: AIUsage
    let engine: AIEngine
    let conversation: AIConversation
    @State private var open = false

    var body: some View {
        let fraction = usage.fraction ?? 0
        let color: Color = fraction >= 0.9 ? Theme.danger : fraction >= 0.8 ? Theme.warning.fill : Theme.textMuted
        Button { open.toggle() } label: {
            ZStack {
                Circle().stroke(Theme.hairline, lineWidth: 2.5)
                Circle().trim(from: 0, to: max(0.02, fraction))
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 15, height: 15)
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Sohbetin \(Int((fraction * 100).rounded()))%'i dolu", "Chat is \(Int((fraction * 100).rounded()))% full"))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(L("Sohbetin boyutu", "Chat size")).font(Theme.bodyStrong)
                Text(verbatim: "\(Self.short(usage.tokens)) / \(Self.short(usage.window ?? 0)) token · %\(Int((fraction * 100).rounded()))")
                    .font(Theme.body).monospacedDigit()
                ProgressView(value: fraction).tint(color).frame(width: 220)
                if let cost = usage.cost, cost > 0 {
                    Text(L("Bu cevap API fiyatıyla yaklaşık \(cost.formatted(.currency(code: "USD"))); aboneliğinden düşer, ayrıca ödenmez.",
                           "This answer is about \(cost.formatted(.currency(code: "USD"))) at API prices; it comes out of your plan, not billed."))
                        .font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                Text(fraction >= 0.8
                     ? L("Doluyor: yeni bir sohbet açmak ya da \"Buradan yeni sohbet\" ile dallanmak daha iyi cevap verir.",
                         "Filling up: a new chat, or branching with \"New chat from here\", will answer better.")
                     : L("Uzun sohbetler her mesajda daha çok limit harcar.", "Long chats use more of your limit with every message."))
                    .font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                if conversation.promptMessages.count >= 2 {
                    Button {
                        open = false
                        Task { await conversation.compact() }
                    } label: {
                        Label(L("Özetle ve sürdür", "Summarize and continue"), systemImage: "rectangle.compress.vertical")
                    }
                    .disabled(conversation.isRunning || conversation.compacting)
                    .help(L("AI şimdiye kadarkini özetler; sonraki mesajlarda tüm sohbet yerine bu özet gider. Mesajlar ekranda kalır.",
                            "The AI summarizes everything so far; from then on the summary goes instead of the whole chat. Messages stay on screen."))
                }
            }
            .padding(Theme.Spacing.m)
            .frame(width: 250, alignment: .leading)
        }
    }

    static func short(_ tokens: Int) -> String {
        tokens >= 1_000_000 ? String(format: "%.1fM", Double(tokens) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
            : tokens >= 1_000 ? "\(Int((Double(tokens) / 1_000).rounded()))K" : "\(tokens)"
    }
}

/// Over the box when the AI says your plan's limit is close or used up: when it frees up, and another AI to ask meanwhile.
private struct LimitBanner: View {
    let engine: AIEngine
    let limit: AILiveLimit
    let state: AIChatState

    var body: some View {
        let blocked = limit.status == .rejected
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: blocked ? "hourglass" : "gauge.with.dots.needle.67percent")
                .foregroundStyle(blocked ? Theme.danger : Theme.warning.fill)
            Text(verbatim: text(blocked)).font(.system(size: 12)).foregroundStyle(Theme.text).lineLimit(2)
            Spacer(minLength: Theme.Spacing.s)
            let others = AIEngine.order.filter { $0 != engine && AIEngines.shared.isAvailable($0) }
            if blocked && !others.isEmpty {
                Menu(L("Başka AI ile", "Use another AI")) {
                    ForEach(others) { other in
                        Button(other.title) {
                            if let conversation = state.conversation { conversation.use(other, model: other.chosenModel) }
                            else { state.engine = other; state.model = other.chosenModel }
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .tint(Theme.accent)
                .fixedSize()
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline) }
    }

    private func text(_ blocked: Bool) -> String {
        let reset = limit.resetsAt.map { date in
            Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened)
                : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        if blocked {
            return L("\(engine.shortName) \(limit.label.lowercased()) doldu", "\(engine.shortName) \(limit.label.lowercased()) used up")
                + (reset.map { L(" · \($0)'de yenilenir", " · resets \($0)") } ?? "")
        }
        let used = limit.used.map { L(" (%\(Int(($0 * 100).rounded())) kullanıldı)", " (\(Int(($0 * 100).rounded()))% used)") } ?? ""
        return L("\(engine.shortName) \(limit.label.lowercased()) dolmak üzere", "\(engine.shortName) \(limit.label.lowercased()) almost used") + used
            + (reset.map { L(" · \($0)'de yenilenir", " · resets \($0)") } ?? "")
    }
}

/// "+": a text file, or what you copied.
private struct AddMenu: View {
    let state: AIChatState
    @AppStorage(Prefs.aiWebSearch) private var web = true

    var body: some View {
        Menu {
            if (state.conversation?.engine ?? state.engine).searchesWeb {
                Toggle(isOn: $web) { Label(L("Web araması", "Web search"), systemImage: "globe") }
                Divider()
            }
            Button(L("Dosya ekle…", "Add a file…"), systemImage: "doc.badge.plus") { pickFile() }
            Button(L("Ekran görüntüsü ekle", "Add a screenshot"), systemImage: "camera.viewfinder") { screenshot() }
            if NSPasteboard.general.availableType(from: [.fileURL]) == nil,
               NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil) {
                Button(L("Panodaki görseli ekle", "Add the copied image"), systemImage: "photo.on.rectangle") {
                    state.attach(image: NSImage(pasteboard: .general), name: L("Kopyalanan görsel", "Copied image"))
                    state.focusComposer += 1
                }
            }
            if let copied = NSPasteboard.general.string(forType: .string), !copied.isEmpty, !SecretText.looksSecret(copied) {
                Button(L("Panodakini ekle", "Add what I copied"), systemImage: "doc.on.clipboard") {
                    state.attachments.append(AIAttachment(name: L("Kopyalanan metin", "Copied text"), text: copied, symbol: "doc.on.clipboard"))
                    state.focusComposer += 1
                }
            }
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(Theme.text)
        .fixedSize()
        .frame(width: 28, height: 28)
        .background(Theme.track, in: Circle())
        .overlay { Circle().strokeBorder(Theme.hairline) }
        .help(L("Dosya ya da metin ekle (bırakabilirsin de)", "Add a file or text (or drop one here)"))
    }

    /// Like ⌘⇧4: pick an area or a window (space), and it's attached.
    private func screenshot() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nabiz-ai-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", file.path]
        process.terminationHandler = { _ in
            Task { @MainActor in
                defer { try? FileManager.default.removeItem(at: file) }
                guard FileManager.default.fileExists(atPath: file.path) else { return }
                state.attach(image: NSImage(contentsOf: file), name: L("Ekran görüntüsü", "Screenshot"))
                NSApp.activate(ignoringOtherApps: true)
                state.focusComposer += 1
            }
        }
        try? process.run()
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.text, .plainText, .sourceCode, .json, .xml, .commaSeparatedText, .html, .yaml, .pdf, .image]
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(state.attach(file:))
        state.focusComposer += 1
    }
}

/// How hard the AI thinks, as each provider offers it: Claude's Low…Max (Medium recommended, Max uses far more),
/// Codex's levels for the chosen model, Grok's Low…Extra. Hidden for AIs without the choice. A pill in the message
/// box, a submenu inside the model menu.
struct AIEffortMenu: View {
    let engine: AIEngine
    let model: String
    var pill = true
    @AppStorage private var chosen: String
    private let engines = AIEngines.shared

    init(engine: AIEngine, model: String, pill: Bool = true) {
        self.engine = engine
        self.model = model
        self.pill = pill
        _chosen = AppStorage(wrappedValue: "", "ai.effort.\(engine.rawValue)")
    }

    var body: some View {
        let levels = engines.efforts(for: engine, model: model)
        if !levels.isEmpty {
            let current = levels.contains { $0.id == chosen } ? chosen : (levels.first(where: \.recommended)?.id ?? "")
            let title = levels.first { $0.id == current }?.title ?? L("Otomatik", "Auto")
            Menu {
                Section(L("Yüksek seviye daha kapsamlı cevap verir ama daha uzun sürer ve limitini daha hızlı harcar.",
                          "Higher effort means more thorough answers, but takes longer and uses your limits faster.")) {
                    if !levels.contains(where: \.recommended) {
                        Toggle(L("Otomatik (\(engine.title) seçer)", "Auto (\(engine.title) decides)"), isOn: Binding(
                            get: { current.isEmpty }, set: { _ in chosen = "" }))
                    }
                    ForEach(levels) { level in
                        Toggle(isOn: Binding(get: { level.id == current }, set: { _ in chosen = level.id })) {
                            Text(verbatim: label(level))
                        }
                    }
                }
            } label: {
                if pill {
                    Label(title, systemImage: "brain.filled.head.profile")
                } else {
                    Text(L("Düşünme · \(title)", "Effort · \(title)"))
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(pill ? .visible : .hidden)
            .tint(pill ? Theme.text : Theme.textMuted)
            .fixedSize()
            .font(Theme.small.weight(.medium))
            .padding(.horizontal, pill ? 10 : 0)
            .frame(height: pill ? 28 : nil)
            .background(pill ? Theme.track : .clear, in: Capsule())
            .overlay { if pill { Capsule().strokeBorder(Theme.hairline) } }
            .help(L("Düşünme seviyesi", "Thinking effort"))
        }
    }

    private func label(_ level: AIEffortLevel) -> String {
        var text = level.title
        if level.recommended { text += L(" · önerilen", " · recommended") }
        if let warning = level.warning { text += " · ⚠︎ " + warning }
        return text
    }
}

/// Send (an arrow on the AI's colours) or stop (a square with a turning ring) while it writes.
struct AISendButton: View {
    let engine: AIEngine
    let running: Bool
    let enabled: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let brand = engine.brand
        let lit = running || enabled
        Button(action: action) {
            ZStack {
                Circle().fill(lit ? AnyShapeStyle(brand.gradient) : AnyShapeStyle(Theme.field))
                Image(systemName: running ? "stop.fill" : "arrow.up")
                    .font(.system(size: running ? 10 : 14, weight: .bold))
                    // Grok's black-and-white needs the opposite colour for its arrow.
                    .foregroundStyle(lit ? (engine == .grok ? Theme.surface : .white) : Theme.textMuted)
                if running && !reduceMotion {
                    TimelineView(.animation) { context in
                        Circle().trim(from: 0, to: 0.28)
                            .stroke(brand.multicolor ? AnyShapeStyle(brand.ring) : AnyShapeStyle(brand.tint),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 360))
                            .padding(-4)
                    }
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!lit)
        .help(running ? L("Durdur (esc)", "Stop (esc)") : L("Gönder (↩)", "Send (↩)"))
        .animation(.easeOut(duration: 0.15), value: running)
        .animation(.easeOut(duration: 0.15), value: enabled)
    }
}

/// Which AI and which model: one menu, like the apps' model picker, with how hard it thinks as a submenu. The
/// provider's own default comes first and says which model it is.
struct AIModelMenu: View {
    @Binding var engine: AIEngine
    @Binding var model: String
    /// A capsule like the apps' model button; plain text in the launcher footer.
    var pill = false
    private let engines = AIEngines.shared

    var body: some View {
        HStack(spacing: 6) {
            AIBrandMark(engine: engine, size: 15)
            Menu {
                Section("AI") {
                    ForEach(AIEngine.order) { option in
                        Toggle(option.title + (engines.problem(option).map { " — \($0)" } ?? ""), isOn: Binding(
                            get: { option == engine }, set: { _ in engine = option }))
                            .disabled(!engines.isAvailable(option))
                    }
                }
                let models = engines.models(for: engine)
                if models.count > 1 {
                    Section(L("Model", "Model")) {
                        ForEach(models) { option in
                            Toggle(option.title, isOn: Binding(get: { option.id == model }, set: { _ in
                                model = option.id
                                engine.setChosenModel(option.id)
                            }))
                        }
                    }
                }
                if !engines.efforts(for: engine, model: model).isEmpty {
                    Divider()
                    AIEffortMenu(engine: engine, model: model, pill: false).id(engine)
                }
                if let provider = AIProvider(rawValue: engine.rawValue),
                   let status = AILimitsStore.shared.statuses.first(where: { $0.provider == provider }), !status.limits.isEmpty {
                    Section(status.plan.map { "\(engine.shortName) \($0)" } ?? L("\(engine.shortName) limitleri", "\(engine.shortName) limits")) {
                        ForEach(status.limits) { limit in
                            Text(verbatim: L("\(limit.label): %\(Int((limit.used * 100).rounded())) kullanıldı", "\(limit.label): \(Int((limit.used * 100).rounded()))% used")
                                 + (limit.resetsAt.map { L(" · \(Format.countdown(until: $0)) sonra yenilenir", " · resets in \(Format.countdown(until: $0))") } ?? ""))
                        }
                    }
                }
                Divider()
                Button(L("AI ayarları…", "AI settings…")) { SettingsWindow.show(.ai) }
            } label: {
                Text(verbatim: label)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .tint(pill ? Theme.text : Theme.textMuted)
            .fixedSize()
        }
        .font(pill ? Theme.small.weight(.medium) : Theme.small)
        .foregroundStyle(pill ? Theme.text : Theme.textMuted)
        .padding(.horizontal, pill ? 10 : 0)
        .frame(height: pill ? 28 : nil)
        .background(pill ? Theme.track : .clear, in: Capsule())
        .overlay { if pill { Capsule().strokeBorder(Theme.hairline) } }
        .onAppear {
            engines.refreshIfNeeded()
            AILimitsStore.shared.refreshIfNeeded(maxAge: 600)
        }
    }

    /// "Claude · Opus 5.5 · Medium", like Claude's own model button; how hard it thinks is picked inside.
    private var label: String {
        _ = engines.seenVersion
        if engine == .onDevice { return engine.shortName }
        var parts = [engine.shortName]
        let name = engines.displayName(model, engine: engine)
        if name != engine.title { parts.append(name) }
        let effort = engines.effectiveEffort(for: engine, model: model)
        if let level = engines.efforts(for: engine, model: model).first(where: { $0.id == effort }) { parts.append(level.title) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Transcript

/// The messages of a chat: yours in bubbles on the right (copy and edit on hover), the AI's as formatted text with
/// its mark, model, time, copy and "write again" underneath. Follows the answer while you're at the bottom; a ↓ button
/// brings you back when you've scrolled up. Shared by the window and the launcher.
struct AITranscriptView: View {
    let conversation: AIConversation
    var state: AIChatState?
    var compact = false
    @State private var atBottom = true
    @State private var viewport: CGFloat = 0
    /// The question you're reading now (the last one whose top has scrolled past the upper third).
    @State private var current: UUID?

    private var questions: [AIMessage] { conversation.messages.filter { $0.role == .user } }
    private var showsNavigator: Bool { !compact && questions.count > 1 }

    var body: some View {
        let size: CGFloat = compact ? 13 : 15
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? Theme.Spacing.l : Theme.Spacing.xl + 4) {
                    ForEach(conversation.messages) { message in
                        if message.role == .user {
                            UserBubble(message: message, size: size, edit: state.map { state in { state.edit(message) } })
                                .background(GeometryReader { geometry in
                                    Color.clear.preference(key: MessageOffsets.self,
                                                           value: [message.id: geometry.frame(in: .named("transcript")).minY])
                                })
                                .background { findMark(message.id) }
                                .id(message.id)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            AIAnswer(message: message, conversation: conversation, size: size, compact: compact,
                                     isLast: message.id == conversation.messages.last?.id,
                                     fork: state.map { state in { state.fork(at: message) } },
                                     quote: state.map { state in { state.quoteSelection(fallback: message.text) } })
                                .background { findMark(message.id) }
                                .id(message.id)
                                .transition(.opacity)
                        }
                        if message.id == conversation.summarizedID, let summary = conversation.summary {
                            SummaryDivider(summary: summary, size: size)
                        }
                    }
                    if conversation.compacting {
                        AIThinkingLabel(engine: conversation.engine, text: L("Sohbet özetleniyor…", "Summarizing the chat…"), size: size * 0.9)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: BottomOffset.self, value: geometry.frame(in: .named("transcript")).minY)
                        })
                }
                .frame(maxWidth: compact ? .infinity : 740, alignment: .leading)
                // Room for the navigator on the left (and the same on the right, so the column stays centred).
                .padding(.horizontal, compact ? Theme.Spacing.l : (showsNavigator ? 48 : Theme.Spacing.xl))
                .padding(.vertical, compact ? Theme.Spacing.m : Theme.Spacing.l)
                .frame(maxWidth: .infinity)
                .animation(.easeOut(duration: 0.25), value: conversation.messages.count)
            }
            .coordinateSpace(name: "transcript")
            // The navigator replaces the scroll bar in the window; the launcher keeps the system one.
            .scrollIndicators(compact ? .automatic : .never)
            .background(GeometryReader { geometry in
                Color.clear
                    .onAppear { viewport = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, height in viewport = height }
            })
            .onPreferenceChange(BottomOffset.self) { offset in
                let bottom = offset <= viewport + 60
                if bottom != atBottom { atBottom = bottom }
            }
            .onPreferenceChange(MessageOffsets.self) { offsets in
                guard showsNavigator else { return }
                var pick = questions.first?.id
                if atBottom {
                    pick = questions.last?.id
                } else {
                    for question in questions { if let top = offsets[question.id], top <= viewport * 0.33 { pick = question.id } }
                }
                if pick != current { current = pick }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: conversation.id) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: state?.findTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .center) }
            }
            .onChange(of: conversation.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: conversation.messages.last?.text.count) { _, _ in
                // Follow the answer only while you're at the bottom; scrolling up to read stops it.
                if conversation.isRunning && atBottom { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .overlay(alignment: .leading) {
                if showsNavigator {
                    ChatNavigator(questions: questions, current: current ?? questions.last?.id, height: viewport) { id in
                        jump(to: id, proxy)
                    }
                    .padding(.leading, Theme.Spacing.m)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if !atBottom {
                    Button { withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) } } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 30, height: 30)
                            .background(.regularMaterial, in: Circle())
                            .overlay { Circle().strokeBorder(Theme.hairline) }
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, Theme.Spacing.s)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .help(L("En alta in", "Jump to the latest"))
                }
            }
            .background {
                if showsNavigator {
                    // ⌥⌘↑ / ⌥⌘↓: previous / next question (⌘↑ alone moves the caret in the composer).
                    Group {
                        Button("") { step(-1, proxy) }.keyboardShortcut(.upArrow, modifiers: [.command, .option])
                        Button("") { step(1, proxy) }.keyboardShortcut(.downArrow, modifiers: [.command, .option])
                    }
                    .hidden()
                }
            }
            .animation(.easeOut(duration: 0.18), value: atBottom)
        }
    }

    /// A soft highlight behind the message find is showing.
    @ViewBuilder private func findMark(_ id: UUID) -> some View {
        if let state, state.findTarget == id {
            // Find's own yellow, as in Safari and Notes.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.yellow.opacity(0.16))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.yellow.opacity(0.55)) }
                .padding(-Theme.Spacing.s)
                .transition(.opacity)
        }
    }

    private func jump(to id: UUID, _ proxy: ScrollViewProxy) {
        current = id
        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.03)) }
    }

    private func step(_ by: Int, _ proxy: ScrollViewProxy) {
        let list = questions
        guard let index = list.firstIndex(where: { $0.id == (current ?? list.last?.id) }) else { return }
        let next = index + by
        if next >= list.count {
            withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) }
        } else if next >= 0 {
            jump(to: list[next].id, proxy)
        }
    }
}

private struct MessageOffsets: PreferenceKey {
    static let defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Quick travel through a long chat, in place of the scroll bar: a short line per question, the one you're reading
/// longer and darker. Hover for the questions themselves; click one to jump to it.
private struct ChatNavigator: View {
    let questions: [AIMessage]
    let current: UUID?
    let height: CGFloat
    let jump: (UUID) -> Void
    @State private var open = false
    @State private var hovered: UUID?

    /// Room per line: roomy for a few questions, tighter for many, never taller than about half the view.
    private var step: CGFloat {
        guard !questions.isEmpty else { return 8 }
        return max(3, min(8, (height * 0.5) / CGFloat(questions.count)))
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xs) {
            lines
            if open {
                list.transition(.opacity.combined(with: .offset(x: -6)))
            }
        }
        .onHover { over in withAnimation(.easeOut(duration: 0.15)) { open = over } }
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(questions) { question in
                let active = question.id == current
                let lit = active || hovered == question.id
                Button { jump(question.id) } label: {
                    Capsule()
                        .fill(lit ? Theme.text : Theme.textMuted.opacity(0.45))
                        .frame(width: active ? 14 : 8, height: 2)
                        .frame(width: 18, height: step, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { over in hovered = over ? question.id : (hovered == question.id ? nil : hovered) }
            }
        }
        .padding(.vertical, Theme.Spacing.s)
        .padding(.horizontal, Theme.Spacing.xs)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: current)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(questions) { question in
                        NavigatorRow(title: Self.title(of: question), active: question.id == current,
                                     hovered: hovered == question.id) { jump(question.id) }
                            .onHover { over in hovered = over ? question.id : (hovered == question.id ? nil : hovered) }
                            .id(question.id)
                    }
                }
                .padding(Theme.Spacing.xs)
            }
            .scrollIndicators(.never)
            .frame(width: 260)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: max(120, height * 0.7))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline) }
            .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
            .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
        }
    }

    /// A question's first line; an attachment's name when it was only an attachment.
    static func title(of message: AIMessage) -> String {
        let line = message.text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if !line.isEmpty { return line }
        return message.attachmentName ?? L("Ek", "Attachment")
    }
}

private struct NavigatorRow: View {
    let title: String
    let active: Bool
    let hovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 12.5, weight: active ? .medium : .regular))
                .foregroundStyle(active || hovered ? Theme.text : Theme.textMuted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.s)
                .frame(height: 26)
                .background(hovered ? Theme.hover : (active ? Theme.hover.opacity(0.6) : .clear),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct BottomOffset: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct UserBubble: View {
    let message: AIMessage
    let size: CGFloat
    var edit: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
            Spacer(minLength: size * 4)
            if hovering {
                HStack(spacing: 2) {
                    AICopyButton(text: message.text, size: size * 0.8, label: false)
                        .frame(width: 24, height: 24)
                    if let edit {
                        Button(action: edit) {
                            Image(systemName: "pencil").font(.system(size: size * 0.8)).foregroundStyle(Theme.textMuted)
                                .frame(width: 24, height: 24).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(L("Düzenle ve yeniden gönder", "Edit and send again"))
                    }
                }
                .transition(.opacity)
            }
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                if let images = message.images, !images.isEmpty {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(images, id: \.self) { MessageImage(name: $0, size: size) }
                    }
                }
                // Text read from images stays out of sight; other attached text shows as a card.
                if let attachment = message.attachment, message.images?.isEmpty ?? true {
                    AttachmentChip(text: attachment, name: message.attachmentName, size: size)
                }
                if !message.text.isEmpty {
                    Text(verbatim: message.text)
                        .font(.system(size: size))
                        .foregroundStyle(Theme.text)
                        .lineSpacing(size * 0.2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, size)
                        .padding(.vertical, size * 0.62)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: size * 1.25, style: .continuous))
                        .help(message.date.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .onHover { over in withAnimation(.easeOut(duration: 0.12)) { hovering = over } }
    }
}

/// An image you sent, small; click to open it in Preview.
private struct MessageImage: View {
    let name: String
    let size: CGFloat
    @State private var picture: NSImage?

    var body: some View {
        Group {
            if let picture {
                Button { NSWorkspace.shared.open(AIImages.url(name)) } label: {
                    Image(nsImage: picture)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: picture.size.width >= picture.size.height ? size * 10 : size * 6.5, height: size * 7.5)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.8, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: size * 0.8, style: .continuous).strokeBorder(Theme.hairline) }
                }
                .buttonStyle(.plain)
                .help(L("Önizleme'de aç", "Open in Preview"))
            } else {
                RoundedRectangle(cornerRadius: size * 0.8, style: .continuous).fill(Theme.track)
                    .frame(width: size * 7.5, height: size * 7.5)
                    .overlay { Image(systemName: "photo").foregroundStyle(Theme.textMuted) }
            }
        }
        .task(id: name) { picture = NSImage(contentsOf: AIImages.url(name)) }
    }
}

/// Attached text as a card ("Pasted text"); click to read all of it.
private struct AttachmentChip: View {
    let text: String
    var name: String?
    let size: CGFloat
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "doc.plaintext").font(.system(size: size)).foregroundStyle(Theme.textMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: name ?? text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
                            .font(.system(size: size * 0.9, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(L("\(text.count.formatted()) karakter", "\(text.count.formatted()) characters"))
                            .font(.system(size: size * 0.78)).foregroundStyle(Theme.textMuted)
                    }
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: size * 0.7)).foregroundStyle(Theme.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                ScrollView {
                    Text(verbatim: text).font(.system(size: size * 0.88)).foregroundStyle(Theme.text).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(size * 0.7)
        .frame(maxWidth: 380, alignment: .leading)
        .background(Theme.track, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline) }
    }
}

private struct AIAnswer: View {
    let message: AIMessage
    let conversation: AIConversation
    let size: CGFloat
    let compact: Bool
    let isLast: Bool
    var fork: (() -> Void)?
    var quote: (() -> Void)?
    @State private var hovering = false

    private var engine: AIEngine { message.engine ?? conversation.engine }

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.7) {
            if !message.thinking.isEmpty {
                ThinkingDisclosure(message: message, engine: engine, size: size)
            }
            if message.streaming && message.searching {
                AIThinkingLabel(engine: engine, text: L("Web'de arıyor…", "Searching the web…"), size: size)
            }
            if message.text.isEmpty && message.streaming {
                if message.thinking.isEmpty && !message.searching { AIThinkingLabel(engine: engine, size: size) }
                if !compact { AISkeleton(color: engine.brand.tint).frame(maxWidth: 480) }
            } else if !message.text.isEmpty {
                MarkdownView(text: message.text, size: size, tint: engine.brand.multicolor ? engine.brand.colors[1] : engine.brand.tint)
            }
            if message.streaming {
                // How long it has been at it, like the apps' "Working for 12s".
                HStack(spacing: Theme.Spacing.s) {
                    if !message.text.isEmpty { AIBrandMark(engine: engine, size: size, animating: true) }
                    TimelineView(.periodic(from: message.date, by: 1)) { context in
                        let seconds = max(0, Int(context.date.timeIntervalSince(message.date)))
                        if seconds >= 3 {
                            Text(verbatim: seconds < 60 ? L("\(seconds) sn", "\(seconds)s") : L("\(seconds / 60) dk \(seconds % 60) sn", "\(seconds / 60)m \(seconds % 60)s"))
                                .font(.system(size: size * 0.78)).monospacedDigit()
                                .foregroundStyle(Theme.textMuted.opacity(0.8))
                        }
                    }
                }
            }
            if let error = message.error {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning.fill)
                    Text(verbatim: error).foregroundStyle(Theme.text).textSelection(.enabled)
                    if isLast {
                        Button(L("Tekrar dene", "Try again")) { conversation.regenerate() }
                            .buttonStyle(TextButtonStyle(font: .system(size: size * 0.9), color: Theme.accent))
                    }
                }
                .font(.system(size: size * 0.9))
                .padding(size * 0.7)
                .background(Theme.track, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
            if !message.streaming && message.error == nil && !message.text.isEmpty {
                // Always under the newest answer; on hover under older ones, like the apps.
                footer.opacity(isLast || hovering ? 1 : 0)
            } else if message.stopped && message.text.isEmpty {
                Text(L("Durduruldu", "Stopped")).font(.system(size: size * 0.85)).foregroundStyle(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { over in withAnimation(.easeOut(duration: 0.12)) { hovering = over } }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.m) {
            AIBrandMark(engine: engine, size: size)
            Text(verbatim: details).font(.system(size: size * 0.8)).foregroundStyle(Theme.textMuted).lineLimit(1)
                .help(message.date.formatted(date: .complete, time: .shortened))
            AICopyButton(text: message.text, size: size * 0.85, label: false)
            if let quote {
                Button(action: quote) {
                    Image(systemName: "text.quote").font(.system(size: size * 0.85)).foregroundStyle(Theme.textMuted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Alıntıla: seçtiğin kısmı (yoksa tüm cevabı) mesaj kutusuna koyar (⇧⌘')",
                        "Quote: puts what you selected (or the whole answer) in the message box (⇧⌘')"))
            }
            if let fork, !conversation.isRunning {
                Button(action: fork) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: size * 0.85)).foregroundStyle(Theme.textMuted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Buradan yeni sohbet aç (bu noktaya kadarki konuşmayla)", "New chat from here (with the conversation so far)"))
            }
            if isLast && !conversation.isRunning {
                Menu {
                    Button(L("Yeniden yaz", "Write again"), systemImage: "arrow.clockwise") { conversation.regenerate() }
                    Section(L("Başka AI ile", "With another AI")) {
                        ForEach(AIEngine.order.filter { $0 != engine && AIEngines.shared.isAvailable($0) }) { other in
                            Button(other.title) {
                                conversation.use(other, model: other.chosenModel)
                                conversation.regenerate()
                            }
                        }
                    }
                    let models = AIEngines.shared.models(for: engine).filter { $0.id != conversation.model }
                    if !models.isEmpty {
                        Section(L("Başka modelle", "With another model")) {
                            ForEach(models) { option in
                                Button(option.title) {
                                    conversation.use(engine, model: option.id)
                                    conversation.regenerate()
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: size * 0.85)).foregroundStyle(Theme.textMuted)
                } primaryAction: {
                    conversation.regenerate()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .tint(Theme.textMuted)
                .fixedSize()
                .help(L("Yeniden yaz (basılı tut: başka AI ya da model)", "Write again (hold: another AI or model)"))
            }
            if message.stopped { Text(L("Durduruldu", "Stopped")).font(.system(size: size * 0.8)).foregroundStyle(Theme.textMuted) }
        }
    }

    private var details: String {
        var parts = [AIEngines.shared.displayName(message.model ?? "", engine: engine)]
        parts.append(Calendar.current.isDateInToday(message.date) ? message.date.formatted(date: .omitted, time: .shortened)
                                                                  : message.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
        if let duration = message.duration {
            parts.append(duration < 60 ? L("\(max(1, Int(duration.rounded()))) sn", "\(max(1, Int(duration.rounded())))s")
                                       : L("\(Int(duration / 60)) dk", "\(Int(duration / 60))m"))
        }
        return parts.joined(separator: " · ")
    }
}

/// "Thinking…" while it reasons, then "Thought process"; open it to read the reasoning.
private struct ThinkingDisclosure: View {
    let message: AIMessage
    let engine: AIEngine
    let size: CGFloat
    @State private var open = false

    var body: some View {
        let live = message.streaming && message.text.isEmpty
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } } label: {
                HStack(spacing: Theme.Spacing.s) {
                    if live {
                        AIThinkingLabel(engine: engine, text: L("Düşünüyor…", "Thinking…"), size: size * 0.92)
                    } else {
                        Image(systemName: "brain.filled.head.profile").font(.system(size: size * 0.85))
                        Text(L("Düşünce süreci", "Thought process")).font(.system(size: size * 0.9))
                    }
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: size * 0.7))
                }
                .foregroundStyle(Theme.textMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open || live {
                HStack(spacing: size * 0.7) {
                    Capsule().fill(Theme.hairline).frame(width: 2)
                    Text(verbatim: open ? message.thinking : String(message.thinking.suffix(240)))
                        .font(.system(size: size * 0.88))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(open ? nil : 3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
