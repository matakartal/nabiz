// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit

/// A quicklink or a script waiting for what to search or pass. The field shows its name as a token and the text
/// typed is the query: "gh" + Tab (or Space) → "GitHub │ nabiz" → ↩ searches GitHub.
struct LauncherArgument {
    enum Target {
        case quicklink(Quicklink)
        case script(Extensions.Script)
    }

    let target: Target
    /// A script's values filled so far; it asks for them one at a time.
    var values: [String] = []

    var title: String {
        switch target {
        case .quicklink(let link): link.name
        case .script(let script): script.title
        }
    }

    var placeholder: String {
        switch target {
        case .quicklink(let link): return L("\(link.name) içinde ara…", "Search \(link.name)…")
        case .script(let script):
            let argument = script.arguments.indices.contains(values.count) ? script.arguments[values.count] : nil
            let name = argument?.placeholder ?? L("Değer \(values.count + 1)", "Value \(values.count + 1)")
            return argument?.optional == true ? L("\(name) (isteğe bağlı)", "\(name) (optional)") : name
        }
    }

    /// The value being typed is the last one asked for.
    var isLast: Bool {
        guard case .script(let script) = target else { return true }
        return values.count + 1 >= script.arguments.count
    }
}

extension LauncherModel {
    /// "gh " with a space typed right after a quicklink's keyword: that quicklink, to type the search after it.
    /// Not for the translate words, which ask AI instead.
    static func quicklink(forSpaceAfter text: String, in links: [Quicklink], translating: Bool) -> Quicklink? {
        guard text.hasSuffix(" ") else { return nil }
        let keyword = String(text.dropLast())
        guard !keyword.isEmpty, !keyword.contains(where: \.isWhitespace) else { return nil }
        if translating && TranslateQuery.text(in: keyword + " x") != nil { return nil }
        return links.first { $0.keyword.lowercased() == keyword.lowercased() && $0.takesQuery }
    }

    func enterArgument(_ target: LauncherArgument.Target) {
        paletteOpen = false
        argument = LauncherArgument(target: target)
        text = ""
    }

    /// Back to the normal search; Backspace on an empty quicklink query brings its keyword back to keep editing.
    func leaveArgument(keepKeyword: Bool = false) {
        guard let argument else { return }
        self.argument = nil
        if keepKeyword, case .quicklink(let link) = argument.target { text = link.keyword } else { text = "" }
    }

    /// Tab: a quicklink or script with values to ask for takes the field; in a script, the next value.
    /// Always handled in the main list, so Tab never moves the focus out of the field.
    func tab() -> Bool {
        guard mode == .all else { return false }
        if let argument {
            if case .script = argument.target, !argument.isLast { advanceArgument() }
            return true
        }
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        let links = LauncherStore.shared.quicklinks
        if let link = links.first(where: { $0.keyword.lowercased() == query && $0.takesQuery }) {
            enterArgument(.quicklink(link))
        } else if let item = selected {
            if let link = links.first(where: { "link:\($0.keyword)" == item.id && $0.takesQuery }) {
                enterArgument(.quicklink(link))
            } else if let script = Extensions.shared.scripts.first(where: { "script:\($0.path)" == item.id && !$0.arguments.isEmpty }) {
                enterArgument(.script(script))
            }
        }
        return true
    }

    /// The one row shown while a quicklink or script waits for its values.
    func argumentSections(_ argument: LauncherArgument) -> [LauncherSection] {
        let value = text.trimmingCharacters(in: .whitespaces)
        switch argument.target {
        case .quicklink(let link):
            let row = value.isEmpty
                ? LauncherItem(id: "arg:empty", icon: .symbol("magnifyingglass"), title: L("Aranacak şeyi yaz", "Type what to search for"),
                               subtitle: link.name, primaryTitle: L("Ara", "Search"), primary: {}, remember: false)
                : searchItem(link, value)
            return [LauncherSection(id: "argument", title: link.name, items: [row])]
        case .script(let script):
            let filled = (argument.values + [value]).filter { !$0.isEmpty }.joined(separator: " · ")
            let row = LauncherItem(id: "arg:script", icon: script.icon.map { .emoji($0) } ?? .symbol("terminal"), title: script.title,
                                   subtitle: filled.isEmpty ? nil : filled,
                                   accessory: "\(argument.values.count + 1)/\(script.arguments.count)",
                                   primaryTitle: argument.isLast ? L("Çalıştır", "Run") : L("Sonraki", "Next"),
                                   primary: { [weak self] in self?.advanceArgument() }, remember: false)
            return [LauncherSection(id: "argument", title: L("Betik", "Script"), items: [row])]
        }
    }

    /// ↩ in a script's value: keep it and ask for the next, or run with all of them.
    func advanceArgument() {
        guard var argument, case .script(let script) = argument.target else { return }
        let value = text.trimmingCharacters(in: .whitespaces)
        let index = argument.values.count
        if value.isEmpty, script.arguments.indices.contains(index), script.arguments[index].optional != true {
            NSSound.beep()
            return
        }
        argument.values.append(value)
        if argument.values.count >= script.arguments.count {
            runScript(script, arguments: argument.values)
        } else {
            self.argument = argument
            text = ""
        }
    }

    /// The launcher stays open with a busy line while the script runs (Esc stops it), and closes when it's done.
    func runScript(_ script: Extensions.Script, arguments: [String] = []) {
        Extensions.shared.run(script, arguments: arguments) { [weak self] in
            self?.argument = nil
            self?.close()
        }
    }
}
