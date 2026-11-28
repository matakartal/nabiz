// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import SwiftUI

/// Notes that float over every app and Space. ⌃⌥M shows or hides them. The first line is a note's title; Markdown
/// lists and checklists continue on Return, and a checkbox ticks with a click or ⌘L.
@MainActor
enum NoteWindow {
    private static var panel: NotePanel?
    private static var keyMonitor: Any?
    /// The editor on screen, for the keyboard shortcuts.
    static weak var editor: NoteTextView?
    /// Toggled by ⌘P; the view shows the list while it is set.
    static let state = NoteWindowState()

    static var isVisible: Bool { panel?.isVisible == true }

    static func toggle() {
        if Prefs.string(Prefs.notesApp) == "apple" { AppleNotes.open(); return }
        if isVisible { close() } else { show() }
    }

    /// Shows the note window, on the given note or the last one open (a new one if there are none).
    static func show(_ id: UUID? = nil) {
        if Prefs.string(Prefs.notesApp) == "apple" { AppleNotes.open(); return }
        let store = NoteStore.shared
        if let id { store.select(id) }
        if store.current == nil { store.create() }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.contentViewController == nil { panel.contentViewController = NSHostingController(rootView: NoteView()) }
        applyLevel()
        panel.makeKeyAndOrderFront(nil)
        installKeys()
        DispatchQueue.main.async { if let editor { editor.window?.makeFirstResponder(editor) } }
    }

