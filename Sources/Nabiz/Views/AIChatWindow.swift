import AppKit
import SwiftUI
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
}

@MainActor
@Observable
final class AIChatState {
    var selection: UUID? {
        didSet { if let chat = conversation, chat.unread { chat.unread = false; AIChatStore.shared.scheduleSave() } }
    }
    var draft = ""
    var attachments: [AIAttachment] = []
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
        draft = ""
        attachments = []
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
        if fromBox, !attachments.isEmpty {
            attachment = attachments.count == 1 ? attachments[0].text
                : attachments.map { "<\($0.name)>\n\($0.text)\n</\($0.name)>" }.joined(separator: "\n\n")
            attachmentName = attachments.map(\.name).joined(separator: ", ")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil else { return }
        let conversation: AIConversation
        if let current = self.conversation {
            guard !current.isRunning else { return }
            conversation = current
        } else {
            conversation = AIConversation(engine: engine, model: model)
            conversation.folder = newChatFolder
            AIChatStore.shared.touch(conversation)
            selection = conversation.id
        }
        conversation.send(text, attachment: attachment, prompt: prompt, attachmentName: attachmentName)
        if fromBox {
            draft = ""
            attachments = []
        }
    }

    /// Puts a message of yours back in the box to change and send again.
    func edit(_ message: AIMessage) {
        guard let conversation, let taken = conversation.takeBack(message.id) else { return }
        draft = taken.text
        if let text = taken.attachment { attachments = [AIAttachment(name: taken.attachmentName ?? L("Ek", "Attachment"), text: text)] }
        focusComposer += 1
    }

    func attach(file url: URL) {
        guard let data = try? Data(contentsOf: url), data.count < 400_000,
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Monitor.panelActions.flash(L("Bu dosya metin olarak okunamadı", "This file couldn't be read as text"))
            return
        }
        attachments.append(AIAttachment(name: url.lastPathComponent, text: text))
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
            SidebarSearchField(text: $state.query) {}
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
        VStack(spacing: 0) {
            if let conversation, !conversation.messages.isEmpty {
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
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
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
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if !state.attachments.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: Theme.Spacing.s) {
                            ForEach(state.attachments) { attachment in
                                AttachmentCard(attachment: attachment) {
                                    withAnimation(.easeOut(duration: 0.15)) { state.attachments.removeAll { $0.id == attachment.id } }
                                }
                            }
                        }
                        .padding(.top, 6)
                        .padding(.trailing, 6)
                    }
                    .scrollIndicators(.never)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                TextField(running ? L("\(engine.shortName) yazıyor…", "\(engine.shortName) is writing…")
                                  : L("\(engine.shortName)'a yaz…", "Message \(engine.shortName)…"),
                          text: $state.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...12)
                    .lineSpacing(3)
                    .tint(brand.multicolor ? brand.colors[1] : brand.tint)
                    .focused($focused)
                    .onSubmit { state.send() }
                    .onExitCommand { conversation?.stop() }
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
                    Spacer(minLength: 0)
                    if state.draft.count > 1_000 {
                        Text(verbatim: state.draft.count.formatted()).font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted)
                    }
                    AISendButton(engine: engine, running: running, enabled: state.canSend) {
                        if running { conversation?.stop() } else { state.send() }
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
            Image(systemName: attachment.symbol)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 30, height: 30)
                .background(Theme.track, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: attachment.name).font(Theme.small.weight(.medium)).foregroundStyle(Theme.text).lineLimit(1)
                Text(L("\(attachment.text.split(whereSeparator: \.isNewline).count) satır", "\(attachment.text.split(whereSeparator: \.isNewline).count) lines"))
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
        .help(String(attachment.text.prefix(300)))
    }
}

/// "+": a text file, or what you copied.
private struct AddMenu: View {
    let state: AIChatState

    var body: some View {
        Menu {
            Button(L("Dosya ekle…", "Add a file…"), systemImage: "doc.badge.plus") { pickFile() }
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

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.text, .plainText, .sourceCode, .json, .xml, .commaSeparatedText, .html, .yaml]
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
        .onAppear { engines.refreshIfNeeded() }
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
                                .id(message.id)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            AIAnswer(message: message, conversation: conversation, size: size, compact: compact,
                                     isLast: message.id == conversation.messages.last?.id)
                                .transition(.opacity)
                        }
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
                if let attachment = message.attachment { AttachmentChip(text: attachment, name: message.attachmentName, size: size) }
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
                }
            }
        }
        .onHover { over in withAnimation(.easeOut(duration: 0.12)) { hovering = over } }
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
    @State private var hovering = false

    private var engine: AIEngine { message.engine ?? conversation.engine }

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.7) {
            if !message.thinking.isEmpty {
                ThinkingDisclosure(message: message, engine: engine, size: size)
            }
            if message.text.isEmpty && message.streaming {
                if message.thinking.isEmpty { AIThinkingLabel(engine: engine, size: size) }
                if !compact { AISkeleton(color: engine.brand.tint).frame(maxWidth: 480) }
            } else if !message.text.isEmpty {
                MarkdownView(text: message.text, size: size, tint: engine.brand.multicolor ? engine.brand.colors[1] : engine.brand.tint)
            }
            if message.streaming && !message.text.isEmpty {
                AIBrandMark(engine: engine, size: size, animating: true)
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
            AICopyButton(text: message.text, size: size * 0.85, label: false)
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
