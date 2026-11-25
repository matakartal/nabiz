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
        switch Int(keyCode) {
        case 125: model.move(1)
        case 126: model.move(-1)
        case 36, 76: command ? model.runSecondary() : model.runPrimary()
        case 53:
            if model.mode == .clipboard && model.text.isEmpty && model.cameFromLauncher {
                model.reset(mode: .all)
            } else if model.text.isEmpty { close() } else { model.text = "" }
        case 51 where command && model.mode == .clipboard: model.deleteSelected()
        case 35 where command && model.mode == .clipboard: model.togglePinSelected()
        default:
            guard command, let key else { return false }
            let edits: [String: Selector] = [
                "c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)), "x": #selector(NSText.cut(_:)),
                "a": #selector(NSText.selectAll(_:)), "z": Selector(("undo:")),
            ]
            if key == "w" { close(); return true }
            guard let action = edits[key] else { return false }
            NSApp.sendAction(action, to: nil, from: nil)
        }
        return true
    }
}

struct LauncherView: View {
    @Bindable var model: LauncherModel
    @FocusState private var focused: Bool
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
        .onAppear { focused = true }
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
                .focused($focused)
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
            if model.mode == .clipboard {
                if Prefs.bool(Prefs.autoPaste) && !Paster.isTrusted {
                    Button(L("Yapıştırmak için izin ver", "Allow pasting")) { Paster.requestTrust() }
                        .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.accent))
                } else {
                    Text(L("Kaydırarak seç · esc geri", "Arrows to pick · esc back")).foregroundStyle(Theme.textMuted)
                }
            } else {
                Text(L("Hesap: 100 usd · Arama: g kelime", "Maths: 100 usd · Search: g words")).foregroundStyle(Theme.textMuted)
            }
            Spacer()
            if let item {
                if model.mode == .clipboard, item.clip != nil {
                    KeyHint(keys: "⌘P", title: item.clip?.pinned == true ? L("Sabitlemeyi kaldır", "Unpin") : L("Sabitle", "Pin"))
                    KeyHint(keys: "⌘⌫", title: L("Sil", "Delete"))
                }
                if let secondary = item.secondaryTitle, item.secondary != nil { KeyHint(keys: "⌘↩", title: secondary) }
                KeyHint(keys: "↩", title: item.primaryTitle, strong: true)
            }
        }
        .font(Theme.small)
        .padding(.horizontal, Theme.Spacing.l)
        .frame(height: Theme.launcherFooter)
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
