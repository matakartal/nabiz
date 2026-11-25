import AppKit
import SwiftUI

/// The launcher: one field for apps, commands, maths, snippets, quicklinks and the clipboard. ⌃⌥Space opens it,
/// ⌃⌥V opens it on the clipboard history. It floats over everything without taking focus from the app in front,
/// so pasting lands where the cursor was.
@MainActor
final class LauncherPanel {
    static let shared = LauncherPanel()
    let model = LauncherModel()
    private var panel: KeyPanel?
    private var keyMonitor: Any?

    var isVisible: Bool { panel?.isVisible == true }

    func toggle(_ mode: LauncherModel.Mode = .all) {
        if isVisible && model.mode == mode { close() } else { show(mode) }
    }

    func show(_ mode: LauncherModel.Mode = .all, text: String = "") {
        RateStore.shared.refreshIfNeeded()
        AppIndex.shared.refreshIfNeeded()
        model.reset(mode: mode, text: text)
        model.cameFromLauncher = false
        model.close = { [weak self] in self?.close() }
        if isVisible { return }
        let panel = self.panel ?? KeyPanel()
        self.panel = panel
        panel.onClose = { [weak self] in self?.removeKeys() }
        // A fresh view each time: focused field, top of the list.
        let host = NSHostingView(rootView: LauncherView(model: model))
        let size = NSSize(width: Theme.launcherWidth, height: Theme.launcherHeight)
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.useMenuMaterial()
        panel.setContentSize(size)
        if let screen = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.maxY - screen.height * 0.2 - size.height))
        }
        panel.present()
        installKeys()
    }

    func close() { panel?.orderOut(nil) }

    /// Arrows, Return and the ⌘ shortcuts, read before the text field sees them. The app has no Edit menu while
    /// another app is in front, so ⌘C, ⌘V, ⌘X, ⌘A and ⌘Z are passed to the field here too.
    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode, flags = event.modifierFlags, key = event.charactersIgnoringModifiers?.lowercased()
            let window = event.window.map(ObjectIdentifier.init)
            let handled = MainActor.assumeIsolated {
                guard let self, let panel = self.panel, window == ObjectIdentifier(panel) else { return false }
                return self.handle(keyCode: keyCode, flags: flags, key: key)
            }
            return handled ? nil : event
        }
    }

    private func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handle(keyCode: UInt16, flags: NSEvent.ModifierFlags, key: String?) -> Bool {
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        if command && key == "k" {
            model.togglePalette()
            return true
        }
        if model.paletteOpen {
            switch Int(keyCode) {
            case 125: model.movePalette(1)
            case 126: model.movePalette(-1)
            case 36, 76: model.runPaletteAction()
            case 53: model.paletteOpen = false
            default: return command ? edit(key) : false
            }
            return true
        }
        switch Int(keyCode) {
        case 125: model.move(1)
        case 126: model.move(-1)
        case 36, 76: command ? model.runSecondary() : model.runPrimary()
        case 53:
            if model.mode == .clipboard && model.text.isEmpty && model.cameFromLauncher {
                model.reset(mode: .all)
            } else if model.text.isEmpty { close() } else { model.text = "" }
        case 51 where command && model.selected?.clip != nil: model.deleteSelected()
        case 35 where command && model.selected?.clip != nil: model.togglePinSelected()
        case 3 where command && shift: model.toggleFavoriteSelected()
        default:
            guard command else { return false }
            if key == "w" { close(); return true }
            return edit(key)
        }
        return true
    }

    /// ⌘C, ⌘V, ⌘X, ⌘A and ⌘Z for whichever field has the cursor.
    private func edit(_ key: String?) -> Bool {
        let edits: [String: Selector] = [
            "c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)), "x": #selector(NSText.cut(_:)),
            "a": #selector(NSText.selectAll(_:)), "z": Selector(("undo:")),
        ]
        guard let key, let action = edits[key] else { return false }
        NSApp.sendAction(action, to: nil, from: nil)
        return true
    }
}

struct LauncherView: View {
    @Bindable var model: LauncherModel
    enum Field { case search, palette }
    @FocusState private var focus: Field?
    private let rates = RateStore.shared
    private let clipboard = ClipboardHistory.shared

