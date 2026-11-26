// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import ApplicationServices
import Observation

/// A window position of the user's own: a share of the screen ("left 70%"), for the window in front or for one app.
/// Layouts that share a set name are applied together ("Code": Xcode left two thirds, Simulator right third).
struct WindowLayout: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// Percent of the usable screen, measured from the top left.
    var x = 0
    var y = 0
    var width = 50
    var height = 100
    /// A bundle id: place this app's window (opening the app if needed) instead of the one in front.
    var app: String?
    /// Layouts with the same set name also run together as "Set: name".
    var set = ""

    var commandID: String { "layout:\(id.uuidString)" }

    var appName: String? {
        guard let app, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// The frame on a screen whose usable area (AppKit coordinates, bottom-left origin) is `v`.
    func frame(in v: CGRect) -> CGRect {
        let clamp: (Int) -> CGFloat = { CGFloat(min(max($0, 0), 100)) / 100 }
        let w = v.width * clamp(width), h = v.height * clamp(height)
        let left = v.minX + v.width * clamp(x)
        let top = v.maxY - v.height * clamp(y)
        return CGRect(x: min(left, v.maxX - w), y: max(top - h, v.minY), width: w, height: h)
    }

    static var presets: [WindowLayout] { [
        WindowLayout(name: L("Sol üçte iki", "Left two thirds"), x: 0, y: 0, width: 67, height: 100),
        WindowLayout(name: L("Sağ üçte iki", "Right two thirds"), x: 33, y: 0, width: 67, height: 100),
        WindowLayout(name: L("Sol üst çeyrek", "Top left quarter"), x: 0, y: 0, width: 50, height: 50),
        WindowLayout(name: L("Sağ üst çeyrek", "Top right quarter"), x: 50, y: 0, width: 50, height: 50),
        WindowLayout(name: L("Sol alt çeyrek", "Bottom left quarter"), x: 0, y: 50, width: 50, height: 50),
        WindowLayout(name: L("Sağ alt çeyrek", "Bottom right quarter"), x: 50, y: 50, width: 50, height: 50),
        WindowLayout(name: L("Ortada geniş", "Wide centre"), x: 10, y: 5, width: 80, height: 90),
    ] }
}

@MainActor
@Observable
final class WindowLayouts {
    static let shared = WindowLayouts()
    private static let key = "windowLayouts"

    var layouts: [WindowLayout] = [] {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([WindowLayout].self, from: data) { layouts = saved }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(layouts), forKey: Self.key)
    }

    /// Set names in the order they first appear.
    var sets: [String] {
        var seen: [String] = []
        for layout in layouts {
            let name = layout.set.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !seen.contains(name) { seen.append(name) }
        }
        return seen
    }

    func add(_ layout: WindowLayout) { layouts.append(layout) }

    func remove(_ id: UUID) { layouts.removeAll { $0.id == id } }

    func apply(_ layout: WindowLayout) {
        guard Paster.isTrusted else {
            Paster.requestTrust()
            return
        }
        if let bundle = layout.app {
            Self.withWindow(of: bundle) { window in
                if let window { Self.place(window, layout) } else {
                    Monitor.panelActions.flash(L("\(layout.appName ?? bundle) penceresi bulunamadı", "No \(layout.appName ?? bundle) window"))
                }
            }
        } else if let window = Self.frontWindow() {
            Self.place(window, layout)
        } else {
            NSSound.beep()
        }
    }

    func applySet(_ name: String) {
        let members = layouts.filter { $0.set.trimmingCharacters(in: .whitespaces) == name }
        guard !members.isEmpty else { return }
        // App windows first, the front-window ones last (they act on whatever ends up in front).
        for layout in members.sorted(by: { ($0.app == nil ? 1 : 0) < ($1.app == nil ? 1 : 0) }) { apply(layout) }
        Monitor.panelActions.flash(L("Düzen: \(name)", "Set: \(name)"))
    }

    // MARK: Accessibility

    private static func frontWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return focusedWindow(of: app.processIdentifier)
    }

    private static func focusedWindow(of pid: pid_t) -> AXUIElement? {
        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
           let value, CFGetTypeID(value) == AXUIElementGetTypeID() { return (value as! AXUIElement) }
        var list: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &list) == .success,
              let windows = list as? [AXUIElement] else { return nil }
        return windows.first
    }

    /// The app's main window; opens the app first and waits up to 5 s for a window when it isn't running.
    private static func withWindow(of bundle: String, _ body: @escaping @MainActor (AXUIElement?) -> Void) {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first,
           let window = focusedWindow(of: running.processIdentifier) {
            body(window)
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { body(nil); return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in
                for _ in 0..<25 {
                    if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first,
                       let window = focusedWindow(of: running.processIdentifier) {
                        body(window)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
                body(nil)
            }
        }
    }

    private static func place(_ window: AXUIElement, _ layout: WindowLayout) {
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return }
        var position = CGPoint.zero, current = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &current)
        // AX uses a top-left origin on the main screen; AppKit a bottom-left one.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitFrame = CGRect(x: position.x, y: mainHeight - position.y - current.height, width: current.width, height: current.height)
        let screen = NSScreen.screens.max {
            $0.frame.intersection(appKitFrame).width * $0.frame.intersection(appKitFrame).height
                < $1.frame.intersection(appKitFrame).width * $1.frame.intersection(appKitFrame).height
        } ?? NSScreen.main
        guard let screen else { return }
        let target = layout.frame(in: screen.visibleFrame)
        var origin = CGPoint(x: target.minX, y: mainHeight - target.maxY)
        var size = target.size
        if let newPosition = AXValueCreate(.cgPoint, &origin), let newSize = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, newSize)
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, newPosition)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, newSize)
        }
    }
}
