import AppKit
import SwiftUI

@main
enum Entry {
    @MainActor static func main() {
        Prefs.registerDefaults()
        let args = CommandLine.arguments
        // `Nabiz --calc "100 usd"` prints what the quick calculator would show.
        if let index = args.firstIndex(of: "--calc"), index + 1 < args.count {
            print(Calculator.evaluate(args[index + 1])?.text ?? "—")
            return
        }
        // `Nabiz --snapshot out.png [--dark] [--settings]` renders the panel (or settings) with live data, for layout checks.
        if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count {
            _ = NSApplication.shared
            Task { @MainActor in
                exit(await Snapshot.render(to: args[index + 1], dark: args.contains("--dark"), settings: args.contains("--settings")) ? 0 : 1)
            }
            while true { RunLoop.main.run(until: .distantFuture) }
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = Monitor()
    private var statusItem: NSStatusItem!
    private var panel: StatusPanel!
    private var flashUntil: Date?
    private var flashMessage = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        panel = StatusPanel(monitor: monitor, actions: PanelActions(
            copy: { [weak self] in self?.copy($0) },
            flash: { [weak self] in self?.flash($0) },
            close: { [weak self] in self?.panel.close() }
        ))
        SettingsWindow.monitor = monitor
        monitor.onUpdate = { [weak self] in
            guard let self else { return }
            updateButton()
            // AI limits and rates are fetched while the panel is open, or in the background when the menu bar shows them.
            if monitor.panelVisible {
                AILimitsStore.shared.refreshIfNeeded()
            } else if !AILimitsStore.shared.enabled.isEmpty {
                // Every 5 minutes in the background: enough readings for the burn rate, light on the providers.
                AILimitsStore.shared.refreshIfNeeded(maxAge: 300)
            }
            if Prefs.bool(Prefs.barCurrency) { RateStore.shared.refreshIfNeeded() }
            Notifier.shared.check(monitor: monitor)
            // Market prices: every 10 s with the panel open, every 30 s for the menu bar.
            if monitor.panelVisible && Prefs.bool(Prefs.showMarkets) {
                MarketStore.shared.refreshWatched(maxAge: 10)
            } else if Prefs.bool(Prefs.barMarket) {
                MarketStore.shared.refreshWatched(maxAge: 30)
            }
        }
        RateStore.shared.refreshIfNeeded()
        HotKey.togglePanel = { [weak self] in self?.togglePanel() }
        updateHotKeys()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateHotKeys()
                AILimitsStore.shared.refreshIfNeeded()
                self?.updateButton()
            }
        }
        updateButton()
        WelcomeWindow.showIfFirstLaunch { [weak self] in self?.togglePanel() }
    }

    func applicationWillTerminate(_ notification: Notification) { KeepAwake.shared.stop() }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        panel.toggle(below: button)
    }

    private func updateHotKeys() {
        HotKey.update(.calculator, enabled: Prefs.bool(Prefs.hotkey))
        HotKey.update(.panel, enabled: Prefs.bool(Prefs.panelHotkey))
    }

    /// Left click opens the panel; right click (or ⌃-click) shows a short native menu.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        guard event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true else {
            togglePanel()
            return
        }
        panel.close()
        let menu = NSMenu()
        func item(_ title: String, _ key: String = "", _ action: @escaping @MainActor () -> Void) -> NSMenuItem {
            let item = ClosureMenuItem(title: title, keyEquivalent: key, handler: action)
            return item
        }
        menu.addItem(item(L("Paneli aç", "Open Panel")) { [weak self] in self?.togglePanel() })
        menu.addItem(item(L("Hızlı hesap", "Quick Calculator")) { CalculatorPanel.shared.show() })
        menu.addItem(.separator())
        menu.addItem(item(L("Ayarlar…", "Settings…"), ",") { SettingsWindow.show(nil) })
        menu.addItem(.separator())
        menu.addItem(item(L("Nabız'dan çık", "Quit Nabız"), "q") { NSApp.terminate(nil) })
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        if let flashUntil, flashUntil > Date() {
            button.imagePosition = .imageLeading
            button.image = symbol("checkmark.circle.fill")
            button.attributedTitle = NSAttributedString(string: " " + flashMessage, attributes: [.font: font])
            return
        }
        let critical = monitor.system?.pressure == .critical
        let icon = symbol(critical ? "exclamationmark.triangle.fill" : "gauge.with.dots.needle.33percent")
        if MenuBarText.stacked {
            let parts = MenuBarText.parts(monitor: monitor)
            let showIcon = Prefs.bool(Prefs.barIcon) || parts.isEmpty || critical
            button.image = MenuBarText.image(parts: parts, icon: showIcon ? icon : nil, height: NSStatusBar.system.thickness)
            button.imagePosition = .imageOnly
            button.title = ""
            return
        }
        let text = MenuBarText.compose(monitor: monitor)
        let showIcon = Prefs.bool(Prefs.barIcon) || text.isEmpty || critical
        button.image = showIcon ? icon : nil
        button.imagePosition = .imageLeading
        button.attributedTitle = NSAttributedString(string: text.isEmpty ? "" : (showIcon ? " " : "") + text, attributes: [.font: font])
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash(L("Kopyalandı", "Copied"))
    }

    /// A short confirmation in place of the menu bar values for a moment.
    private func flash(_ message: String) {
        flashMessage = message
        flashUntil = Date().addingTimeInterval(1.5)
        updateButton()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            self?.updateButton()
        }
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Nabız")
        image?.isTemplate = true
        return image
    }
}