    var body: some View {
        // Reading these makes the list follow new rates and new copies while it is open.
        let _ = (rates.table, clipboard.items.count)
        let sections = model.sections
        let items = sections.flatMap(\.items)
        let selectedID = items.isEmpty ? nil : items[min(model.selection, items.count - 1)].id
        VStack(spacing: 0) {
            field
            Rectangle().fill(Theme.hairline).frame(height: 1)
            if model.mode == .clipboard {
                HStack(spacing: 0) {
                    list(sections, selectedID: selectedID, items: items).frame(width: Theme.launcherList)
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                    ClipPreview(clip: items.first { $0.id == selectedID }?.clip)
                }
            } else {
                list(sections, selectedID: selectedID, items: items)
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            footer(items.first { $0.id == selectedID })
        }
        .frame(width: Theme.launcherWidth, height: Theme.launcherHeight)
        .appearanceRoot()
        .overlay(alignment: .bottomTrailing) {
            if model.paletteOpen {
                ActionPalette(model: model, focus: $focus)
                    .padding(.trailing, Theme.Spacing.s)
                    .padding(.bottom, Theme.launcherFooter + Theme.Spacing.s)
            }
        }
        .onAppear { focus = .search }
        .onChange(of: model.paletteOpen) { _, open in focus = open ? .palette : .search }
    }

    private var field: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: model.mode == .clipboard ? "doc.on.clipboard" : "magnifyingglass")
                .font(Theme.input).foregroundStyle(Theme.textMuted)
                .frame(width: Theme.launcherIcon)
            TextField(model.mode == .clipboard ? L("Panoda ara", "Search the clipboard")
                                               : L("Uygulama, komut, hesap ya da arama", "Apps, commands, maths or search"),
                      text: $model.text)
                .textFieldStyle(.plain)
                .font(Theme.input)
                .foregroundStyle(Theme.text)
                .focused($focus, equals: .search)
            if model.mode == .clipboard {
                Text(verbatim: "\(clipboard.items.count)").font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(height: Theme.launcherField)
    }

    private func list(_ sections: [LauncherSection], selectedID: String?, items: [LauncherItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if sections.isEmpty { empty }
                    ForEach(sections) { section in
                        Text(verbatim: section.title)
                            .font(Theme.smallStrong).foregroundStyle(Theme.textMuted)
                            .padding(.horizontal, Theme.Spacing.l)
                            .padding(.top, Theme.Spacing.s)
                            .padding(.bottom, Theme.Spacing.xs)
                        ForEach(section.items) { item in
                            LauncherRow(item: item, selected: item.id == selectedID, compact: model.mode == .clipboard)
                                .id(item.id)
                                .onContinuousHover { phase in
                                    // Only a real pointer move selects: rows sliding under a still pointer while
                                    // scrolling with the arrow keys must not steal the selection.
                                    guard case .active = phase, model.pointerMoved(),
                                          let index = items.firstIndex(where: { $0.id == item.id }) else { return }
                                    model.selection = index
                                }
                                .onTapGesture {
                                    if let index = items.firstIndex(where: { $0.id == item.id }) { model.selection = index }
                                    model.runPrimary()
                                }
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            .scrollIndicators(.never)
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: model.mode == .clipboard ? "doc.on.clipboard" : "magnifyingglass")
                .font(Theme.title).foregroundStyle(Theme.textMuted)
            Text(model.mode == .clipboard
                 ? (Prefs.bool(Prefs.clipboardEnabled) ? L("Henüz kopyalanan bir şey yok.", "Nothing copied yet.")
                                                       : L("Pano geçmişi kapalı. Ayarlar → Pano'dan açabilirsin.", "Clipboard history is off. Turn it on in Settings → Clipboard."))
                 : L("Sonuç yok", "No results"))
                .font(Theme.small).foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xxl)
    }

    private func footer(_ item: LauncherItem?) -> some View {
        HStack(spacing: Theme.Spacing.l) {
            if model.mode == .clipboard && Prefs.bool(Prefs.autoPaste) && !Paster.isTrusted {
                Button(L("Yapıştırmak için izin ver", "Allow pasting")) { Paster.requestTrust() }
                    .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.accent))
            } else {
                Text(model.mode == .clipboard ? L("↑↓ seç · esc geri", "↑↓ to pick · esc back")
                                              : L("Hesap: 100 usd · Web: g kelime · Komutlar: >", "Maths: 100 usd · Web: g words · Commands: >"))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            if let item {
                KeyHint(keys: "↩", title: item.primaryTitle, strong: true)
                Rectangle().fill(Theme.hairline).frame(width: 1, height: Theme.Spacing.l)
                KeyHint(keys: "⌘K", title: L("Eylemler", "Actions"), strong: model.paletteOpen)
            }
        }
        .font(Theme.small)
        .padding(.horizontal, Theme.Spacing.l)
        .frame(height: Theme.launcherFooter)
    }
}

