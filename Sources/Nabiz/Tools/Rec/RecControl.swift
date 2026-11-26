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
        let end = NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 48, width: size.width, height: size.height)
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(still ? end : end.offsetBy(dx: 0, dy: -14), display: true)
        panel.alphaValue = 0
        panel.onClose = { bar = nil; RecPicker.close() }
        // Clicks on the picker (Nabız's own windows) mustn't close the bar.
        panel.keepsOpenOnClick = { _ in true }
        panel.present()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = still ? 0.12 : 0.26
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = 1
        }
        bar = panel
        RecPicker.show(options.target)
    }

    static func closeBar() {
        bar?.orderOut(nil)
        bar = nil
        RecPicker.close()
    }

    /// A target picked in the bar: the picker on screen switches with it, like ⌘⇧5.
    static func choose(_ target: Target) {
        options.target = target
        RecPicker.show(target)
    }

    /// The bar's record button: the whole screen with the pointer, or the area on screen.
    static func begin() {
        switch options.target {
        case .screen:
            let screen = RecPicker.hoveredScreen ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
            record(screen: screen, rect: nil, window: nil)
        case .area:
            guard let (screen, rect) = RecPicker.areaOnScreen() else { return }
            record(screen: screen, rect: rect, window: nil)
        case .window:
            Monitor.panelActions.flash(L("Kaydetmek için bir pencereye tıkla", "Click a window to record it"))
        }
    }

    /// Starts after the picker: asks for the camera first if it's on, then counts down.
    static func record(screen: NSScreen, rect: CGRect?, window: CGWindowID?) {
        closeBar()
        options.save()
        Task {
            if options.camera, !(await RecCamera.allowed()) {
                options.camera = false
                Monitor.panelActions.flash(L("Kamera izni yok", "No camera access"))
            }
            count(on: screen, rect: rect, window: window)
        }
    }

    // MARK: Countdown

    private static func count(on screen: NSScreen, rect: CGRect?, window: CGWindowID?) {
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
                try await RecRecorder.shared.start(screen: screen, rect: rect, window: window, sound: options.sound,
                                                  microphone: options.microphone, camera: options.camera)
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

/// The recording bar, in Nabız's own look: frosted, 28-point controls, thin dividers, the chosen target lit with a
/// soft highlight that slides between them, the accent only for what's on and for the one main action.
struct RecBarView: View {
    @Bindable var options: RecOptions
    @Namespace private var selection

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            BarButton(symbol: "xmark", help: L("Kapat  ⎋", "Close  ⎋")) { RecControl.closeBar() }
            divider
            HStack(spacing: 2) {
                ForEach(RecControl.Target.allCases) { target in
                    targetButton(target)
                }
            }
            divider
            ShotToolButton(symbol: options.sound ? "speaker.wave.2" : "speaker.slash", help: L("Bilgisayarın sesi", "The Mac's sound"),
                           active: options.sound) { options.sound.toggle() }
            ShotToolButton(symbol: options.microphone ? "mic" : "mic.slash",
                           help: options.microphoneAvailable ? L("Mikrofon", "Microphone") : L("Mikrofon için macOS 15 gerekir", "The microphone needs macOS 15"),
                           active: options.microphone) { options.microphone.toggle() }
                .disabled(!options.microphoneAvailable)
                .opacity(options.microphoneAvailable ? 1 : 0.4)
            ShotToolButton(symbol: options.camera ? "video" : "video.slash", help: L("Kamera, köşede", "Camera, in a corner"),
                           active: options.camera) { options.camera.toggle() }
            divider
            ZStack {
            if options.target == .window {
                Text(L("Bir pencereye tıkla", "Click a window"))
                    .font(Theme.body).foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, Theme.Spacing.s)
                    .frame(height: 28)
                    .transition(.opacity)
            } else {
                Button { RecControl.begin() } label: {
                    HStack(spacing: Theme.Spacing.xs + 2) {
                        Image(systemName: "record.circle").font(.system(size: 13, weight: .semibold))
                        Text(L("Kaydet", "Record")).font(Theme.bodyStrong)
                        Text(verbatim: "↩").font(Theme.small).opacity(0.75)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.m)
                    .frame(height: 28)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .transition(.opacity)
            }
            }
            // One width for both, so the bar never jumps.
            .frame(width: 136)
        }
        .animation(.spring(duration: 0.28, bounce: 0.12), value: options.target)
        .padding(Theme.Spacing.s)
        .fixedSize()
        .onExitCommand { RecControl.closeBar() }
        .appearanceRoot(opaqueFill: Theme.surface)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 18).padding(.horizontal, Theme.Spacing.xs)
    }

    private func targetButton(_ target: RecControl.Target) -> some View {
        let chosen = options.target == target
        return Button { RecControl.choose(target) } label: {
            HStack(spacing: Theme.Spacing.xs + 2) {
                Image(systemName: target.symbol).font(.system(size: 13))
                    .foregroundStyle(chosen ? Theme.accent : Theme.textMuted)
                Text(target.title).font(chosen ? Theme.bodyStrong : Theme.body)
                    .foregroundStyle(chosen ? Theme.text : Theme.textMuted)
            }
            .padding(.horizontal, Theme.Spacing.s + 2)
            .frame(height: 28)
            .background {
                if chosen {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.hover)
                        .matchedGeometryEffect(id: "target", in: selection)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
