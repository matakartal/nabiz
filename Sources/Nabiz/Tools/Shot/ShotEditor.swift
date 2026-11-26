import AppKit
import SwiftUI

/// The screenshot editor window: tools along the top bar (level with the window buttons, like Nabız's other big
/// windows), the screenshot in the middle, the colour, size and style of the current tool along the bottom.
@MainActor
enum ShotEditor {
    private static var open: [ShotEditorController] = []

    static func show(_ doc: ShotDocument) {
        let controller = ShotEditorController(doc: doc)
        open.append(controller)
        controller.show()
    }

    /// Opens an image file, or tells the user it can't.
    static func show(file url: URL) {
        guard let doc = ShotDocument(contentsOf: url) else {
            Monitor.panelActions.flash(L("Resim açılamadı", "Couldn't open the image"))
            return
        }
        show(doc)
    }

    /// The image on the clipboard, if there is one.
    @discardableResult
    static func showClipboard() -> Bool {
        guard let image = NSImage(pasteboard: .general), let doc = ShotDocument(nsImage: image) else {
            Monitor.panelActions.flash(L("Panoda resim yok", "No image on the clipboard"))
            return false
        }
        show(doc)
        return true
    }

    /// Asks for an image file to edit.
    static func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.directoryURL = Capture.folder
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        show(file: url)
    }

    static func closed(_ controller: ShotEditorController) {
        open.removeAll { $0 === controller }
    }
}

@MainActor
final class ShotEditorController: NSObject, NSWindowDelegate {
    let doc: ShotDocument
    private var window: NSWindow?

    init(doc: ShotDocument) {
        self.doc = doc
    }

