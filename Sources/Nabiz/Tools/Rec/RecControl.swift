import AppKit
import AVFoundation
import SwiftUI

/// Starting and stopping a recording: a bar at the bottom of the screen (like macOS's ⌘⇧5) to pick the whole
/// screen, a window or an area and the sound; a 3-2-1 countdown; a red dot and the time in the menu bar while it
/// runs (click it, or press the shortcut again, to stop); then the editor opens.
@MainActor
enum RecControl {
    enum Target: String, CaseIterable, Identifiable {
        case screen, window, area
        var id: String { rawValue }
        var title: String {
            switch self {
            case .screen: L("Tüm ekran", "Whole screen")
            case .window: L("Pencere", "Window")
            case .area: L("Alan", "Area")
            }
        }
        var symbol: String {
            switch self {
            case .screen: "display"
            case .window: "macwindow"
            case .area: "rectangle.dashed"
            }
        }
    }

    private static var bar: NSPanel?
    private static var countdown: NSPanel?
    private static var outline: NSPanel?
    private static var indicator: NSStatusItem?
    private static var ticker: Timer?
    static let options = RecOptions()

    /// The shortcut and the launcher: open the bar, or stop if a recording is running.
    static func toggle() {
        if RecRecorder.shared.isRecording { stop(); return }
        if bar != nil { closeBar(); return }
        guard ScreenAccess.granted else { ScreenAccess.ask(for: .area); return }
        showBar()
    }

    // MARK: The bar

    private static func showBar() {
        Monitor.panelActions.close()
        LauncherPanel.shared.close()
        let panel = KeyPanel()
        panel.level = .statusBar
        panel.contentViewController = NSHostingController(rootView: RecBarView(options: options))
        panel.useMenuMaterial()
        panel.layoutIfNeeded()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let size = panel.contentViewController?.view.fittingSize ?? NSSize(width: 520, height: 52)
        panel.setFrame(NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 48,
                              width: size.width, height: size.height), display: true)
        panel.onClose = { bar = nil }
        panel.present()
        bar = panel
    }

    static func closeBar() {
        bar?.orderOut(nil)
        bar = nil
    }

    /// The bar's record button.
    static func begin() {
        closeBar()
        let target = options.target
        options.save()
        if options.camera {
            // Ask for the camera before the countdown, not in the middle of it.
            Task {
                if !(await RecCamera.allowed()) {
                    options.camera = false
                    Monitor.panelActions.flash(L("Kamera izni yok", "No camera access"))
                }
                pick(target)
            }
            return
        }
        pick(target)
    }

    private static func pick(_ target: Target) {
        switch target {
        case .screen:
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
            count(on: screen, rect: nil)
        case .window, .area:
            ShotSelector.begin(windowMode: target == .window) { result in
                guard let result else { return }
                count(on: result.screen, rect: result.rect)
            }
        }
    }

    // MARK: Countdown

    private static func count(on screen: NSScreen, rect: CGRect?) {
        let area = rect ?? CGRect(origin: .zero, size: screen.frame.size)
        // The area in global (bottom-left) coordinates.
        let global = NSRect(x: screen.frame.minX + area.minX, y: screen.frame.maxY - area.maxY, width: area.width, height: area.height)
        let state = RecCountdownState()
        let panel = NSPanel(contentRect: global, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: RecCountdownView(state: state))
        panel.setFrame(global, display: true)
        panel.orderFrontRegardless()
        countdown = panel
        Task {
            for n in [3, 2, 1] {
                state.number = n
                try? await Task.sleep(for: .milliseconds(800))
            }
            countdown?.orderOut(nil)
            countdown = nil
            do {
                try await RecRecorder.shared.start(screen: screen, rect: rect, sound: options.sound, microphone: options.microphone,
                                                  camera: options.camera)
                showRecording(global: global, whole: rect == nil)
            } catch {
                Monitor.panelActions.flash(L("Kayıt başlamadı", "Recording didn't start"))
                ShotLog.write("recording failed: \(error)")
            }
        }
    }

    // MARK: While recording

    private static func showRecording(global: NSRect, whole: Bool) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = RecStopTarget.shared
        item.button?.action = #selector(RecStopTarget.stop)
        item.button?.toolTip = L("Kaydı durdur", "Stop recording")
        indicator = item
        updateIndicator()
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in MainActor.assumeIsolated { updateIndicator() } }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        // A thin frame around a recorded area (left out of the recording itself).
        if !whole {
            let panel = NSPanel(contentRect: global.insetBy(dx: -3, dy: -3), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.ignoresMouseEvents = true
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.contentView = NSHostingView(rootView: RoundedRectangle(cornerRadius: 4)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(Color.red.opacity(0.8)))
            panel.orderFrontRegardless()
            outline = panel
        }
    }

    private static func updateIndicator() {
        guard let button = indicator?.button, let started = RecRecorder.shared.startedAt else { return }
        let seconds = Int(Date().timeIntervalSince(started))
        let title = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: NSColor.systemRed,
                                                                        .font: NSFont.systemFont(ofSize: 12, weight: .bold)])
        title.append(NSAttributedString(string: String(format: "%d:%02d", seconds / 60, seconds % 60),
                                        attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]))
        button.attributedTitle = title
    }

    static func stop() {
        ticker?.invalidate()
        ticker = nil
        if let indicator { NSStatusBar.system.removeStatusItem(indicator) }
        indicator = nil
        outline?.orderOut(nil)
        outline = nil
        guard RecRecorder.shared.isRecording else { return }
        Task {
            guard let meta = await RecRecorder.shared.stop() else {
                Monitor.panelActions.flash(L("Kayıt boş", "Nothing was recorded"))
                return
            }
            RecEditor.show(meta)
        }
    }
}

