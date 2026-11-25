import AppKit
import Carbon.HIToolbox
import SwiftUI

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
        // Hover works even while another app stays active underneath.
        acceptsMouseMovedEvents = true
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

/// Global shortcuts. Carbon hot keys need no Accessibility permission (moving windows does).
@MainActor
enum HotKey {
    enum Shortcut: UInt32, CaseIterable {
        case launcher = 1, panel = 2, clipboard = 3, note = 4
        case leftHalf = 10, rightHalf, topHalf, bottomHalf, maximize, center

        var key: Int {
            switch self {
            case .launcher: kVK_Space
            case .panel: kVK_ANSI_N
            case .clipboard: kVK_ANSI_V
            case .note: kVK_ANSI_M
            case .leftHalf: kVK_LeftArrow
            case .rightHalf: kVK_RightArrow
            case .topHalf: kVK_UpArrow
            case .bottomHalf: kVK_DownArrow
            case .maximize: kVK_Return
            case .center: kVK_ANSI_C
            }
        }

        var window: WindowAction? {
            switch self {
            case .leftHalf: .leftHalf
            case .rightHalf: .rightHalf
            case .topHalf: .topHalf
            case .bottomHalf: .bottomHalf
            case .maximize: .maximize
            case .center: .center
            default: nil
            }
        }

        static var windows: [Shortcut] { allCases.filter { $0.window != nil } }
    }

    /// What the panel shortcut does; set by the app delegate.
    static var togglePanel: () -> Void = {}
    private static var refs: [Shortcut: EventHotKeyRef] = [:]
    private static var handler: EventHandlerRef?

    static func update(_ shortcut: Shortcut, enabled: Bool) {
        if enabled == (refs[shortcut] != nil) { return }
        if let ref = refs.removeValue(forKey: shortcut) { UnregisterEventHotKey(ref) }
        guard enabled else { return }
        installHandler()
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(shortcut.key), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: 0x4E42_5A31, id: shortcut.rawValue), GetApplicationEventTarget(), 0, &ref)
        if let ref { refs[shortcut] = ref }
    }

    private static func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let pressed = id.id
            Task { @MainActor in
                guard let shortcut = Shortcut(rawValue: pressed) else { return }
                switch shortcut {
                case .launcher: LauncherPanel.shared.toggle(.all)
                case .panel: HotKey.togglePanel()
                case .clipboard: LauncherPanel.shared.toggle(.clipboard)
                case .note: NoteWindow.toggle()
                default: shortcut.window?.run()
                }
            }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
