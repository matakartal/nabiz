import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A Spotlight-style floating field for quick maths and currency conversion. ⌃⌥Space toggles it from anywhere.
@MainActor
final class CalculatorPanel {
    static let shared = CalculatorPanel()
    private var panel: KeyPanel?

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    func show() {
        RateStore.shared.refreshIfNeeded()
        let panel = self.panel ?? KeyPanel()
        self.panel = panel
        // A fresh view each time: empty field, focused.
        let host = NSHostingView(rootView: CalculatorView { [weak self] in self?.close() })
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        panel.contentView = host
        panel.useMenuMaterial()
        panel.setContentSize(host.fittingSize)
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.midX - host.fittingSize.width / 2, y: screen.minY + screen.height * 0.68))
        }
        panel.present()
    }

    func close() { panel?.orderOut(nil) }
}

/// A borderless panel that takes typing without activating Nabız, the way system menus and Spotlight do.
/// It never depends on app activation (macOS 14+ may refuse it), so it stays open until the user dismisses it:
/// Escape, a click outside, or another app coming forward.
final class KeyPanel: NSPanel {
    /// Called once each time the panel goes away.
    var onClose: (() -> Void)?
    /// Clicks that should not dismiss the panel, e.g. on the status item that toggles it.
    var keepsOpenOnClick: (NSEvent) -> Bool = { _ in false }
    private var monitors: [Any] = []
    private var activationObserver: NSObjectProtocol?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Puts the content on the frosted material native menus use, with their rounded corners and rim.
    func useMenuMaterial() {
        guard let content = contentView ?? contentViewController?.view else { return }
        if let effect = content.superview as? NSVisualEffectView, effect === contentView { return }
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Theme.radius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        let controller = contentViewController
        contentViewController = nil
        contentView = effect
        content.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        retainedController = controller
        animationBehavior = .utilityWindow
    }

    /// Keeps a hosting controller alive after its view moved inside the material view.
    private var retainedController: NSViewController?
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    func present() {
        makeKeyAndOrderFront(nil)
        guard monitors.isEmpty else { return }
        // Clicks in other apps.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }) { monitors.append(monitor) }
        // Clicks in Nabız's other windows (Settings), but not in this panel or on the status item.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self, !self.keepsOpenOnClick(event) { self.orderOut(nil) }
            }
            return event
        }) { monitors.append(monitor) }
        // ⌘Tab or a click on the Dock.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if app?.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.orderOut(nil) }
            }
        }
    }

    override func orderOut(_ sender: Any?) {
        let wasVisible = isVisible
        super.orderOut(sender)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        if wasVisible { onClose?() }
    }
}

struct CalculatorView: View {
    let onDone: () -> Void
    @State private var text: String

    init(text: String = "", onDone: @escaping () -> Void) {
        _text = State(initialValue: text)
        self.onDone = onDone
    }
    @FocusState private var focused: Bool
    private let rates = RateStore.shared

    var body: some View {
        // Touching `rates.table` makes the view redraw when rates arrive.
        let result = rates.table.map { _ in Calculator.evaluate(text) } ?? Calculator.evaluate(text)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "equal.circle.fill").font(Theme.input).foregroundStyle(Theme.accent)
                TextField(L("Hesapla ya da çevir", "Calculate or convert"), text: $text)
                    .textFieldStyle(.plain)
                    .font(Theme.input)
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .onSubmit { copy(result) }
            }
            .padding(Theme.Spacing.l)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            HStack(alignment: .firstTextBaseline) {
                if let result {
                    Text(verbatim: result.text).font(Theme.inputStrong).foregroundStyle(Theme.text)
                        .textSelection(.enabled).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: Theme.Spacing.m)
                    if !result.copy.isEmpty {
                        Text(L("↩ kopyala", "↩ copy")).font(Theme.small).foregroundStyle(Theme.textMuted)
                    }
                } else {
                    Text(verbatim: hint).font(Theme.small).foregroundStyle(Theme.textMuted)
                    Spacer()
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
        }
        .frame(width: 520)
        .onAppear { focused = true }
    }

    private var hint: String {
        L("Örnek: 12*4 · 200 + %18 · 100 usd · 250 € tl · 5 km mi · 100 f c · 2 gb mb",
          "e.g. 12*4 · 200 + 18% · 100 usd · 250 € try · 5 km mi · 100 f c · 2 gb mb")
    }

    private func copy(_ result: Calculator.Result?) {
        guard let result, !result.copy.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.copy, forType: .string)
        onDone()
    }
}

/// The global shortcut, ⌃⌥Space. Carbon hot keys need no Accessibility permission.
@MainActor
enum HotKey {
    private static var ref: EventHotKeyRef?
    private static var handler: EventHandlerRef?

    static func update(enabled: Bool) {
        if enabled == (ref != nil) { return }
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        guard enabled else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in CalculatorPanel.shared.toggle() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        var newRef: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: 0x4E42_5A31, id: 1), GetApplicationEventTarget(), 0, &newRef)
        ref = newRef
    }
}
