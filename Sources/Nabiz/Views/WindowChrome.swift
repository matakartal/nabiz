import AppKit
import SwiftUI

/// The window shape Nabız's big windows share, like Claude's and Finder's: one bar along the top, level with the
/// window buttons, split into a sidebar part and a content part by the same line that runs down between them,
/// with a hairline under the bar. The whole window is frosted (or opaque, per Settings → Appearance).
@MainActor
enum WindowChrome {
    /// A titled window whose bar is drawn by SwiftUI: an empty toolbar gives the bar its height and centres the
    /// window buttons in it; the title is hidden.
    static func apply(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "nabiz.chrome")
            toolbar.showsBaselineSeparator = false
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
        }
        window.toolbarStyle = .unifiedCompact
        window.backgroundColor = .clear
        window.isOpaque = false
    }

    /// Room for the close, minimise and zoom buttons at the bar's leading edge, until the real ones are measured.
    static let trafficLights: CGFloat = 76
}

/// Where the window buttons really are (their centre from the top, and where the zoom button ends), so the bar's
/// own buttons sit on exactly the same line, the same distance apart as the window buttons are from each other.
struct TrafficLights: Equatable {
    var centerY: CGFloat = 0
    var trailing: CGFloat = 0
    /// The gap between two window buttons, used again after the zoom button.
    var gap: CGFloat = 8
}

private struct TrafficLightsKey: PreferenceKey {
    static let defaultValue = TrafficLights()
    static func reduce(value: inout TrafficLights, nextValue: () -> TrafficLights) {
        let next = nextValue()
        if next.trailing > 0 { value = next }
    }
}

/// Reads the window buttons' frames once the view is in its window (and again after layout changes).
private struct TrafficLightReader: NSViewRepresentable {
    @Binding var lights: TrafficLights

    func makeNSView(context: Context) -> NSView {
        let view = MeasuringView()
        view.onMeasure = { measured in if measured != lights { lights = measured } }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? MeasuringView)?.measureSoon()
    }

    final class MeasuringView: NSView {
        var onMeasure: (TrafficLights) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            measureSoon()
        }

        override func layout() {
            super.layout()
            measureSoon()
        }

        func measureSoon() {
            DispatchQueue.main.async { [weak self] in self?.measure() }
        }

        private func measure() {
            guard let window, let content = window.contentView,
                  let close = window.standardWindowButton(.closeButton), let mini = window.standardWindowButton(.miniaturizeButton),
                  let zoom = window.standardWindowButton(.zoomButton), let frame = zoom.superview else { return }
            let zoomRect = content.convert(zoom.frame, from: frame)
            let closeRect = content.convert(close.frame, from: frame)
            let miniRect = content.convert(mini.frame, from: frame)
            // Content is flipped or not; take the centre from the top either way.
            let centerY = content.isFlipped ? zoomRect.midY : content.bounds.height - zoomRect.midY
            onMeasure(TrafficLights(centerY: centerY.rounded(), trailing: zoomRect.maxX.rounded(),
                                    gap: max(miniRect.minX - closeRect.maxX, 6).rounded()))
        }
    }
}

/// A sidebar and a content area under one aligned top bar. The sidebar can be hidden (its bar part shrinks to the
/// window buttons and its own buttons) and resized by dragging the line between them.
struct UnifiedSplitView<Sidebar: View, Detail: View, SidebarBar: View, DetailBar: View>: View {
    @Binding var sidebarVisible: Bool
    @Binding var sidebarWidth: Double
    var minWidth: Double = 210
    var maxWidth: Double = 380
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail
    @ViewBuilder var sidebarBar: () -> SidebarBar
    @ViewBuilder var detailBar: () -> DetailBar
    @AppStorage("panelStyle") private var style = "material"
    @State private var dragStart: Double?
    @State private var lights = TrafficLights()