/// ⌘K: what can be done with the selected row, searchable, run with ↩.
private struct ActionPalette: View {
    @Bindable var model: LauncherModel
    var focus: FocusState<LauncherView.Field?>.Binding

    var body: some View {
        let actions = model.paletteActions
        let selectedID = actions.isEmpty ? nil : actions[min(model.paletteSelection, actions.count - 1)].id
        let headers = Set(actions.indices.filter { $0 == 0 || actions[$0].group != actions[$0 - 1].group })
        let height = min(CGFloat(actions.count) * Theme.paletteRow + CGFloat(headers.count) * Theme.menuLine + Theme.Spacing.s,
                         Theme.paletteMaxList)
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                            if headers.contains(index) {
                                Text(verbatim: action.group).font(Theme.smallStrong).foregroundStyle(Theme.textMuted)
                                    .padding(.horizontal, Theme.Spacing.s)
                                    .frame(height: Theme.menuLine, alignment: .bottom)
                            }
                            PaletteRow(action: action, selected: action.id == selectedID)
                                .id(action.id)
                                .onContinuousHover { phase in
                                    guard case .active = phase, model.pointerMoved() else { return }
                                    model.paletteSelection = index
                                }
                                .onTapGesture { model.runPaletteAction(action) }
                        }
                        if actions.isEmpty {
                            Text(L("Eylem yok", "No actions")).font(Theme.small).foregroundStyle(Theme.textMuted)
                                .frame(maxWidth: .infinity).frame(height: Theme.paletteRow)
                        }
                    }
                    .padding(Theme.Spacing.xs)
                }
                .scrollIndicators(.never)
                .frame(height: max(height, Theme.paletteRow + Theme.Spacing.s))
                .onChange(of: selectedID) { _, id in if let id { proxy.scrollTo(id) } }
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            TextField(L("Eylem ara", "Search actions"), text: $model.paletteQuery)
                .textFieldStyle(.plain)
                .font(Theme.body)
                .focused(focus, equals: .palette)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(height: Theme.launcherFooter + Theme.Spacing.xs)
        }
        .frame(width: Theme.paletteWidth)
        .background {
            if Prefs.string(Prefs.panelStyle) == "opaque" { Theme.surfaceRaised } else { MenuMaterial(blending: .withinWindow) }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.25), radius: Theme.Spacing.m, y: Theme.Spacing.xs)
    }
}

private struct PaletteRow: View {
    let action: LauncherAction
    let selected: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: action.symbol).font(Theme.small)
                .foregroundStyle(action.destructive ? Theme.danger : selected ? Theme.accent : Theme.textMuted)
                .frame(width: Theme.menuIcon)
            Text(verbatim: action.title).font(Theme.body).foregroundStyle(action.destructive ? Theme.danger : Theme.text).lineLimit(1)
            Spacer(minLength: Theme.Spacing.s)
            if let shortcut = action.shortcut {
                Text(verbatim: shortcut).font(Theme.small).foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: Theme.paletteRow)
        .background(selected ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct KeyHint: View {
    let keys: String
    let title: String
    var strong = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(verbatim: title).font(strong ? Theme.smallStrong : Theme.small).foregroundStyle(strong ? Theme.text : Theme.textMuted)
            Text(verbatim: keys)
                .font(Theme.small).foregroundStyle(Theme.textMuted)
                .padding(.horizontal, Theme.Spacing.xs)
                .background(Theme.track, in: RoundedRectangle(cornerRadius: Theme.fieldRadius / 2, style: .continuous))
        }
    }
}

