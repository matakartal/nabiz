// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit

/// Asking AI from the launcher: "?" (or ⌃⌥A) switches to it; ↩ asks; the chat then shows in place, and ⌘O moves it
/// to the AI window. Selected or copied text gets ready-made tasks; recent chats can be picked up again.
extension LauncherModel {
    func aiSections(_ question: String) -> [LauncherSection] {
        var sections: [LauncherSection] = []
        if !question.isEmpty {
            sections.append(LauncherSection(id: "ai", title: "AI", items: [askItem(question)]))
        }
        if let selectedText {
            sections.append(LauncherSection(id: "selection", title: L("Seçili metin", "Selected text"),
                                            items: filtered(aiTaskItems(selectedText, source: "sel"), question)))
        } else if let clip = ClipboardHistory.shared.items.first(where: { $0.text != nil && $0.kind == .text }), let text = clip.text,
                  !SecretText.looksSecret(text) {
            sections.append(LauncherSection(id: "copied", title: L("Son kopyalanan", "Last copied"),
                                            items: filtered(aiTaskItems(text, source: "clip"), question)))
        }
        let store = AIChatStore.shared
        store.loadIfNeeded()
        let chats = store.conversations.filter { chat in
            !chat.messages.isEmpty && (question.isEmpty || Fuzzy.contains(question, chat.title))
        }
        var chatItems = chats.prefix(question.isEmpty ? 5 : 3).map(chatItem)
        if question.isEmpty {
            chatItems.append(LauncherItem(id: "ai:window", icon: .symbol("macwindow"), title: L("AI sohbet penceresini aç", "Open the AI chat window"),
                                          primaryTitle: L("Aç", "Open"), primary: { [weak self] in
                                              self?.close()
                                              AIChatWindow.show()
                                          }, remember: false))
        }
        sections.append(LauncherSection(id: "chats", title: L("Sohbetler", "Chats"), items: chatItems))
        return sections.filter { !$0.items.isEmpty }
    }

    private func filtered(_ items: [LauncherItem], _ query: String) -> [LauncherItem] {
        query.isEmpty ? items : items.filter { Fuzzy.score(query, $0.title) != nil }
    }

    func askItem(_ question: String) -> LauncherItem {
        let engine = AIEngines.shared.resolve(AIEngine.chosen)
        return LauncherItem(id: "ai:ask", icon: .symbol("sparkles"), title: question,
                            subtitle: engine.map { L("\($0.shortName)'a sor", "Ask \($0.shortName)") },
                            accessory: engine.map { AIEngines.shared.displayName($0.chosenModel, engine: $0) },
                            primaryTitle: L("Sor", "Ask"),
                            primary: { [weak self] in self?.ask(question) },
                            secondaryTitle: L("Pencerede sor", "Ask in the window"),
                            secondary: { [weak self] in
                                self?.close()
                                AIChatWindow.state.newChat()
                                AIChatWindow.show()
                                AIChatWindow.state.send(question)
                            },
                            remember: false)
    }