    static func close() {
        state.listOpen = false
        NoteStore.shared.dropEmpty()
        NoteStore.shared.saveNow()
        panel?.orderOut(nil)
        // The editor is rebuilt next time; nothing of it stays in memory meanwhile.
        panel?.contentViewController = nil
        editor = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Floats over everything, or behaves like a normal window, from the pin button.
    static func applyLevel() {
        panel?.level = Prefs.bool(Prefs.noteOnTop) ? .floating : .normal
    }

    private static func makePanel() -> NotePanel {
        let panel = NotePanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.minSize = NSSize(width: 280, height: 220)
        panel.contentViewController = NSHostingController(rootView: NoteView())
        panel.setFrameAutosaveName("NabizNote")
        if !panel.setFrameUsingName("NabizNote"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrame(NSRect(x: screen.maxX - 400, y: screen.maxY - 460, width: 380, height: 440), display: false)
        }
        return panel
    }

    /// The note's shortcuts, read before the text view sees them (Nabız has no menu bar while another app is in front).
    private static func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode, flags = event.modifierFlags, key = event.charactersIgnoringModifiers?.lowercased()
            let window = event.window.map(ObjectIdentifier.init)
            let handled = MainActor.assumeIsolated {
                guard let panel, window == ObjectIdentifier(panel) else { return false }
                return handle(keyCode: keyCode, flags: flags, key: key)
            }
            return handled ? nil : event
        }
    }

    private static func handle(keyCode: UInt16, flags: NSEvent.ModifierFlags, key: String?) -> Bool {
        let store = NoteStore.shared
        if keyCode == 53 {
            if state.listOpen { state.listOpen = false } else { close() }
            return true
        }
        guard flags.contains(.command), let key else { return false }
        let shift = flags.contains(.shift)
        switch key {
        case "n": NoteWindow.show(store.create())
        case "p": state.listOpen.toggle()
        case "w": close()
        case "[": store.step(1)
        case "]": store.step(-1)
        case "l": editor?.toggleList(shift ? .bullet : .checklist)
        case "b": editor?.wrap("**")
        case "i": editor?.wrap("_")
        case "c" where shift: copyCurrent()
        // Editing keys go to whatever has the cursor: the note, or the list's search field.
        case "c": sendEdit(#selector(NSText.copy(_:)))
        case "v": if inEditor { editor?.pasteAsPlainText(nil) } else { sendEdit(#selector(NSText.paste(_:))) }
        case "x": sendEdit(#selector(NSText.cut(_:)))
        case "a": sendEdit(#selector(NSText.selectAll(_:)))
        case "z": sendEdit(shift ? Selector(("redo:")) : Selector(("undo:")))
        default: return false
        }
        return true
    }

    /// The note's own editor has the cursor (not the list's search field).
    private static var inEditor: Bool {
        guard let editor else { return false }
        return panel?.firstResponder === editor
    }

    /// To the first responder of the note window, which is key while it takes typing.
    private static func sendEdit(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    static func copyCurrent() {
        guard let note = NoteStore.shared.current, !note.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.text, forType: .string)
        Monitor.panelActions.flash(L("Not kopyalandı", "Note copied"))
    }

    static func export(_ note: Note) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = note.title.replacingOccurrences(of: "/", with: "-") + ".md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? note.text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Asks first unless the note is empty: deleting can't be undone.
    static func delete(_ note: Note) {
        if !note.isEmpty {
            let alert = NSAlert()
            alert.messageText = L("“\(note.title)” silinsin mi?", "Delete “\(note.title)”?")
            alert.informativeText = L("Bu geri alınamaz.", "This can't be undone.")
            alert.addButton(withTitle: L("Sil", "Delete"))
            alert.addButton(withTitle: L("Vazgeç", "Cancel"))
            alert.buttons.first?.hasDestructiveAction = true
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        NoteStore.shared.delete(note.id)
        // Deleted from the launcher with the window closed: it stays closed (its view is gone until shown again).
        guard isVisible else { return }
        if NoteStore.shared.current == nil { close() } else { panel?.makeKeyAndOrderFront(nil) }
    }
}

@MainActor
@Observable
final class NoteWindowState {
    var listOpen = false
}

final class NotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { NoteWindow.close() }
}

struct NoteView: View {
    private let store = NoteStore.shared
    private let state = NoteWindow.state
    @AppStorage(Prefs.noteOnTop) private var onTop = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            if let note = store.current {
                NoteEditor(id: note.id, text: note.text).id(note.id)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                footer(note)
            } else {
                Spacer()
            }
        }
        .overlay(alignment: .topLeading) {
            if state.listOpen {
                NoteList { state.listOpen = false }
                    .padding(.top, Theme.noteHeader)
                    .transition(.opacity)
            }
        }
        // The header takes the title bar's place, so there's no empty strip above it.
        .ignoresSafeArea(edges: .top)
        .frame(minWidth: 280, minHeight: 220)
        .background(MenuMaterial().ignoresSafeArea())
        .appearanceRoot(opaqueFill: Theme.surface)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            IconButton(symbol: state.listOpen ? "xmark" : "list.bullet", help: L("Tüm notlar (⌘P)", "All notes (⌘P)")) {
                state.listOpen.toggle()
            }
            Text(verbatim: store.current?.title ?? L("Notlar", "Notes"))
                .font(Theme.bodyStrong).foregroundStyle(Theme.text).lineLimit(1)
            if store.notes.count > 1 {
                Text(verbatim: "\(store.notes.count)").font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: Theme.Spacing.s)
            IconButton(symbol: onTop ? "pin.fill" : "pin", help: onTop ? L("Üstte tutmayı bırak", "Stop floating on top") : L("Üstte tut", "Float on top"),
                       active: onTop) {
                onTop.toggle()
                NoteWindow.applyLevel()
            }
            IconButton(symbol: "square.and.pencil", help: L("Yeni not (⌘N)", "New note (⌘N)")) { NoteWindow.show(store.create()) }
            Menu {
                if let note = store.current {
                    Button(L("Kopyala (⇧⌘C)", "Copy (⇧⌘C)")) { NoteWindow.copyCurrent() }.disabled(note.isEmpty)
                    Button(L("Markdown olarak kaydet…", "Save as Markdown…")) { NoteWindow.export(note) }.disabled(note.isEmpty)
                    Divider()
                    Button(L("Önceki not (⌘[)", "Previous note (⌘[)")) { store.step(1) }.disabled(store.notes.count < 2)
                    Button(L("Sonraki not (⌘])", "Next note (⌘])")) { store.step(-1) }.disabled(store.notes.count < 2)
                    Divider()
                    Button(L("Notu sil…", "Delete note…"), role: .destructive) { NoteWindow.delete(note) }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(Theme.body).foregroundStyle(Theme.textMuted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .tint(Theme.textMuted)
            .help(L("Diğer", "More"))
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(height: Theme.noteHeader)
    }

    private func footer(_ note: Note) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: Theme.Spacing.m) {
                Text(L("\(note.words) kelime", "\(note.words) words"))
                let list = note.checklist
                if list.total > 0 {
                    Label("\(list.done)/\(list.total)", systemImage: list.done == list.total ? "checkmark.circle.fill" : "checklist")
                        .foregroundStyle(list.done == list.total ? Palette.green.mark : Theme.textMuted)
                }
                Spacer()
                Text(note.modified.formatted(.relative(presentation: .named).locale(Format.locale)))
            }
            .font(Theme.small)
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: Theme.launcherFooter)
        }
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(Theme.body).foregroundStyle(active ? Theme.accent : Theme.textMuted)
                .frame(width: Theme.menuIcon + Theme.Spacing.xs, height: Theme.menuIcon + Theme.Spacing.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Every note, last edited first, with a search field. Fills the window under the header.
private struct NoteList: View {
    let done: () -> Void
    @State private var query = ""
    @FocusState private var focused: Bool
    private let store = NoteStore.shared

    var body: some View {
        let notes = store.sorted.filter { note in
            query.isEmpty || Fuzzy.contains(query, note.text)
        }
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textMuted)
                TextField(L("Notlarda ara", "Search notes"), text: $query).textFieldStyle(.plain).focused($focused)
            }
            .font(Theme.body)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: Theme.noteHeader)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(notes) { note in
                        Button {
                            store.select(note.id)
                            done()
                            NoteWindow.show()
                        } label: {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                                HStack {
                                    Text(verbatim: note.title).font(Theme.bodyStrong).foregroundStyle(Theme.text).lineLimit(1)
                                    Spacer()
                                    Text(note.modified.formatted(.relative(presentation: .named).locale(Format.locale)))
                                        .font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize()
                                }
                                if !note.preview.isEmpty {
                                    Text(verbatim: note.preview).font(Theme.small).foregroundStyle(Theme.textMuted).lineLimit(2)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.s)
                            .padding(.vertical, Theme.Spacing.s)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(note.id == store.currentID ? Theme.hover : .clear,
                                        in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(L("Sil…", "Delete…"), role: .destructive) { NoteWindow.delete(note) }
                        }
                    }
                    if notes.isEmpty {
                        Text(L("Eşleşen not yok", "No matching notes")).font(Theme.small).foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity).padding(.top, Theme.Spacing.xl)
                    }
                }
                .padding(Theme.Spacing.xs)
            }
            .scrollIndicators(.never)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Button {
                done()
                NoteWindow.show(store.create())
            } label: {
                Label(L("Yeni not", "New note"), systemImage: "plus").font(Theme.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TextButtonStyle(color: Theme.accent))
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: Theme.launcherFooter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MenuMaterial(blending: .withinWindow))
        .onAppear { focused = true }
    }
}

