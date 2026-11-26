// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Carbon.HIToolbox
import Observation

/// A launcher row given its own global shortcut ("⌥S opens Safari") or a short alias ("ss" for a screenshot).
struct ItemBinding: Codable, Identifiable, Equatable {
    /// The launcher item's stable id ("app:/Applications/Safari.app", "cmd:note").
    var id: String
    /// Its title when it was bound, for the Settings list.
    var title: String
    var alias: String?
    var combo: HotKey.Combo?

    var isEmpty: Bool { (alias ?? "").isEmpty && combo == nil }
}

@MainActor
@Observable
final class ItemBindings {
    static let shared = ItemBindings()
    private static let key = "launcherBindings"

    private(set) var all: [ItemBinding] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([ItemBinding].self, from: data) { all = saved }
    }

    func binding(_ id: String) -> ItemBinding? { all.first { $0.id == id } }

    /// The item an alias stands for, when the whole query is that alias.
    func id(forAlias query: String) -> String? {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return nil }
        return all.first { $0.alias?.lowercased() == query }?.id
    }

    func setAlias(_ alias: String?, id: String, title: String) {
        let alias = alias?.trimmingCharacters(in: .whitespaces).lowercased()
        update(id, title) { $0.alias = (alias ?? "").isEmpty ? nil : alias }
    }

    func setCombo(_ combo: HotKey.Combo?, id: String, title: String) {
        update(id, title) { $0.combo = combo }
        HotKey.registerItems()
    }

    func remove(_ id: String) {
        all.removeAll { $0.id == id }
        save()
        HotKey.registerItems()
    }

    private func update(_ id: String, _ title: String, _ change: (inout ItemBinding) -> Void) {
        var binding = binding(id) ?? ItemBinding(id: id, title: title)
        binding.title = title
        change(&binding)
        all.removeAll { $0.id == id }
        if !binding.isEmpty { all.append(binding) }
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: Self.key)
    }

    // MARK: Asking

    /// "ss", "saf": typed alone in the launcher, it puts this row first.
    func askAlias(id: String, title: String) {
        let alert = NSAlert()
        alert.messageText = L("\(title) için takma ad", "Alias for \(title)")
        alert.informativeText = L("Başlatıcıda bunu yazınca \(title) en üstte çıkar.", "Type it in the launcher and \(title) comes first.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = binding(id)?.alias ?? ""
        field.placeholderString = L("örn. ss", "e.g. ss")
        alert.accessoryView = field
        alert.addButton(withTitle: L("Kaydet", "Save"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        if binding(id)?.alias != nil { alert.addButton(withTitle: L("Kaldır", "Remove")) }
        alert.window.initialFirstResponder = field
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let alias = field.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
            if let other = all.first(where: { $0.alias == alias && $0.id != id }), !alias.isEmpty {
                Monitor.panelActions.flash(L("\"\(alias)\" zaten \(other.title) için", "\"\(alias)\" is already \(other.title)'s"))
                return
            }
            setAlias(alias, id: id, title: title)
            if !alias.isEmpty { Monitor.panelActions.flash(L("Takma ad: \(alias)", "Alias: \(alias)")) }
        case .alertThirdButtonReturn:
            setAlias(nil, id: id, title: title)
        default: break
        }
    }

    /// Records a key combination while the dialog is open (with ⌘, ⌃ or ⌥, or an F-key alone).
    func askCombo(id: String, title: String) {
        let alert = NSAlert()
        alert.messageText = L("\(title) için kısayol", "Shortcut for \(title)")
        alert.informativeText = L("Yeni tuşlara bas (en az bir ⌘, ⌃ ya da ⌥ ile). Her uygulamadayken çalışır.",
                                  "Press the new keys (with at least ⌘, ⌃ or ⌥). It works from any app.")
        let label = NSTextField(labelWithString: binding(id)?.combo?.label ?? L("Tuşlara bas…", "Press keys…"))
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 0, width: 220, height: 30)
        alert.accessoryView = label
        alert.addButton(withTitle: L("Kaydet", "Save"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        if binding(id)?.combo != nil { alert.addButton(withTitle: L("Kaldır", "Remove")) }
        var recorded: HotKey.Combo?
        HotKey.suspend(true)
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = Int(event.keyCode), flags = event.modifierFlags, characters = event.charactersIgnoringModifiers
            let modifiers = HotKey.modifiers(flags)
            // Plain ↩ and ⎋ still answer the dialog.
            if modifiers.carbon == 0 && (keyCode == kVK_Return || keyCode == kVK_Escape) { return event }
            let isFunctionKey = (96...122).contains(keyCode)
            guard modifiers.carbon & (cmdKey | controlKey | optionKey) != 0 || isFunctionKey else {
                NSSound.beep()
                return nil
            }
            let combo = HotKey.Combo(keyCode: keyCode, modifiers: modifiers.carbon,
                                     label: modifiers.symbols + HotKey.keyName(keyCode, characters))
            MainActor.assumeIsolated {
                recorded = combo
                label.stringValue = combo.label
            }
            return nil
        }
        NSApp.activate()
        let answer = alert.runModal()
        if let monitor { NSEvent.removeMonitor(monitor) }
        HotKey.suspend(false)
        switch answer {
        case .alertFirstButtonReturn:
            guard let recorded else { return }
            if let clash = clash(recorded, except: id) {
                Monitor.panelActions.flash(L("\(recorded.label) zaten \(clash) için", "\(recorded.label) is already \(clash)'s"))
                return
            }
            setCombo(recorded, id: id, title: title)
            Monitor.panelActions.flash(HotKey.isRegistered(id) ? L("\(title): \(recorded.label)", "\(title): \(recorded.label)")
                                                               : L("\(recorded.label) başka bir uygulamada kullanılıyor", "\(recorded.label) is taken by another app"))
        case .alertThirdButtonReturn:
            setCombo(nil, id: id, title: title)
        default: break
        }
    }

    /// Another Nabız shortcut already on these keys.
    private func clash(_ combo: HotKey.Combo, except id: String) -> String? {
        if let other = all.first(where: { $0.id != id && $0.combo.map { $0.keyCode == combo.keyCode && $0.modifiers == combo.modifiers } == true }) {
            return other.title
        }
        for shortcut in HotKey.Shortcut.allCases {
            let own = HotKey.combo(shortcut)
            if own.keyCode == combo.keyCode && own.modifiers == combo.modifiers { return "Nabız" }
        }
        return nil
    }
}