    func show() {
        let view = ShotEditorView(doc: doc) { [weak self] action in self?.perform(action) }
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        WindowChrome.apply(window)
        window.title = L("Ekran görüntüsü", "Screenshot")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 820, height: 480)
        let screen = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = doc.documentRect
        let width = min(max(rect.width + 80, 820), screen.width * 0.9)
        let height = min(max(rect.height + 80 + 39 + 45, 480), screen.height * 0.9)
        window.setContentSize(NSSize(width: width, height: height))
        window.setFrameOrigin(NSPoint(x: screen.midX - width / 2, y: screen.midY - height / 2))
        self.window = window
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            NSRunningApplication.current.activate(from: front, options: [])
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func perform(_ action: ShotAction) {
        guard let window else { return }
        (window.firstResponder as? ShotTextView)?.onFinish()
        switch action {
        case .copy:
            if ShotExport.copy(doc) { doc.savedChanges = doc.changes; toast(L("Kopyalandı", "Copied")) }
        case .done:
            if ShotExport.copy(doc) {
                doc.savedChanges = doc.changes
                Monitor.panelActions.flash(L("Kopyalandı", "Copied"))
                window.close()
            }
        case .save:
            if let url = ShotExport.save(doc) {
                doc.savedChanges = doc.changes
                toast(L("Kaydedildi: \(url.deletingLastPathComponent().lastPathComponent)", "Saved to \(url.deletingLastPathComponent().lastPathComponent)"))
            }
        case .saveAs:
            ShotExport.saveAs(doc, in: window) { [weak self] url in
                guard let self else { return }
                doc.savedChanges = doc.changes
                toast(L("Kaydedildi", "Saved") + ": " + url.lastPathComponent)
            }
        case .copyText:
            Task { [weak self] in
                guard let self else { return }
                let found = await ShotExport.readText(doc)
                if let found, !found.text.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(found.text, forType: .string)
                    toast(found.isCode ? L("QR kopyalandı", "QR copied") : L("Metin kopyalandı", "Text copied"))
                } else {
                    toast(L("Metin bulunamadı", "No text found"))
                }
            }
        case .pin:
            if let image = ShotRenderer.exportImage(doc) { ShotPin.show(image, doc: doc) }
        case .share:
            guard let url = ShotExport.temporaryFile(doc), let anchor = window.contentView else { return }
            let picker = NSSharingServicePicker(items: [url])
            picker.show(relativeTo: NSRect(x: anchor.bounds.maxX - 150, y: anchor.bounds.maxY - 38, width: 28, height: 28), of: anchor, preferredEdge: .minY)
        case .close:
            window.performClose(nil)
        }
    }

    private func toast(_ text: String) {
        doc.toast = text
        Task { [weak doc] in
            try? await Task.sleep(for: .seconds(1.6))
            if doc?.toast == text { doc?.toast = nil }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        (sender.firstResponder as? ShotTextView)?.onFinish()
        guard doc.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = L("Değişiklikler kopyalanmadı ya da kaydedilmedi", "Your changes weren't copied or saved")
        alert.informativeText = L("Kapatırsan çizimler kaybolur.", "If you close, the markup is lost.")
        alert.addButton(withTitle: L("Kopyala ve kapat", "Copy and close"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        alert.addButton(withTitle: L("Kapat", "Close")).hasDestructiveAction = true
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if ShotExport.copy(doc) { Monitor.panelActions.flash(L("Kopyalandı", "Copied")); return true }
            return false
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
        ShotEditor.closed(self)
    }
}

// MARK: - The window's content

struct ShotEditorView: View {
    @Bindable var doc: ShotDocument
    let perform: (ShotAction) -> Void
    @AppStorage("panelStyle") private var style = "material"

    var body: some View {
        GeometryReader { geometry in
            let bar = max(geometry.safeAreaInsets.top, 38)
            VStack(spacing: 0) {
                topBar.frame(height: bar)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                ZStack(alignment: .top) {
                    ShotCanvas(doc: doc, perform: perform)
                        .background(style == "opaque" ? Theme.track : Theme.track.opacity(0.6))
                    if let toast = doc.toast {
                        Text(verbatim: toast)
                            .font(Theme.smallStrong)
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, Theme.Spacing.m)
                            .padding(.vertical, Theme.Spacing.xs + 2)
                            .background(MenuMaterial(blending: .withinWindow).clipShape(Capsule()))
                            .overlay(Capsule().strokeBorder(Theme.hairline))
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                            .padding(.top, Theme.Spacing.m)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.3), value: doc.toast)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                bottomBar.frame(height: 44)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(MenuMaterial().ignoresSafeArea())
        .appearanceRoot(opaqueFill: Theme.surface)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: WindowChrome.trafficLights)
            ForEach(ShotTool.allCases) { tool in
                ShotToolButton(symbol: tool.symbol, help: "\(tool.title)  \(String(tool.key).uppercased())", active: doc.tool == tool) {
                    doc.tool = tool
                }
                if tool == .select || tool == .counter { barDivider }
            }
            Spacer(minLength: Theme.Spacing.s)
            BarButton(symbol: "arrow.uturn.backward", help: L("Geri al  ⌘Z", "Undo  ⌘Z")) { doc.undo() }
                .disabled(!doc.canUndo).opacity(doc.canUndo ? 1 : 0.4)
            BarButton(symbol: "arrow.uturn.forward", help: L("Yinele  ⇧⌘Z", "Redo  ⇧⌘Z")) { doc.redo() }
                .disabled(!doc.canRedo).opacity(doc.canRedo ? 1 : 0.4)
            barDivider
            ShotToolButton(symbol: "photo.artframe", help: L("Arka plan ve çerçeve", "Background and frame"), active: doc.framePanel) {
                doc.framePanel.toggle()
                if doc.framePanel && !doc.background.enabled { doc.setBackground { $0.enabled = true } }
            }
            BarButton(symbol: "text.viewfinder", help: L("Metni kopyala  ⇧⌘C", "Copy text  ⇧⌘C")) { perform(.copyText) }
            BarButton(symbol: "pin", help: L("Ekrana sabitle  ⌘P", "Pin to screen  ⌘P")) { perform(.pin) }
            BarButton(symbol: "square.and.arrow.up", help: L("Paylaş", "Share")) { perform(.share) }
            ShotDragHandle(doc: doc)
            barDivider
            Button { perform(.save) } label: {
                Text(L("Kaydet", "Save")).font(Theme.bodyStrong).foregroundStyle(Theme.text)
                    .padding(.horizontal, Theme.Spacing.m).frame(height: 24)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(L("Ekran görüntüleri klasörüne kaydet  ⌘S", "Save to the screenshots folder  ⌘S"))
            Button { perform(.done) } label: {
                Text(L("Kopyala", "Copy")).font(Theme.bodyStrong).foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.m).frame(height: 24)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(L("Panoya kopyala ve kapat  ⌘↩  (yalnızca kopyala: ⌘C)", "Copy to the clipboard and close  ⌘↩  (copy only: ⌘C)"))
        }
        .padding(.trailing, Theme.Spacing.m)
    }

    private var barDivider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 18).padding(.horizontal, Theme.Spacing.xs)
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: Theme.Spacing.m) {
            if doc.framePanel { frameControls } else if doc.tool == .crop { cropControls } else { markControls }
            Spacer(minLength: 0)
            Text(verbatim: sizeLabel)
                .font(Theme.small).monospacedDigit()
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    private var sizeLabel: String {
        let rect = doc.tool == .crop ? (doc.cropDraft ?? doc.bounds) : doc.documentRect
        return "\(Int((rect.width * doc.scale).rounded())) × \(Int((rect.height * doc.scale).rounded())) px"
    }

    /// The kind the bottom bar sets: the selected mark's, else the current tool's.
    private var activeKind: ShotItem.Kind? { doc.selectedItem?.kind ?? doc.tool.kind }

    @ViewBuilder
    private var markControls: some View {
        let ink = doc.selectedItem?.ink ?? doc.ink
        let size = doc.selectedItem?.size ?? doc.lineSize
        HStack(spacing: 6) {
            ForEach(Array(ShotInk.palette.enumerated()), id: \.offset) { index, color in
                ShotSwatch(fill: AnyShapeStyle(Color(nsColor: color.nsColor)), selected: color == ink,
                           help: "\(ShotInk.paletteNames[index])  \(index + 1)") { doc.setInk(color) }
            }
        }
        if activeKind != .blur && activeKind != .spotlight {
            barDivider
            HStack(spacing: 2) {
                ForEach(ShotSize.allCases) { option in
                    Button { doc.setSize(option) } label: {
                        Circle().fill(option == size ? Theme.accent : Theme.textMuted)
                            .frame(width: CGFloat(3 + option.rawValue * 3), height: CGFloat(3 + option.rawValue * 3))
                            .frame(width: 26, height: 24)
                            .background(option == size ? Theme.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(option.title + "  [ ]")
                }
            }
        }
        if let kind = activeKind, !ShotItem.styles(for: kind).isEmpty {
            barDivider
            let current = doc.selectedItem?.style ?? doc.style(for: kind)
            HStack(spacing: 2) {
                ForEach(Array(ShotItem.styles(for: kind).enumerated()), id: \.offset) { index, option in
                    ShotToolButton(symbol: option.symbol, help: option.title, active: index == current) { doc.setStyle(index, for: kind) }
                }
            }
        }
        if doc.selection != nil {
            barDivider
            BarButton(symbol: "plus.square.on.square", help: L("Çoğalt  ⌘D", "Duplicate  ⌘D")) { doc.duplicateSelection() }
            BarButton(symbol: "trash", help: L("Sil  ⌫", "Delete  ⌫")) { doc.deleteSelection() }
        } else if doc.tool == .select {
            Text(L("Bir işarete tıkla, sürükle ya da tutamaçlarından boyutlandır.", "Click a mark to move it, or drag its handles."))
                .font(Theme.small).foregroundStyle(Theme.textMuted).lineLimit(1)
        }
    }

    @ViewBuilder
    private var cropControls: some View {
        Text(L("Sürükleyerek kırp. ↩ uygular, ⎋ çıkar.", "Drag to crop. ↩ applies, ⎋ leaves."))
            .font(Theme.small).foregroundStyle(Theme.textMuted).lineLimit(1)
        Button(L("Sıfırla", "Reset")) { doc.resetCrop() }.buttonStyle(.text).font(Theme.small)
        Button(L("Uygula", "Apply")) { doc.tool = .select }.buttonStyle(TextButtonStyle(font: Theme.smallStrong, color: Theme.accent))
    }

    @ViewBuilder
    private var frameControls: some View {
        Toggle(L("Arka plan", "Background"), isOn: Binding(get: { doc.background.enabled },
                                                          set: { on in doc.setBackground { $0.enabled = on } }))
            .toggleStyle(.switch).controlSize(.mini).font(Theme.small)
        HStack(spacing: 6) {
            ForEach(Array(ShotBackground.presets.enumerated()), id: \.offset) { index, pair in
                ShotSwatch(fill: AnyShapeStyle(LinearGradient(colors: [Color(nsColor: pair.0.nsColor), Color(nsColor: pair.1.nsColor)],
                                                              startPoint: .topLeading, endPoint: .bottomTrailing)),
                           selected: doc.background.preset == index, help: "") {
                    doc.setBackground { $0.preset = index; $0.enabled = true }
                }
            }
        }
        .disabled(!doc.background.enabled)
        barDivider
        ShotSlider(title: L("Boşluk", "Padding"), value: doc.background.padding, range: 8...160) { value in
            doc.setBackground { $0.padding = value }
        }
        ShotSlider(title: L("Köşe", "Corners"), value: doc.background.radius, range: 0...40) { value in
            doc.setBackground { $0.radius = value }
        }
        Toggle(L("Gölge", "Shadow"), isOn: Binding(get: { doc.background.shadow }, set: { on in doc.setBackground { $0.shadow = on } }))
            .toggleStyle(.checkbox).font(Theme.small)
        Button(L("Bitti", "Done")) { doc.framePanel = false }.buttonStyle(TextButtonStyle(font: Theme.smallStrong, color: Theme.accent))
    }
}

/// A tool in the bar: its symbol, lit in the accent while chosen.
struct ShotToolButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Theme.accent : (hovering ? Theme.text : Theme.textMuted))
                .frame(width: 28, height: 24)
                .background(active ? Theme.accent.opacity(0.16) : (hovering ? Theme.hover : .clear),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// A round colour (or gradient) choice with a ring when chosen.
struct ShotSwatch: View {
    let fill: AnyShapeStyle
    let selected: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle().fill(fill)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                .frame(width: 16, height: 16)
                .padding(2.5)
                .overlay(Circle().strokeBorder(selected ? Theme.accent : .clear, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// A compact labelled slider; the change is one undo step when the drag ends.
struct ShotSlider: View {
    let title: String
    let value: CGFloat
    let range: ClosedRange<CGFloat>
    let set: (CGFloat) -> Void
    @State private var live: CGFloat?

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(title).font(Theme.small).foregroundStyle(Theme.textMuted)
            Slider(value: Binding(get: { live ?? value }, set: { live = $0 }), in: range) { editing in
                if !editing, let live { set(live.rounded()); self.live = nil }
            }
            .controlSize(.mini)
            .frame(width: 80)
        }
    }
}

/// Drag this into Finder, Mail, Slack or anywhere that takes a file: the finished image as a PNG.
struct ShotDragHandle: NSViewRepresentable {
    let doc: ShotDocument

    func makeNSView(context: Context) -> ShotDragView {
        let view = ShotDragView()
        view.provide = { [weak doc] in doc.flatMap { ShotExport.temporaryFile($0) } }
        return view
    }

    func updateNSView(_ nsView: ShotDragView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ShotDragView, context: Context) -> CGSize? {
        CGSize(width: 28, height: 24)
    }
}

/// A view that starts a file drag of whatever `provide` makes.
final class ShotDragView: NSView, NSDraggingSource {
    var provide: () -> URL? = { nil }
    /// Drawn as an SF Symbol; the overlay thumbnail draws nothing and covers the image instead.
    var symbol: String? = "hand.draw"
    private var hovering = false
    private var down: NSPoint?

    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = L("Sürükleyip bırak", "Drag and drop")
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 28, height: 24) }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) else { return }
        if hovering {
            NSColor(Theme.hover).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        let tint = hovering ? NSColor(Theme.text) : NSColor(Theme.textMuted)
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(at: NSPoint(x: (bounds.width - image.size.width) / 2, y: (bounds.height - image.size.height) / 2),
                    from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func mouseDown(with event: NSEvent) { down = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = down, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 3,
              let url = provide() else { return }
        down = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let preview = NSImage(contentsOf: url) ?? NSImage()
        let width: CGFloat = 120
        let height = preview.size.width > 0 ? width * preview.size.height / preview.size.width : width
        let local = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: local.x - width / 2, y: local.y - height / 2, width: width, height: height), contents: preview)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if down != nil { onClick?() }
        down = nil
    }

    /// For the thumbnail: a click that isn't a drag, and a drag that landed somewhere.
    var onClick: (() -> Void)?
    var onDragEnd: (() -> Void)?

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] { onDragEnd?() }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