    var body: some View {
        GeometryReader { geometry in
            let bar = max(geometry.safeAreaInsets.top, 38)
            // The bar's buttons line up with the window buttons: same centre line, and after the zoom button the
            // same gap again (plus the button's own inset), measured from the window itself.
            let shift = lights.trailing > 0 ? lights.centerY - bar / 2 : 0
            let lead = lights.trailing > 0 ? lights.trailing + lights.gap * 2 - BarButton.inset : WindowChrome.trafficLights
            let width = CGFloat(min(max(sidebarWidth, minWidth), maxWidth))
            HStack(spacing: 0) {
                if sidebarVisible {
                    VStack(spacing: 0) {
                        HStack(spacing: BarButton.spacing) {
                            Color.clear.frame(width: lead)
                            sidebarBar()
                            Spacer(minLength: 0)
                        }
                        .padding(.trailing, Theme.Spacing.s)
                        .frame(height: bar)
                        .offset(y: shift)
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        sidebar()
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: width)
                    .background(style == "opaque" ? Theme.track : Theme.track.opacity(0.6))
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    divider(width)
                }
                VStack(spacing: 0) {
                    HStack(spacing: Theme.Spacing.s) {
                        if !sidebarVisible {
                            HStack(spacing: BarButton.spacing) {
                                Color.clear.frame(width: lead)
                                sidebarBar()
                            }
                            Rectangle().fill(Theme.hairline).frame(width: 1, height: 18)
                        }
                        detailBar()
                    }
                    .padding(.leading, sidebarVisible ? Theme.Spacing.l : 0)
                    .padding(.trailing, Theme.Spacing.m)
                    .frame(height: bar)
                    .offset(y: shift)
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    detail()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(TrafficLightReader(lights: $lights))
    }

    /// The line between the two parts, from the top of the bar down; drag it to resize the sidebar.
    private func divider(_ width: CGFloat) -> some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { drag in
                            let start = dragStart ?? Double(width)
                            dragStart = start
                            sidebarWidth = min(max(start + drag.translation.width, minWidth), maxWidth)
                        }
                        .onEnded { _ in dragStart = nil })
            }
    }
}

/// A small bar button: an SF Symbol that lights on hover, like the apps' toolbar icons.
struct BarButton: View {
    /// The empty space on each side of the symbol inside the button.
    static let inset: CGFloat = 6
    /// Between two bar buttons.
    static let spacing: CGFloat = 4
    static let size = CGSize(width: 28, height: 24)

    let symbol: String
    let help: String
    var active = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(active || hovering ? Theme.text : Theme.textMuted)
                .frame(width: Self.size.width, height: Self.size.height)
                .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// A bar menu that looks like a `BarButton` (share, more): the symbol, lit on hover, no arrow.
struct BarMenu<Content: View>: View {
    let symbol: String
    let help: String
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        Menu(content: content) {
            Image(systemName: symbol)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(hovering ? Theme.text : Theme.textMuted)
        .fixedSize()
        .frame(width: BarButton.size.width, height: BarButton.size.height)
        .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// Renaming in place, Finder-style: the text selected, a soft rounded field instead of the black box AppKit draws
/// for an editor in a sidebar; ↩ saves, esc cancels, clicking away saves.
struct InlineRenameField: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = Theme.nsFont(size: 13)
    let commit: () -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = font
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
            Self.clearEditor(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// The shared field editor paints its own background; keep it see-through.
    static func clearEditor(_ field: NSTextField) {
        if let editor = field.currentEditor() as? NSTextView {
            editor.drawsBackground = false
            editor.backgroundColor = .clear
            editor.insertionPointColor = NSColor.controlAccentColor
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineRenameField
        private var finished = false

        init(_ parent: InlineRenameField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if let field = notification.object as? NSTextField { InlineRenameField.clearEditor(field) }
        }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                finished = true
                parent.cancel()
                return true
            }
            if selector == #selector(NSResponder.insertNewline(_:)) {
                finished = true
                parent.commit()
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard !finished else { return }
            finished = true
            parent.commit()
        }
    }
}

extension InlineRenameField {
    /// The field in its soft frame, sized like the row text it replaces.
    func framed() -> some View {
        self
            .padding(.horizontal, 5)
            .frame(height: 22)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.accent.opacity(0.7), lineWidth: 1) }
            .padding(.leading, -5)
    }
}