    func aiTaskItems(_ text: String, source: String) -> [LauncherItem] {
        let preview = text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(60)) } ?? ""
        return AITextTask.allCases.map { task in
            LauncherItem(id: "ai:\(source):\(task.rawValue)", icon: .symbol(task.symbol), title: task.title, subtitle: preview,
                         accessory: "AI", primaryTitle: L("Çalıştır", "Run"),
                         primary: { [weak self] in self?.runAI(task, on: text) },
                         remember: false)
        }
    }

    private func chatItem(_ chat: AIConversation) -> LauncherItem {
        LauncherItem(id: "ai:chat:\(chat.id)", icon: .symbol("bubble.left.and.bubble.right"), title: chat.title,
                     subtitle: chat.engine.shortName,
                     accessory: chat.updated.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated).locale(Format.locale)),
                     primaryTitle: L("Devam et", "Continue"),
                     primary: { [weak self] in self?.open(chat) },
                     secondaryTitle: L("Pencerede aç", "Open in the window"),
                     secondary: { [weak self] in
                         self?.close()
                         AIChatWindow.show(chat)
                     },
                     remember: false)
    }

    // MARK: Running

    /// A new chat with this question, or the next message in the open one.
    func ask(_ question: String, attachment: String? = nil, prompt: String? = nil) {
        let engines = AIEngines.shared
        // The CLIs are still being looked for (first open): wait for that instead of picking the wrong one.
        guard engines.searched else {
            engines.refreshIfNeeded()
            Task { [weak self] in
                for _ in 0..<100 where !engines.searched { try? await Task.sleep(for: .milliseconds(50)) }
                guard engines.searched else { return }
                self?.ask(question, attachment: attachment, prompt: prompt)
            }
            return
        }
        if mode == .ai, let chat = ai {
            chat.send(question, attachment: attachment, prompt: prompt)
            text = ""
            return
        }
        guard let engine = engines.resolve(AIEngine.chosen) else {
            Monitor.panelActions.flash(engines.problem(AIEngine.chosen) ?? L("Kurulu bir AI yok", "No AI is set up"))
            return
        }
        let chat = AIConversation(engine: engine)
        AIChatStore.shared.touch(chat)
        open(chat)
        chat.send(question, attachment: attachment, prompt: prompt)
    }

    func open(_ chat: AIConversation) {
        chat.unread = false
        paletteOpen = false
        mode = .ai
        ai = chat
        text = ""
    }

    func runAI(_ task: AITextTask, on text: String) {
        ai = nil
        mode = .ai
        ask(task.title, attachment: text, prompt: task.prompt(text))
    }

    /// ↩: a typed message is sent; otherwise the last answer is copied.
    func aiReturn() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
            if let chat = ai, chat.isRunning {
                queue(message, after: chat)
                return
            }
            ask(message)
        } else if let answer = ai?.lastAnswer?.text, !answer.isEmpty, ai?.isRunning == false {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(answer, forType: .string)
            close()
            Monitor.panelActions.flash(L("Cevap kopyalandı", "Answer copied"))
        }
    }

    /// Keeps a follow-up typed during an answer and sends it when that answer ends (in the same chat only).
    private func queue(_ message: String, after chat: AIConversation) {
        let waiting = queuedFollowUp != nil
        queuedFollowUp = queuedFollowUp.map { $0 + "\n" + message } ?? message
        text = ""
        guard !waiting else { return }
        let id = chat.id
        Task { [weak self] in
            while chat.isRunning { try? await Task.sleep(for: .milliseconds(150)) }
            guard let self, let next = self.queuedFollowUp else { return }
            self.queuedFollowUp = nil
            guard self.mode == .ai, self.ai?.id == id else { return }
            self.ask(next)
        }
    }

    /// ⌘↩: the answer goes where the cursor was.
    func aiPaste() {
        guard let chat = ai, !chat.isRunning, let answer = chat.lastAnswer?.text, !answer.isEmpty else { return }
        paste(text: answer)
    }

    /// Escape: stop a running answer, then clear the box, then go back to the list.
    func aiEscape() {
        if let chat = ai, chat.isRunning {
            // Stopping drops a waiting follow-up too, and puts it back in the box to edit.
            if let queued = queuedFollowUp, text.isEmpty { text = queued }
            queuedFollowUp = nil
            chat.stop()
        } else if !text.isEmpty {
            text = ""
        } else {
            ai = nil
        }
    }

    func openInWindow() {
        guard let chat = ai else { return }
        close()
        AIChatWindow.show(chat)
    }

    func aiActions() -> [LauncherAction] {
        guard let chat = ai else { return [] }
        var list: [LauncherAction] = []
        let main = L("Eylemler", "Actions")
        let answer = chat.lastAnswer?.text ?? ""
        if !chat.isRunning && !answer.isEmpty {
            list.append(LauncherAction(id: "aiCopy", title: L("Cevabı kopyala", "Copy the answer"), symbol: "doc.on.doc", shortcut: "↩", group: main) { [weak self] in
                self?.text = ""
                self?.aiReturn()
            })
            list.append(LauncherAction(id: "aiPaste", title: L("Yapıştır", "Paste"), symbol: "doc.on.clipboard", shortcut: "⌘↩", group: main) { [weak self] in
                self?.aiPaste()
            })
        }
        list.append(LauncherAction(id: "aiWindow", title: L("Pencerede aç", "Open in the window"), symbol: "macwindow", shortcut: "⌘O", group: main) { [weak self] in
            self?.openInWindow()
        })
        if chat.isRunning {
            list.append(LauncherAction(id: "aiStop", title: L("Durdur", "Stop"), symbol: "stop.circle", shortcut: "esc", group: main) { chat.stop() })
        } else {
            list.append(LauncherAction(id: "aiAgain", title: L("Yeniden yaz", "Write again"), symbol: "arrow.clockwise", shortcut: "⌘R", group: main) {
                chat.regenerate()
            })
        }
        if !answer.isEmpty {
            list.append(LauncherAction(id: "aiNote", title: L("Not olarak kaydet", "Save as note"), symbol: "note.text.badge.plus", group: main) { [weak self] in
                self?.close()
                if Prefs.string(Prefs.notesApp) == "apple" { AppleNotes.create(answer) } else { NoteWindow.show(NoteStore.shared.create(answer)) }
            })
        }
        list.append(LauncherAction(id: "aiNew", title: L("Yeni sohbet", "New chat"), symbol: "square.and.pencil", shortcut: "⌘N", group: main) { [weak self] in
            self?.ai = nil
            self?.text = ""
        })
        let engines = AIEngines.shared
        let again = L("Başka AI ile yeniden yaz", "Write again with another AI")
        for engine in AIEngine.order where engine != chat.engine && engines.isAvailable(engine) {
            list.append(LauncherAction(id: "aiWith-\(engine.rawValue)", title: engine.title, symbol: "sparkles", group: again) {
                chat.use(engine, model: engine.chosenModel)
                chat.regenerate()
            })
        }
        let models = L("Model", "Model")
        for option in engines.models(for: chat.engine) where option.id != chat.model {
            list.append(LauncherAction(id: "aiModel-\(option.id)", title: option.title, symbol: "cpu", group: models) {
                chat.use(chat.engine, model: option.id)
                chat.engine.setChosenModel(option.id)
            })
        }
        list.append(LauncherAction(id: "aiSettings", title: L("AI ayarları", "AI settings"), symbol: "gearshape", group: models) { [weak self] in
            self?.close()
            SettingsWindow.show(.ai)
        })
        return list
    }
}