/// The opaque panel under the status item. Closes on Escape, on a click elsewhere, or on a second click of the item.
/// A menu item that runs a closure.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, keyEquivalent: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}

@MainActor
final class StatusPanel {
    private let window = KeyPanel()
    private let monitor: Monitor
    private var anchor: NSRect = .zero
    private weak var button: NSStatusBarButton?
    private var resizeObserver: NSObjectProtocol?

    init(monitor: Monitor, actions: PanelActions) {
        self.monitor = monitor
        let controller = NSHostingController(rootView: PanelView(monitor: monitor, actions: actions))
        controller.sizingOptions = .preferredContentSize
        window.contentViewController = controller
        window.useMenuMaterial()
        window.onClose = { [weak self] in self?.monitor.panelVisible = false }
        // The status item toggles the panel itself; its click must not count as "outside".
        window.keepsOpenOnClick = { [weak self] event in event.window != nil && event.window === self?.button?.window }
        // Keep the top edge pinned under the menu bar as the content grows or shrinks.
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
    }

    func toggle(below button: NSStatusBarButton) {
        if window.isVisible { close(); return }
        self.button = button
        guard let buttonWindow = button.window else { return }
        anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        monitor.panelVisible = true
        AILimitsStore.shared.refreshIfNeeded()
        MarketStore.shared.refreshWatched(maxAge: 10)
        Toolbox.shared.refresh()
        if let view = window.contentView { window.setContentSize(view.fittingSize) }
        place()
        window.present()
    }

    func close() {
        guard window.isVisible else { return }
        window.orderOut(nil)
    }

    private func place() {
        let size = window.frame.size
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.origin) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = min(max(anchor.minX, visible.minX + Theme.Spacing.s), visible.maxX - size.width - Theme.Spacing.s)
        let top = anchor.minY - Theme.Spacing.xs
        window.setFrameOrigin(NSPoint(x: x, y: top - size.height))
    }
}

@MainActor
enum Snapshot {
    static func render(to path: String, dark: Bool, settings: Bool) async -> Bool {
        let monitor = Monitor(autostart: false)
        RateStore.shared.refreshIfNeeded()
        MarketStore.shared.refreshWatched(maxAge: 0)
        await monitor.tick(forceSimulators: true)
        for _ in 0..<6 {
            try? await Task.sleep(for: .milliseconds(400))
            await monitor.tick()
        }
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        NSApp.appearance = appearance
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        // `--page markets` opens that Settings page; it loads the market catalog first.
        let page = value(after: "--page").flatMap(SettingsPage.init(rawValue:))
        if page == .markets {
            MarketStore.shared.refreshCatalog()
            try? await Task.sleep(for: .seconds(4))
        }
        let selection = SettingsSelection()
        selection.page = page ?? .general
        let root: AnyView
        if args.contains("--welcome") {
            root = AnyView(WelcomeView {})
        } else if let text = value(after: "--calculator") {
            root = AnyView(CalculatorView(text: text) {})
        } else if settings {
            root = AnyView(SettingsView(selection: selection).frame(width: 760, height: 560))
        } else {
            root = AnyView(PanelView(monitor: monitor, actions: PanelActions()))
        }
        let host = NSHostingView(rootView: root
            .background(settings ? Color.clear : Theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: settings ? 0 : Theme.radius, style: .continuous))
            .environment(\.colorScheme, dark ? .dark : .light))
        host.appearance = appearance
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        try? await Task.sleep(for: .milliseconds(300))
        let size = host.fittingSize
        window.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(500))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
