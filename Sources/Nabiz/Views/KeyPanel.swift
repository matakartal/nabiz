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
        // The mask shapes the window itself, so its shadow follows the rounded corners instead of a square box.
        effect.maskImage = Self.roundedMask(Theme.radius)
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

    /// A stretchable rounded rectangle; only its corners are drawn, the middle stretches.
    static func roundedMask(_ radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// The shadow is computed from the shape; recompute it whenever the panel grows or shrinks.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        invalidateShadow()
    }

    /// Keeps a hosting controller alive after its view moved inside the material view.
    private var retainedController: NSViewController?
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    func present() {
        makeKeyAndOrderFront(nil)
        invalidateShadow()
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
        case launcher = 1, panel = 2, clipboard = 3, note = 4, ai = 5, dictation = 6, screenshot = 7, aiChat = 8
        case leftHalf = 10, rightHalf, topHalf, bottomHalf, maximize, center

        var key: Int {
            switch self {
            case .launcher: kVK_Space
            case .panel: kVK_ANSI_N
            case .clipboard: kVK_ANSI_V
            case .note: kVK_ANSI_M
            case .ai: kVK_ANSI_A
            case .aiChat: kVK_ANSI_I
            case .dictation: kVK_ANSI_D
            case .screenshot: kVK_ANSI_S
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

    /// A key and its modifiers (Carbon flags), with how it reads: "⌃⌥Space".
    struct Combo: Codable, Equatable {
        var keyCode: Int
        var modifiers: Int
        var label: String
    }

    /// What the panel shortcut does; set by the app delegate.
    static var togglePanel: () -> Void = {}
    private static var refs: [Shortcut: EventHotKeyRef] = [:]
    private static var registered: [Shortcut: Combo] = [:]
    private static var handler: EventHandlerRef?
    /// While a shortcut is being recorded in Settings, none of them fire.
    private(set) static var suspended = false

    /// The shortcuts a person can change in Settings.
    static let customizable: [Shortcut] = [.launcher, .clipboard, .note, .panel, .ai, .aiChat, .dictation, .screenshot]

    static func combo(_ shortcut: Shortcut) -> Combo {
        if let data = UserDefaults.standard.data(forKey: "hotkey.\(shortcut.rawValue)"),
           let saved = try? JSONDecoder().decode(Combo.self, from: data) { return saved }
        return Combo(keyCode: shortcut.key, modifiers: controlKey | optionKey, label: "⌃⌥" + keyName(shortcut.key, nil))
    }

    static func label(_ shortcut: Shortcut) -> String { combo(shortcut).label }

    /// Saves a new combination (nil goes back to the default) and registers it right away.
    static func set(_ shortcut: Shortcut, _ combo: Combo?) {
        if let combo { UserDefaults.standard.set(try? JSONEncoder().encode(combo), forKey: "hotkey.\(shortcut.rawValue)") } else {
            UserDefaults.standard.removeObject(forKey: "hotkey.\(shortcut.rawValue)")
        }
        let enabled = refs[shortcut] != nil
        unregister(shortcut)
        if enabled { update(shortcut, enabled: true) }
    }

    static func suspend(_ on: Bool) {
        suspended = on
    }

    static func update(_ shortcut: Shortcut, enabled: Bool) {
        let combo = combo(shortcut)
        if enabled == (refs[shortcut] != nil) && (!enabled || registered[shortcut] == combo) { return }
        unregister(shortcut)
        guard enabled else { return }
        installHandler()
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(combo.keyCode), UInt32(combo.modifiers),
                            EventHotKeyID(signature: 0x4E42_5A31, id: shortcut.rawValue), GetApplicationEventTarget(), 0, &ref)
        if let ref {
            refs[shortcut] = ref
            registered[shortcut] = combo
        }
        if shortcut == .screenshot { ShotLog.write("registered \(combo.label): \(ref != nil)") }
    }

    /// Shortcuts people gave to launcher rows, by hot key id (from 1000 up).
    private static var itemRefs: [UInt32: (id: String, ref: EventHotKeyRef)] = [:]

    /// Registers every launcher row's own shortcut again, after one changed or at launch.
    static func registerItems() {
        for entry in itemRefs.values { UnregisterEventHotKey(entry.ref) }
        itemRefs = [:]
        let bindings = ItemBindings.shared.all.filter { $0.combo != nil }
        guard !bindings.isEmpty else { return }
        installHandler()
        for (index, binding) in bindings.enumerated() {
            guard let combo = binding.combo else { continue }
            let hotKeyID = UInt32(1000 + index)
            var ref: EventHotKeyRef?
            RegisterEventHotKey(UInt32(combo.keyCode), UInt32(combo.modifiers),
                                EventHotKeyID(signature: 0x4E42_5A31, id: hotKeyID), GetApplicationEventTarget(), 0, &ref)
            if let ref { itemRefs[hotKeyID] = (binding.id, ref) }
        }
    }

    /// False when another app already holds the keys.
    static func isRegistered(_ itemID: String) -> Bool { itemRefs.values.contains { $0.id == itemID } }

    private static func unregister(_ shortcut: Shortcut) {
        if let ref = refs.removeValue(forKey: shortcut) { UnregisterEventHotKey(ref) }
        registered[shortcut] = nil
    }

    /// "Space", "↩", "←", "F5", or the letter itself.
    static func keyName(_ keyCode: Int, _ characters: String?) -> String {
        switch keyCode {
        case kVK_Space: L("Boşluk", "Space")
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_Delete: "⌫"
        case kVK_Escape: "⎋"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_F1: "F1"
        case kVK_F2: "F2"
        case kVK_F3: "F3"
        case kVK_F4: "F4"
        case kVK_F5: "F5"
        case kVK_F6: "F6"
        case kVK_F7: "F7"
        case kVK_F8: "F8"
        case kVK_F9: "F9"
        case kVK_F10: "F10"
        case kVK_F11: "F11"
        case kVK_F12: "F12"
        case kVK_ANSI_N: "N"
        case kVK_ANSI_V: "V"
        case kVK_ANSI_M: "M"
        case kVK_ANSI_D: "D"
        case kVK_ANSI_A: "A"
        case kVK_ANSI_C: "C"
        case kVK_ANSI_S: "S"
        case kVK_ANSI_I: "I"
        default: (characters ?? "?").uppercased()
        }
    }

    /// Carbon modifier flags and their symbols, from an AppKit event.
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> (carbon: Int, symbols: String) {
        var carbon = 0, symbols = ""
        if flags.contains(.control) { carbon |= controlKey; symbols += "⌃" }
        if flags.contains(.option) { carbon |= optionKey; symbols += "⌥" }
        if flags.contains(.shift) { carbon |= shiftKey; symbols += "⇧" }
        if flags.contains(.command) { carbon |= cmdKey; symbols += "⌘" }
        return (carbon, symbols)
    }

    private static func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let pressed = id.id
            if pressed == HotKey.Shortcut.screenshot.rawValue { ShotLog.write("hot key \(pressed)") }
            Task { @MainActor in
                guard !HotKey.suspended else { return }
                if let item = HotKey.itemRefs[pressed] {
                    LauncherPanel.shared.run(itemID: item.id)
                    return
                }
                guard let shortcut = Shortcut(rawValue: pressed) else { return }
                switch shortcut {
                case .launcher: LauncherPanel.shared.toggle(.all)
                case .panel: HotKey.togglePanel()
                case .clipboard: LauncherPanel.shared.toggle(.clipboard)
                case .note: NoteWindow.toggle()
                case .ai: LauncherPanel.shared.toggle(.ai)
                case .aiChat: AIChatWindow.toggle()
                case .dictation: Dictation.shared.toggle()
                case .screenshot: Capture.run(.area)
                default: shortcut.window?.run()
                }
            }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
