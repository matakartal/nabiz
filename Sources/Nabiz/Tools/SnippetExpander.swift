// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Carbon.HIToolbox

/// Snippets typed anywhere: the prefix and a snippet's keyword (";sig") are replaced by the snippet as soon as the
/// last letter is typed. Off by default; needs Accessibility. Only the last few letters typed are kept, in memory,
/// to spot a keyword — never written anywhere. Password fields and password managers are skipped.
@MainActor
final class SnippetExpander {
    static let shared = SnippetExpander()

    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var appObserver: NSObjectProtocol?
    /// The letters typed since the last click, app switch or non-typing key.
    private var typed = ""
    /// Our own backspaces and paste are passing through: not typing.
    private var expanding = false
    private static let keep = 64

    /// Starts or stops listening, following the setting and the permission.
    func update() {
        let on = Prefs.bool(Prefs.snippetExpand) && AXIsProcessTrusted()
        if on && keyMonitor == nil { start() } else if !on && keyMonitor != nil { stop() }
    }

    private func start() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode, flags = event.modifierFlags, characters = event.characters
            MainActor.assumeIsolated { SnippetExpander.shared.typedKey(keyCode, flags: flags, characters: characters) }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { SnippetExpander.shared.typed = "" }
        }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                        object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SnippetExpander.shared.typed = "" }
        }
    }

    private func stop() {
        [keyMonitor, mouseMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        keyMonitor = nil
        mouseMonitor = nil
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        appObserver = nil
        typed = ""
    }

    private func typedKey(_ keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) {
        guard !expanding else { return }
        // Shortcuts, arrows, Return, Tab and Escape end the word being typed.
        if !flags.intersection([.command, .control]).isEmpty { typed = ""; return }
        switch Int(keyCode) {
        case kVK_Delete:
            if !typed.isEmpty { typed.removeLast() }
            return
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_Escape, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete:
            typed = ""
            return
        default: break
        }
        guard let characters, !characters.isEmpty else { return }
        typed = String((typed + characters).suffix(Self.keep))
        guard let (snippet, length) = Self.match(typed, prefix: Prefs.string(Prefs.snippetPrefix), in: LauncherStore.shared.snippets) else { return }
        typed = ""
        expand(snippet, replacing: length)
    }

    /// The snippet whose prefix + keyword ends what was typed (the longest, if several do), and how many characters
    /// that trigger is. Without a prefix the keyword must start a word, so "tarih" doesn't fire inside "tarihi".
    static func match(_ typed: String, prefix: String, in snippets: [Snippet]) -> (Snippet, Int)? {
        let hits = snippets.compactMap { snippet -> (Snippet, Int)? in
            let keyword = snippet.keyword.trimmingCharacters(in: .whitespaces)
            guard !keyword.isEmpty else { return nil }
            let trigger = prefix + keyword
            guard typed.hasSuffix(trigger) else { return nil }
            if prefix.isEmpty, let before = typed.dropLast(trigger.count).last, before.isLetter || before.isNumber { return nil }
            return (snippet, trigger.count)
        }
        return hits.max { $0.1 < $1.1 }
    }

    private func expand(_ snippet: Snippet, replacing count: Int) {
        guard !IsSecureEventInputEnabled(), !Self.focusIsSecure(), !Self.frontIsExcluded() else { return }
        let (text, back) = snippet.expandedWithCursor
        expanding = true
        Task {
            // Let the last letter land before taking the keyword back out.
            try? await Task.sleep(for: .milliseconds(30))
            for _ in 0..<count { Paster.key(CGKeyCode(kVK_Delete)) }
            try? await Task.sleep(for: .milliseconds(40))
            Paster.paste(text, cursorBack: back, delay: .zero)
            try? await Task.sleep(for: .milliseconds(300))
            expanding = false
        }
    }

    /// The field with the cursor is a password field.
    private static func focusIsSecure() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success else { return false }
        return (subrole as? String) == (kAXSecureTextFieldSubrole as String)
    }

    /// Password managers and the apps the clipboard history skips.
    private static func frontIsExcluded() -> Bool {
        guard let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        let excluded = Set(ClipboardHistory.defaultExcluded).union(Prefs.string(Prefs.clipboardExcluded).split(separator: ",").map(String.init))
        return excluded.contains(bundle)
    }
}