/// The status item's action needs an Objective-C target.
final class RecStopTarget: NSObject {
    @MainActor static let shared = RecStopTarget()
    @MainActor @objc func stop() { RecControl.stop() }
}

/// What the bar is set to; remembered between recordings.
@MainActor
@Observable
final class RecOptions {
    var target: RecControl.Target
    var sound: Bool
    var microphone: Bool
    var camera: Bool

    init() {
        let defaults = UserDefaults.standard
        target = RecControl.Target(rawValue: defaults.string(forKey: "rec.target") ?? "") ?? .area
        sound = defaults.object(forKey: "rec.sound") as? Bool ?? true
        microphone = defaults.bool(forKey: "rec.microphone")
        camera = defaults.bool(forKey: "rec.camera")
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(target.rawValue, forKey: "rec.target")
        defaults.set(sound, forKey: "rec.sound")
        defaults.set(microphone, forKey: "rec.microphone")
        defaults.set(camera, forKey: "rec.camera")
    }

    /// The microphone comes through ScreenCaptureKit from macOS 15.
    var microphoneAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }
}

struct RecBarView: View {
    @Bindable var options: RecOptions

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            BarButton(symbol: "xmark", help: L("Kapat  ⎋", "Close  ⎋")) { RecControl.closeBar() }
            divider
            ForEach(RecControl.Target.allCases) { target in
                Button { options.target = target } label: {
                    VStack(spacing: 3) {
                        Image(systemName: target.symbol).font(.system(size: 15))
                        Text(target.title).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(options.target == target ? Theme.accent : Theme.text)
                    .frame(width: 70, height: 42)
                    .background(options.target == target ? Theme.accent.opacity(0.15) : .clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            divider
            toggle(on: $options.sound, symbol: options.sound ? "speaker.wave.2.fill" : "speaker.slash",
                   help: L("Bilgisayarın sesi", "The Mac's sound"))
            toggle(on: $options.microphone, symbol: options.microphone ? "mic.fill" : "mic.slash",
                   help: options.microphoneAvailable ? L("Mikrofon", "Microphone") : L("Mikrofon için macOS 15 gerekir", "The microphone needs macOS 15"))
                .disabled(!options.microphoneAvailable)
            toggle(on: $options.camera, symbol: options.camera ? "video.fill" : "video.slash", help: L("Kamera, köşede", "Camera, in a corner"))
            divider
            Button { RecControl.begin() } label: {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 9, height: 9)
                    Text(L("Kayda başla", "Record")).font(Theme.bodyStrong)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(height: 30)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .fixedSize()
        .onExitCommand { RecControl.closeBar() }
        .appearanceRoot(opaqueFill: Theme.surface)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 28)
    }

    private func toggle(on: Binding<Bool>, symbol: String, help: String) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(on.wrappedValue ? Theme.accent : Theme.textMuted)
                .frame(width: 34, height: 34)
                .background(on.wrappedValue ? Theme.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

@MainActor
@Observable
final class RecCountdownState {
    var number = 3
}

struct RecCountdownView: View {
    let state: RecCountdownState

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
            Text(verbatim: "\(state.number)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 168, height: 168)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
                .contentTransition(.numericText(countsDown: true))
                .animation(.spring(duration: 0.35), value: state.number)
        }
    }
}