private struct LauncherRow: View {
    let item: LauncherItem
    let selected: Bool
    var compact = false

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            icon.frame(width: Theme.launcherIcon, height: Theme.launcherIcon)
            Text(verbatim: item.title).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                .layoutPriority(1)
            if !compact, let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(verbatim: subtitle).font(Theme.small).foregroundStyle(Theme.textMuted).lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.s)
            if item.clip?.pinned == true {
                Image(systemName: "pin.fill").font(Theme.small).foregroundStyle(Theme.accent)
            }
            if let accessory = item.accessory {
                Text(verbatim: accessory).font(Theme.small).foregroundStyle(Theme.textMuted).lineLimit(1).fixedSize()
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(height: Theme.launcherRow)
        .background(selected ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
        .padding(.horizontal, Theme.Spacing.xs)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var icon: some View {
        switch item.icon {
        case .symbol(let name):
            Image(systemName: name).font(Theme.body).foregroundStyle(selected ? Theme.accent : Theme.textMuted)
        case .app(let path):
            Image(nsImage: AppIndex.shared.icon(path)).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        case .clip(let clip):
            ClipIcon(clip: clip, selected: selected)
        }
    }
}

private struct ClipIcon: View {
    let clip: ClipItem
    let selected: Bool

    var body: some View {
        switch clip.kind {
        case .image:
            if let image = Thumbnails.image(for: clip) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: Theme.launcherIcon, height: Theme.launcherIcon)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.fieldRadius / 2, style: .continuous))
            } else {
                Image(systemName: clip.symbol).foregroundStyle(Theme.textMuted)
            }
        case .color:
            Circle().fill(Color(hex: clip.text ?? "") ?? .clear).overlay(Circle().strokeBorder(Theme.hairline))
                .padding(Theme.Spacing.xs / 2)
        case .files:
            if let first = clip.files?.first {
                Image(nsImage: AppIndex.shared.icon(first)).resizable().aspectRatio(contentMode: .fit)
            }
        default:
            Image(systemName: clip.symbol).font(Theme.body).foregroundStyle(selected ? Theme.accent : Theme.textMuted)
        }
    }
}

/// The clipboard item in full: its text, picture, colour or files, and where and when it was copied.
private struct ClipPreview: View {
    let clip: ClipItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let clip {
                ScrollView {
                    content(clip).frame(maxWidth: .infinity, alignment: .topLeading).padding(Theme.Spacing.l)
                }
                .scrollIndicators(.never)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                VStack(spacing: Theme.Spacing.xs) {
                    info(L("Kaynak", "From"), clip.app ?? "—")
                    info(L("Zaman", "Copied"), clip.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Format.locale)))
                    if let text = clip.text { info(L("Karakter", "Characters"), "\(text.count)") }
                }
                .padding(Theme.Spacing.l)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func content(_ clip: ClipItem) -> some View {
        switch clip.kind {
        case .image:
            if let data = clip.image, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            }
        case .color:
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Color(hex: clip.text ?? "") ?? .clear)
                    .frame(height: Theme.launcherRow * 3)
                Text(verbatim: clip.text ?? "").font(Theme.bodyStrong).foregroundStyle(Theme.text)
            }
        case .files:
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(clip.files ?? [], id: \.self) { path in
                    Text(verbatim: path).font(Theme.small).foregroundStyle(Theme.text).textSelection(.enabled)
                }
            }
        case .text, .link:
            Text(verbatim: clip.text ?? "").font(.system(.body, design: .monospaced)).foregroundStyle(Theme.text)
                .textSelection(.enabled)
        }
    }

    private func info(_ title: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: title).foregroundStyle(Theme.textMuted)
            Spacer()
            Text(verbatim: value).foregroundStyle(Theme.text).lineLimit(1)
        }
        .font(Theme.small)
    }
}

/// Small copies of clipboard images, decoded once.
@MainActor
enum Thumbnails {
    private static var cache: [UUID: NSImage] = [:]

    static func image(for clip: ClipItem) -> NSImage? {
        if let image = cache[clip.id] { return image }
        guard let data = clip.image, let image = NSImage(data: data) else { return nil }
        if cache.count > 300 { cache.removeAll() }
        cache[clip.id] = image
        return image
    }
}

extension Color {
    /// "#1DB954" or "#FFF".
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(nsColor: Theme.RGBA.hex(number).nsColor)
    }
}
