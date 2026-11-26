import AppKit
import AVFoundation
import Carbon.HIToolbox
import SwiftUI

@main
enum Entry {
    @MainActor static func main() {
        Prefs.registerDefaults()
        let args = CommandLine.arguments
        // `Nabiz --mcp`: started by an AI app (Claude Code, Claude Desktop…), it connects them to the running Nabız.
        if args.contains("--mcp") { MCPBridge.run() }
        // `Nabiz --calc "100 usd"` prints what the quick calculator would show.
        if args.contains("--dev-scan") {
            // `--dev-scan`: what the developer clean-up would offer, without cleaning anything.
            for item in DevCleanup.scan() {
                print("\(item.kind.rawValue)\t\(Format.bytes(item.size))\t\(item.targets.count)\t\(item.detail)")
            }
            exit(0)
        }
        if let index = args.firstIndex(of: "--calc"), index + 1 < args.count {
            print(Calculator.evaluate(args[index + 1])?.text ?? "—")
            return
        }
        // `Nabiz --ask "question" [--engine claude|codex|gemini|onDevice]` prints the answer, for checking the AI engines.
        if let index = args.firstIndex(of: "--ask"), index + 1 < args.count {
            _ = NSApplication.shared
            let engine = args.firstIndex(of: "--engine").flatMap { args.indices.contains($0 + 1) ? AIEngine(rawValue: args[$0 + 1]) : nil }
            AIChatStore.persists = false
            Task { @MainActor in
                AIEngines.shared.refreshIfNeeded()
                while !AIEngines.shared.searched { try? await Task.sleep(for: .milliseconds(50)) }
                guard let resolved = AIEngines.shared.resolve(engine ?? .auto) else { print("no engine"); exit(1) }
                let model = args.firstIndex(of: "--model").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
                let chat = AIConversation(engine: resolved, model: model ?? "")
                // Every message after the first is a follow-up in the same chat: `--ask "a" "b"`.
                for question in args[(index + 1)...].prefix { !$0.hasPrefix("--") } {
                    chat.send(question)
                    while chat.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
                    guard let answer = chat.lastAnswer else { exit(1) }
                    if let error = answer.error { print("[\(resolved.rawValue)] failed: \(error)"); exit(1) }
                    let name = AIEngines.shared.displayName(answer.model ?? "", engine: resolved)
                    print("[\(name), \(String(format: "%.1f", answer.duration ?? 0))s]\(answer.thinking.isEmpty ? "" : " (thought)") \(answer.text)\n")
                }
                exit(0)
            }
            while true { RunLoop.main.run(until: .distantFuture) }
        }
        // `Nabiz --snapshot out.png [--dark] [--settings]` renders the panel (or settings) with live data, for layout checks.
        // `Nabiz --rec-test folder`: records part of the screen for 3 s, exports MP4 and GIF there, prints what came out.
        if let index = args.firstIndex(of: "--rec-test"), index + 1 < args.count {
            _ = NSApplication.shared
            let folder = URL(fileURLWithPath: args[index + 1])
            Task { @MainActor in
                guard let screen = NSScreen.main else { exit(1) }
                do {
                    try await RecRecorder.shared.start(screen: screen, rect: CGRect(x: 80, y: 80, width: 640, height: 400), sound: true, microphone: false)
                } catch { print("start failed: \(error)"); exit(1) }
                try? await Task.sleep(for: .seconds(3))
                guard var meta = await RecRecorder.shared.stop() else { print("nothing recorded"); exit(1) }
                print("recorded \(String(format: "%.2f", meta.duration)) s, \(meta.width)×\(meta.height), \(meta.track.moves.count) moves, \(meta.cursors.count) cursor shapes")
                let video = AVURLAsset(url: RecStore.video(for: meta.id))
                let tracks = (try? await video.load(.tracks)) ?? []
                print("source tracks: \(tracks.map(\.mediaType.rawValue))")
                // Exercise the speed-ups, a fixed shape and the added sounds too (made-up clicks and keys).
                meta.track.clicks = [RecTrack.Point(t: 0.6, x: 10, y: 10), RecTrack.Point(t: 2.4, x: 10, y: 10)]
                meta.track.typing = [1.4, 1.6, 1.8]
                var edit = meta.edit
                edit.style.clickSound = true
                edit.style.keySound = true
                edit.speeds = [RecSpeed(start: 0.5, end: 2.5, rate: 2)]
                edit.style.aspect = "16:9"
                if let built = await RecPlan.build(meta: meta, speeds: [], clickSound: true, keySound: true) {
                    for track in built.asset.tracks(withMediaType: .audio) {
                        let segments = track.segments.filter { !$0.isEmpty }.map { String(format: "%.2f", $0.timeMapping.target.start.seconds) }
                        print("audio track \(track.trackID)\(track.trackID == built.effects ? " (effects)" : ""): \(segments.count) segments \(segments.prefix(6))")
                    }
                }
                for kind in [RecExport.Kind.hd, .gif] {
                    let out = folder.appendingPathComponent("test.\(kind == .gif ? "gif" : "mp4")")
                    try? FileManager.default.removeItem(at: out)
                    let url = await RecExport.run(meta, edit: edit, kind: kind, to: out) { _ in }
                    let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
                    if kind != .gif, url != nil {
                        let asset = AVURLAsset(url: out)
                        let seconds = (try? await asset.load(.duration).seconds) ?? 0
                        let natural = (try? await asset.loadTracks(withMediaType: .video).first?.load(.naturalSize)) ?? .zero
                        print("mp4: \(String(format: "%.2f", seconds)) s, \(Int(natural.width))×\(Int(natural.height)), \(size / 1024) KB")
                        // Loudness in 50 ms steps: the clicks and keys should stand out.
                        let levels = RecWaveform.read(out, bins: Int(seconds * 20))
                        print("loudness: " + levels.map { $0 > 0.5 ? "█" : $0 > 0.15 ? "▄" : "·" }.joined())
                    } else {
                        print("\(kind.rawValue): \(url == nil ? "FAILED" : "\(size / 1024) KB")")
                    }
                }
                if args.contains("--keep") { print("kept: \(RecStore.video(for: meta.id).path)") } else { RecStore.delete(meta.id) }
                exit(0)
            }
            while true { RunLoop.main.run(until: .distantFuture) }
        }
        if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count,
           let framesIndex = args.firstIndex(of: "--rec-frames"), framesIndex + 1 < args.count {
            // `--snapshot out.png --rec-frames picture.png`: the recording look at a few moments, side by side.
            _ = NSApplication.shared
            let out = args[index + 1], picture = args[framesIndex + 1]
            Task { @MainActor in
                guard let sheet = RecDemo.frames(picture: URL(fileURLWithPath: picture), times: [0.3, 1.6, 2.3, 3.4, 5.5]),
                      let png = NSBitmapImageRep(cgImage: sheet).representation(using: .png, properties: [:]) else { exit(1) }
                exit((try? png.write(to: URL(fileURLWithPath: out))) != nil ? 0 : 1)
            }
            while true { RunLoop.main.run(until: .distantFuture) }
        }
        if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count,
           let selectorIndex = args.firstIndex(of: "--selector"), selectorIndex + 1 < args.count {
            // `--snapshot out.png --selector picture.png [--drag]`: the frozen-screen picker drawn over that picture.
            _ = NSApplication.shared
            let out = args[index + 1], picture = args[selectorIndex + 1]
            Task { @MainActor in
                guard let source = NSImage(contentsOfFile: picture)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let image = ShotSelector.preview(source, drag: args.contains("--drag")),
                      let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                else { exit(1) }
                exit((try? png.write(to: URL(fileURLWithPath: out))) != nil ? 0 : 1)
            }
            while true { RunLoop.main.run(until: .distantFuture) }
        }
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
    private var timerWasRunning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashReporter.shared.start()
        ShotExport.cleanCache()
        ShotLog.write("launch, screen access: \(ScreenAccess.granted)")
        ScreenAccess.checkAfterLaunch()
        if Prefs.bool(Prefs.aiAsk) { AIEngines.shared.refreshIfNeeded() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // After Nabız's own item, so the hider's arrow and divider land to its left.
        MenuBarHider.shared.update()
        Brightness.shared.start()
        let actions = PanelActions(
            copy: { [weak self] in self?.copy($0) },
            flash: { [weak self] in self?.flash($0) },
            close: { [weak self] in self?.panel.close() }
        )
        Monitor.panelActions = actions
        panel = StatusPanel(monitor: monitor, actions: actions)
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
            Scheduler.shared.check()
            Updater.shared.check()
            // Market prices: every 4 s when shown (panel or menu bar), every 30 s for price alerts alone.
            if (monitor.panelVisible && Prefs.bool(Prefs.showMarkets)) || Prefs.bool(Prefs.barMarket) {
                MarketStore.shared.refreshWatched(maxAge: 4)
            } else if !PriceAlerts.shared.markets.isEmpty {
                MarketStore.shared.refreshWatched(maxAge: 30)
            }
        }
        MarketStore.shared.onPrices = { [weak self] in self?.updateButton() }
        RateStore.shared.refreshIfNeeded()
        Updater.shared.check()
        AppearanceMode.apply()
        ClipboardHistory.shared.update()
        AppIndex.shared.refreshIfNeeded()
        NSApp.mainMenu = Self.editMenu()
        HotKey.togglePanel = { [weak self] in self?.togglePanel() }
        updateHotKeys()
        MCPServer.shared.update()
        CalendarAgenda.shared.update()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateHotKeys()
                MenuBarHider.shared.update()
                BrightnessKeys.shared.update()
                MCPServer.shared.update()
                CalendarAgenda.shared.update()
                AppearanceMode.apply()
                ClipboardHistory.shared.update()
                AILimitsStore.shared.refreshIfNeeded()
                self?.updateButton()
            }
        }
        updateButton()
        // While a timer runs, the menu bar counts down every second; otherwise this does nothing.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Pomodoro.shared.tick()
                FocusMode.shared.tick()
                CalendarAgenda.shared.tick()
                Backup.autoBackupIfNeeded()
                let running = CountdownTimer.shared.endsAt != nil || Pomodoro.shared.isActive || FocusMode.shared.isOn
                // One last refresh when it stops, so the countdown doesn't linger.
                if running || self.timerWasRunning { self.updateButton() }
                self.timerWasRunning = running
            }
        }
        WelcomeWindow.showIfFirstLaunch { [weak self] in self?.togglePanel() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MCPServer.shared.stop()
        KeepAwake.shared.stop()
        UsageHistory.shared.save()
        NoteStore.shared.saveNow()
        ClipboardHistory.shared.saveNow()
        AIChatStore.shared.saveNow()
        FocusMode.shared.stop()
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        panel.toggle(below: button)
    }

    private func updateHotKeys() {
        HotKey.update(.launcher, enabled: Prefs.bool(Prefs.hotkey))
        HotKey.update(.panel, enabled: Prefs.bool(Prefs.panelHotkey))
        HotKey.update(.clipboard, enabled: Prefs.bool(Prefs.clipboardHotkey) && Prefs.bool(Prefs.clipboardEnabled))
        HotKey.update(.note, enabled: Prefs.bool(Prefs.noteHotkey))
        HotKey.update(.dictation, enabled: Prefs.bool(Prefs.dictationHotkey))
        HotKey.update(.screenshot, enabled: Prefs.bool(Prefs.shotHotkey))
        HotKey.update(.record, enabled: Prefs.bool(Prefs.recHotkey))
        HotKey.update(.ai, enabled: Prefs.bool(Prefs.aiHotkey) && Prefs.bool(Prefs.aiAsk))
        HotKey.update(.aiChat, enabled: Prefs.bool(Prefs.aiChatHotkey))
        for shortcut in HotKey.Shortcut.windows { HotKey.update(shortcut, enabled: Prefs.bool(Prefs.windowHotkeys)) }
        HotKey.registerItems()
    }

    /// Without an Edit menu, ⌘C, ⌘V and ⌘A do nothing in text fields (Settings, the note). The menu bar never shows it.
    private static func editMenu() -> NSMenu {
        let main = NSMenu()
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = edit
        return main
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
        /// Shows the global shortcut on the right, as native menus do (only while it is turned on).
        func keyed(_ item: NSMenuItem, _ shortcut: HotKey.Shortcut, on: Bool) -> NSMenuItem {
            guard on else { return item }
            let combo = HotKey.combo(shortcut)
            let name = HotKey.keyName(combo.keyCode, nil)
            let key = combo.keyCode == kVK_Space ? " " : name.count == 1 ? name.lowercased() : ""
            guard !key.isEmpty else { return item }
            var flags: NSEvent.ModifierFlags = []
            if combo.modifiers & controlKey != 0 { flags.insert(.control) }
            if combo.modifiers & optionKey != 0 { flags.insert(.option) }
            if combo.modifiers & shiftKey != 0 { flags.insert(.shift) }
            if combo.modifiers & cmdKey != 0 { flags.insert(.command) }
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = flags
            return item
        }
        menu.addItem(keyed(item(L("Paneli aç", "Open Panel")) { [weak self] in self?.togglePanel() }, .panel, on: Prefs.bool(Prefs.panelHotkey)))
        menu.addItem(keyed(item(L("Başlatıcı", "Launcher")) { LauncherPanel.shared.show() }, .launcher, on: Prefs.bool(Prefs.hotkey)))
        menu.addItem(keyed(item(L("AI sohbet", "AI Chat")) { AIChatWindow.show() }, .aiChat, on: Prefs.bool(Prefs.aiChatHotkey)))
        if Prefs.bool(Prefs.aiAsk) {
            menu.addItem(keyed(item(L("AI'a sor", "Ask AI")) { LauncherPanel.shared.show(.ai) }, .ai, on: Prefs.bool(Prefs.aiHotkey)))
        }
        menu.addItem(.separator())
        menu.addItem(keyed(item(L("Pano geçmişi", "Clipboard History")) { LauncherPanel.shared.show(.clipboard) }, .clipboard,
                           on: Prefs.bool(Prefs.clipboardHotkey) && Prefs.bool(Prefs.clipboardEnabled)))
        menu.addItem(keyed(item(L("Notlar", "Notes")) { NoteWindow.toggle() }, .note, on: Prefs.bool(Prefs.noteHotkey)))
        menu.addItem(keyed(item(L("Ekran görüntüsü", "Screenshot")) { Capture.run(.area) }, .screenshot, on: Prefs.bool(Prefs.shotHotkey)))
        menu.addItem(keyed(item(RecRecorder.shared.isRecording ? L("Kaydı durdur", "Stop Recording") : L("Ekranı kaydet", "Record Screen")) { RecControl.toggle() },
                           .record, on: Prefs.bool(Prefs.recHotkey)))
        menu.addItem(keyed(item(Dictation.shared.isListening ? L("Dikteyi bitir", "Stop Dictation") : L("Dikte et", "Dictate")) { Dictation.shared.toggle() },
                           .dictation, on: Prefs.bool(Prefs.dictationHotkey)))
        let pomodoro = Pomodoro.shared
        menu.addItem(item(pomodoro.isActive ? (pomodoro.isRunning ? L("Pomodoro'yu duraklat", "Pause Pomodoro") : L("Pomodoro'ya devam et", "Resume Pomodoro"))
                                            : L("Pomodoro başlat", "Start Pomodoro")) { pomodoro.toggle() })
        menu.addItem(item(FocusMode.shared.isOn ? L("Odak modunu kapat", "Turn Focus Mode Off") : L("Odak modu", "Focus Mode")) { FocusMode.shared.toggle() })
        menu.addItem(item(L("Geçmiş", "History")) { HistoryWindow.show() })
        menu.addItem(item(L("Zamanlanmış görevler…", "Scheduled Tasks…")) { SettingsWindow.show(.schedules) })
        menu.addItem(.separator())
        menu.addItem(item(L("Neler yapabilir?", "What Can It Do?")) { HelpWindow.show() })
        menu.addItem(item(L("Ayarlar…", "Settings…"), ",") { SettingsWindow.show(nil) })
        menu.addItem(.separator())
        menu.addItem(item(L("Nabız'dan çık", "Quit Nabız"), "q") { NSApp.terminate(nil) })
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @ObservationIgnored private var rollTimer: Timer?

    /// While digits are rolling, redraw at ~60 fps; stops on its own when the roll ends.
    private func scheduleRollFrame() {
        guard BarRoll.shared.isAnimating, rollTimer == nil else { return }
        rollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rollTimer = nil
                self?.updateButton()
            }
        }
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
        let icon = symbol(critical ? "exclamationmark.triangle.fill" : BarSymbol.current)
        if MenuBarText.stacked {
            let parts = MenuBarText.parts(monitor: monitor)
            let showIcon = Prefs.bool(Prefs.barIcon) || parts.isEmpty || critical
            button.image = MenuBarText.image(parts: parts, icon: showIcon ? icon : nil, height: NSStatusBar.system.thickness)
            button.imagePosition = .imageOnly
            button.title = ""
            scheduleRollFrame()
            return
        }
        let text = MenuBarText.compose(monitor: monitor)
        let showIcon = Prefs.bool(Prefs.barIcon) || text.isEmpty || critical
        button.image = showIcon ? icon : nil
        button.imagePosition = .imageLeading
        button.attributedTitle = Prefs.bool(Prefs.barColors)
            ? MenuBarText.colouredLine(monitor: monitor, font: font, leadingSpace: showIcon)
            : NSAttributedString(string: text.isEmpty ? "" : (showIcon ? " " : "") + text, attributes: [.font: font])
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
    static var shotDoc: ShotDocument?
    static func render(to path: String, dark: Bool, settings: Bool) async -> Bool {
        let monitor = Monitor(autostart: false)
        RateStore.shared.refreshIfNeeded()
        MarketStore.shared.refreshWatched(maxAge: 0)
        ProjectStore.shared.refresh(force: true)
        DockerStore.shared.refresh()
        await monitor.tick(forceSimulators: true)
        for _ in 0..<6 {
            try? await Task.sleep(for: .milliseconds(400))
            await monitor.tick()
        }
        for _ in 0..<40 where !ProjectStore.shared.loaded { try? await Task.sleep(for: .milliseconds(100)) }
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        NSApp.appearance = appearance
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        // `--page markets` opens that Settings page; it loads the market catalog first.
        let page = value(after: "--page").flatMap(SettingsPage.init(rawValue:))
        if page == .developer {
            DevCleanupStore.shared.scan()
            for _ in 0..<1200 where DevCleanupStore.shared.scanning || DevCleanupStore.shared.scannedAt == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        if page == .markets {
            MarketStore.shared.refreshCatalog()
            try? await Task.sleep(for: .seconds(4))
        }
        let selection = SettingsSelection()
        selection.page = page ?? .general
        // `--anchor id`: open that section as a search result would (scrolled to and lit up).
        if let anchor = value(after: "--anchor") { selection.go(SettingsTarget(page: page ?? .general, anchor: anchor)) }
        let root: AnyView
        if args.contains("--welcome") {
            root = AnyView(WelcomeView {})
        } else if args.contains("--help") {
            HelpState.shared.tab = value(after: "--tab").flatMap(HelpTab.init(rawValue:)) ?? .start
            HelpState.shared.query = value(after: "--find") ?? ""
            root = AnyView(HelpView().frame(width: 720, height: 760))
        } else if args.contains("--note") {
            root = AnyView(NoteView().frame(width: 380, height: 440))
        } else if args.contains("--history") {
            root = AnyView(HistoryView().frame(width: 680, height: 560))
        } else if args.contains("--limits") {
            root = AnyView(LimitsPreview())
        } else if let text = value(after: "--ai-window") {
            // `--ai-window "question" [--engine x] [--thinking]`: the chat window with that question asked ("" = a new chat).
            AIChatStore.persists = false
            AIEngines.shared.refreshIfNeeded()
            while !AIEngines.shared.searched { try? await Task.sleep(for: .milliseconds(50)) }
            let state = AIChatWindow.state
            // `--seed`: a few made-up chats so the sidebar shows pinned, grouped and archived rows.
            if args.contains("--seed") {
                let day: TimeInterval = 86_400
                let samples: [(String, AIEngine, TimeInterval, Bool, Bool)] = [
                    (L("Haftalık plan", "Weekly plan"), .claude, 0, true, false),
                    (L("Kahve mi çay mı", "Coffee or tea"), .onDevice, 600, false, false),
                    (L("Go'da merhaba dünya", "Hello world in Go"), .codex, 3_000, false, false),
                    (L("Tatil rotası", "Holiday route"), .claude, day * 1.2, false, false),
                    (L("Kira sözleşmesi özeti", "Lease summary"), .onDevice, day * 4, false, false),
                    (L("Eski fikirler", "Old ideas"), .claude, day * 40, false, true),
                ]
                for (title, engine, age, pinned, archived) in samples.reversed() {
                    let date = Date().addingTimeInterval(-age)
                    let record = AIConversation.Record(id: UUID(), title: title, messages: [
                        AIMessage(role: .user, text: title, date: date),
                        AIMessage(role: .assistant, text: "…", engine: engine, date: date, duration: 3),
                    ], engine: engine, model: "", created: date, updated: date, pinned: pinned, archived: archived, titleEdited: true)
                    AIChatStore.shared.touch(AIConversation(record: record))
                }
                let folder = AIChatStore.shared.createFolder("PTBook")
                if let chat = AIChatStore.shared.conversations.first(where: { $0.engine == .codex }) { AIChatStore.shared.move(chat, to: folder.id) }
                if args.contains("--renaming") { AIChatWindow.state.renamingFolder = folder.id }
            }
            state.newChat()
            if let engine = value(after: "--engine").flatMap(AIEngine.init(rawValue:)) {
                state.engine = engine
                state.model = engine.chosenModel
            }
            // `--image file`: attached to the first question.
            if let image = value(after: "--image") { state.attach(file: URL(fileURLWithPath: image)) }
            if !text.isEmpty {
                // Through the box, like typing it, so attachments go along.
                state.draft = text
                state.send()
                for _ in 0..<900 where state.conversation?.isRunning == true && !args.contains("--thinking") {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if let follow = value(after: "--then") {
                    state.send(follow)
                    for _ in 0..<900 where state.conversation?.isRunning == true && !args.contains("--thinking") {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
            // `--compact`: the chat summarized; `--side "q"`: a side question; `--suggest`: wait for the suggestion.
            if args.contains("--compact") { await state.conversation?.compact() }
            if let question = value(after: "--side") {
                state.sideOpen = true
                state.sideDraft = question
                state.sendSide()
                for _ in 0..<900 where state.side?.isRunning == true { try? await Task.sleep(for: .milliseconds(100)) }
            }
            if args.contains("--suggest") { try? await Task.sleep(for: .seconds(4)) }
            // `--find "words"`: the find bar open on them.
            if let words = value(after: "--find") {
                state.startFind()
                state.findQuery = words
                state.updateFind()
            }
            root = AnyView(AIChatView(state: state).frame(width: 920, height: 660))
        } else if let text = value(after: "--launcher") {
            AppIndex.shared.refreshIfNeeded()
            try? await Task.sleep(for: .milliseconds(600))
            LauncherPanel.shared.model.reset(mode: args.contains("--clipboard") ? .clipboard : .all, text: text)
            // Ports and projects are read in the background.
            for _ in 0..<60 where !ProjectStore.shared.loaded { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .milliseconds(200))
            // `--ai`: asks the text and waits for the answer.
            if args.contains("--ai") {
                AIChatStore.persists = false
                AIEngines.shared.refreshIfNeeded()
                while !AIEngines.shared.searched { try? await Task.sleep(for: .milliseconds(50)) }
                LauncherPanel.shared.model.ask(text)
                // `--thinking`: catch it before the first words, to see the loading state.
                for _ in 0..<600 where LauncherPanel.shared.model.ai?.isRunning == true && !args.contains("--thinking") {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            if args.contains("--palette") { LauncherPanel.shared.model.paletteOpen = true }
            root = AnyView(LauncherView(model: LauncherPanel.shared.model))
        } else if args.contains("--phone-qr") {
            // `--phone-qr [--local]`: the dev server QR window (`--local`: a server only this Mac can reach).
            root = AnyView(PhoneQRView(url: "http://192.168.1.24:5173", title: "pt-takip",
                                       problem: args.contains("--local") ? PhoneQR.address(for: DevServer(pid: 1, ports: [5173], folder: "/x", project: "/x", tool: "vite", started: nil)).problem : nil,
                                       close: {}).background(MenuMaterial()))
        } else if args.contains("--rec-bar") {
            // `--rec-bar [--target window]`: the recording bar.
            let options = RecOptions()
            options.target = value(after: "--target").flatMap(RecControl.Target.init(rawValue:)) ?? .area
            options.sound = true
            root = AnyView(RecBarView(options: options).background(MenuMaterial()).clipShape(RoundedRectangle(cornerRadius: Theme.radius)).padding(20))
        } else if args.contains("--rec-editor") {
            // `--rec-editor`: the editor on the latest recording (record one with `--rec-test folder --keep`).
            guard let meta = RecStore.all().first else { return false }
            let model = RecEditorModel(meta: meta)
            try? await Task.sleep(for: .seconds(1.5))
            root = AnyView(RecEditorView(model: model))
        } else if args.contains("--access") {
            // `--access [--stuck | --ready]`: the Screen Recording guide.
            let state = ScreenAccessState()
            state.stuck = args.contains("--stuck")
            state.ready = args.contains("--ready")
            root = AnyView(ScreenAccessView(state: state))
        } else if let file = value(after: "--shot") {
            // `--shot image.png [--seed] [--tool arrow] [--frame]`: the screenshot editor on that image.
            guard let doc = ShotDocument(contentsOf: URL(fileURLWithPath: file)) else { return false }
            if args.contains("--seed") { ShotDemo.seed(doc) }
            if args.contains("--frame") { doc.background.enabled = true; doc.framePanel = true }
            if let tool = value(after: "--tool").flatMap(ShotTool.init(rawValue:)) { doc.tool = tool }
            Snapshot.shotDoc = doc
            root = AnyView(ShotEditorView(doc: doc) { _ in })
        } else if settings {
            root = AnyView(SettingsView(selection: selection).frame(width: 760, height: 560))
        } else {
            root = AnyView(PanelView(monitor: monitor, actions: PanelActions(), alwaysRender: true))
        }
        // `--chrome`: Settings in a real titled window, traffic lights and all, drawn off screen.
        // `--chrome`: Settings (or the AI window with `--ai-window`) in a real titled window, window buttons and all.
        if (settings || args.contains("--ai-window") || args.contains("--shot") || args.contains("--rec-editor")) && args.contains("--chrome") {
            let content: AnyView = args.contains("--shot") || args.contains("--rec-editor") ? root : args.contains("--ai-window") ? AnyView(AIChatView(state: AIChatWindow.state))
                : AnyView(SettingsView(selection: selection, query: value(after: "--find") ?? ""))
            let controller = NSHostingController(rootView: content.environment(\.colorScheme, dark ? .dark : .light))
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            WindowChrome.apply(window)
            window.appearance = appearance
            window.setContentSize(NSSize(width: value(after: "--width").flatMap(Double.init) ?? (settings ? 680 : 1000),
                                         height: value(after: "--height").flatMap(Double.init) ?? (settings ? 500 : 680)))
            window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            window.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(300))
            if !args.contains("--focus") { window.makeFirstResponder(nil) }
            try? await Task.sleep(for: .milliseconds(900))
            guard let frame = window.contentView?.superview,
                  let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return false }
            frame.cacheDisplay(in: frame.bounds, to: rep)
            window.orderOut(nil)
            guard let data = rep.representation(using: .png, properties: [:]) else { return false }
            return (try? data.write(to: URL(fileURLWithPath: path))) != nil
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