// MARK: - Editor

/// A plain-text editor that shows its Markdown: headings big, list markers in the accent colour, ticked items struck
/// through, `code` monospaced, **bold** bold, links clickable.
struct NoteEditor: NSViewRepresentable {
    let id: UUID
    let text: String

    func makeCoordinator() -> Coordinator { Coordinator(id: id) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        let textView = NoteTextView(usingTextLayoutManager: false)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: Theme.Spacing.m, height: Theme.Spacing.m)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.insertionPointColor = NSColor(Theme.accent)
        textView.delegate = context.coordinator
        textView.string = text
        textView.restyle()
        scroll.documentView = textView
        NoteWindow.editor = textView
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NoteTextView, textView.string != text else { return }
        textView.string = text
        textView.restyle()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let id: UUID
        init(id: UUID) { self.id = id }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NoteTextView else { return }
            MainActor.assumeIsolated {
                textView.restyle()
                NoteStore.shared.update(id, text: textView.string)
            }
        }
    }
}

final class NoteTextView: NSTextView {
    // MARK: Lists

    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let selection = selectedRange()
        guard selection.length == 0 else { return super.insertNewline(sender) }
        let line = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        let before = NSRange(location: line.location, length: selection.location - line.location)
        switch NoteMarkdown.onReturn(ns.substring(with: before)) {
        case .plain: super.insertNewline(sender)
        case .end: insertText("", replacementRange: before)
        case .next(let text): insertText(text, replacementRange: selection)
        }
    }

    /// ⌘L: checklist on or off for the selected lines; ⇧⌘L: bullets.
    func toggleList(_ kind: NoteMarkdown.ListKind) {
        let ns = string as NSString
        let lines = ns.lineRange(for: selectedRange())
        let text = ns.substring(with: lines)
        let hasNewline = text.hasSuffix("\n")
        let body = hasNewline ? String(text.dropLast()) : text
        let changed = body.components(separatedBy: "\n").map { NoteMarkdown.toggled($0, kind) }.joined(separator: "\n") + (hasNewline ? "\n" : "")
        insertText(changed, replacementRange: lines)
        let length = (changed as NSString).length - (hasNewline ? 1 : 0)
        setSelectedRange(NSRange(location: lines.location + length, length: 0))
    }

    /// ⌘B / ⌘I: wraps the selection, or puts the cursor between a new pair.
    func wrap(_ marker: String) {
        let selection = selectedRange()
        let selected = (string as NSString).substring(with: selection)
        insertText(marker + selected + marker, replacementRange: selection)
        if selection.length == 0 {
            setSelectedRange(NSRange(location: selection.location + (marker as NSString).length, length: 0))
        }
    }

    // MARK: Checkboxes

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let ns = string as NSString
        if ns.length > 0 {
            let line = ns.lineRange(for: NSRange(location: min(index, ns.length - 1), length: 0))
            if let box = NoteMarkdown.checkbox(in: ns.substring(with: line)) {
                let start = line.location + box.location
                if index >= start && index <= start + box.length {
                    let mark = NSRange(location: start + 1, length: 1)
                    let ticked = ns.substring(with: mark) != " "
                    if shouldChangeText(in: mark, replacementString: ticked ? " " : "x") {
                        textStorage?.replaceCharacters(in: mark, with: ticked ? " " : "x")
                        didChangeText()
                    }
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: Styling

    private static let heading = try! NSRegularExpression(pattern: #"^(#{1,3}) +\S.*$"#, options: .anchorsMatchLines)
    private static let checklist = try! NSRegularExpression(pattern: #"^([ \t]*[-*•] )\[([ xX])\]( .*)?$"#, options: .anchorsMatchLines)
    private static let bullet = try! NSRegularExpression(pattern: #"^[ \t]*([-*•]|\d{1,4}[.)]) (?!\[[ xX]\])"#, options: .anchorsMatchLines)
    private static let quote = try! NSRegularExpression(pattern: #"^> ?.*$"#, options: .anchorsMatchLines)
    private static let code = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)
    private static let bold = try! NSRegularExpression(pattern: #"\*\*[^*\n]+\*\*"#)
    private static let italic = try! NSRegularExpression(pattern: #"(?<![\w*])_[^_\n]+_(?!\w)"#)
    private static let links = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Re-applies the look from the text; only attributes change, so undo and the cursor are untouched.
    func restyle() {
        guard let storage = textStorage else { return }
        let ns = string as NSString
        let all = NSRange(location: 0, length: ns.length)
        let base = Theme.nsFont(size: Theme.noteText)
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = Theme.Spacing.xs
        paragraph.lineSpacing = 2
        let accent = NSColor(Theme.accent)
        let baseAttributes: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: all)
        for match in Self.heading.matches(in: string, range: all) {
            let level = match.range(at: 1).length
            let size = level == 1 ? Theme.noteHeading : level == 2 ? Theme.noteSubheading : Theme.noteText
            storage.addAttribute(.font, value: Theme.nsFont(size: size, weight: level == 1 ? .bold : .semibold), range: match.range)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: match.range(at: 1))
        }
        for match in Self.checklist.matches(in: string, range: all) {
            let box = NSRange(location: match.range(at: 2).location - 1, length: 3)
            let ticked = ns.substring(with: match.range(at: 2)) != " "
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: match.range(at: 1))
            storage.addAttributes([.foregroundColor: ticked ? accent : NSColor.secondaryLabelColor,
                                   .font: Theme.nsFont(size: Theme.noteText, weight: .semibold),
                                   .cursor: NSCursor.pointingHand], range: box)
            if ticked, match.range(at: 3).length > 1 {
                // From the first letter, not the space after the box.
                let item = NSRange(location: match.range(at: 3).location + 1, length: match.range(at: 3).length - 1)
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                       .foregroundColor: NSColor.secondaryLabelColor], range: item)
            }
        }
        for match in Self.bullet.matches(in: string, range: all) {
            storage.addAttribute(.foregroundColor, value: accent, range: match.range(at: 1))
        }
        for match in Self.quote.matches(in: string, range: all) {
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
        }
        for match in Self.bold.matches(in: string, range: all) {
            storage.addAttribute(.font, value: Theme.nsFont(size: Theme.noteText, weight: .bold), range: match.range)
            dim(storage, NSRange(location: match.range.location, length: 2))
            dim(storage, NSRange(location: NSMaxRange(match.range) - 2, length: 2))
        }
        for match in Self.italic.matches(in: string, range: all) {
            storage.addAttribute(.font, value: NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask), range: match.range)
        }
        for match in Self.code.matches(in: string, range: all) {
            storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: Theme.noteText - 1, weight: .regular),
                                   .backgroundColor: NSColor.quaternaryLabelColor], range: match.range)
        }
        for match in Self.links?.matches(in: string, range: all) ?? [] {
            if let url = match.url { storage.addAttributes([.link: url, .cursor: NSCursor.pointingHand], range: match.range) }
        }
        storage.endEditing()
        typingAttributes = baseAttributes
        linkTextAttributes = [.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue]
    }

    private func dim(_ storage: NSTextStorage, _ range: NSRange) {
        storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
    }
}

/// For people who keep their notes in Apple Notes: Nabız's note shortcuts open it instead.
@MainActor
enum AppleNotes {
    static func open() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Notes.app"), configuration: NSWorkspace.OpenConfiguration())
    }

    /// A new note in Apple Notes with this text (macOS asks once for permission to control Notes).
    static func create(_ text: String) {
        let body = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Notes\"\nactivate\nshow (make new note with properties {body:\"\(body)\"})\nend tell")?
            .executeAndReturnError(&error)
        if error != nil { open() }
    }
}
