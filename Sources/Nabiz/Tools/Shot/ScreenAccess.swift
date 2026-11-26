// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import SwiftUI

/// Getting macOS's Screen Recording permission without a manual: a small window at the screen's top-right (so
/// System Settings stays visible next to it) with three steps, one button for each, and a fix for the case where
/// Settings shows Nabız switched on but macOS still says no. After "Quit & Reopen" it comes back saying it's ready.
@MainActor
enum ScreenAccess {
    private static var panel: NSPanel?
    static let state = ScreenAccessState()

    /// macOS's answer for this run of Nabız (it only changes after a relaunch).
    static var granted: Bool { CGPreflightScreenCaptureAccess() }

    /// A capture was asked for without the permission: explain, and remember to say "ready" after the relaunch.
    static func ask(for mode: CaptureMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "shot.pendingMode")
        // Second time round after a relaunch: Settings says yes but macOS doesn't, so lead with the fix.
        state.stuck = UserDefaults.standard.bool(forKey: "shot.openedSettings")
        state.ready = false
        show()
    }

    /// At launch: if a capture was waiting for the permission, say whether it worked.
    static func checkAfterLaunch() {
        guard let raw = UserDefaults.standard.string(forKey: "shot.pendingMode") else { return }
        if granted {
            UserDefaults.standard.removeObject(forKey: "shot.openedSettings")
            state.ready = true
            state.stuck = false
            state.pending = CaptureMode(rawValue: raw)
            show()
        } else if UserDefaults.standard.bool(forKey: "shot.openedSettings") {
            state.ready = false
            state.stuck = true
            show()
        }
    }

    /// Puts Nabız in the list (macOS adds it on the first request) and opens the right Settings page.
    static func openSettings() {
        UserDefaults.standard.set(true, forKey: "shot.openedSettings")
        _ = CGRequestScreenCaptureAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Clears Nabız's own Screen Recording entry (only Nabız's) and asks again: fixes a switch that is on in
    /// Settings but not honoured, which happens after the app was replaced by a newer build.
    static func resetAndAsk() {
        Task {
            _ = await Toolbox.run("/usr/bin/tccutil", ["reset", "ScreenCapture", Bundle.main.bundleIdentifier ?? "app.nabiz.menubar"])
            state.stuck = false
            openSettings()
        }
    }

    /// Relaunches Nabız so macOS applies the new permission (what Settings' "Quit & Reopen" does).
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    static func tryNow() {
        let mode = state.pending ?? .area
        UserDefaults.standard.removeObject(forKey: "shot.pendingMode")
        close()
        Capture.run(mode)
    }

    static func close() {
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        panel = nil
        if state.ready { UserDefaults.standard.removeObject(forKey: "shot.pendingMode") }
    }

    private static func show() {
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = .clear
            [.miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
            panel.contentViewController = NSHostingController(rootView: ScreenAccessView(state: state))
            self.panel = panel
        }
        guard let panel else { return }
        panel.layoutIfNeeded()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 20, y: screen.maxY - size.height - 20))
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }
}

@MainActor
@Observable
final class ScreenAccessState {
    var ready = false
    var stuck = false
    var pending: CaptureMode?
}

struct ScreenAccessView: View {
    @Bindable var state: ScreenAccessState

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: state.ready ? "checkmark.circle.fill" : "camera.viewfinder")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(state.ready ? Palette.green.fill : Theme.accent)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.title).foregroundStyle(Theme.text)
                    Text(subtitle).font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            if state.ready {
                Button { ScreenAccess.tryNow() } label: { primary(L("Şimdi dene", "Try it now")) }.buttonStyle(.plain)
            } else if state.stuck {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(L("Ayarlarda açık görünüyor ama macOS izni eski Nabız'a bağlı kalmış. Tek tıkla temizleyip yeniden isteyelim.",
                           "Settings shows it on, but macOS tied the permission to an older Nabız. Clear it and ask again in one click."))
                        .font(Theme.small).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                    Button { ScreenAccess.resetAndAsk() } label: { primary(L("Sıfırla ve yeniden iste", "Reset and ask again")) }.buttonStyle(.plain)
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    step(1, L("Ayarları aç", "Open Settings"), L("Doğru sayfa açılır.", "The right page opens.")) {
                        Button { ScreenAccess.openSettings() } label: { primary(L("Ayarları Aç", "Open Settings")) }.buttonStyle(.plain)
                    }
                    step(2, L("Nabız'ın anahtarını aç", "Switch Nabız on"), L("Touch ID ya da parola isteyebilir.", "It may ask for Touch ID or your password.")) {
                        EmptyView()
                    }
                    step(3, L("“Çık ve Yeniden Aç”a bas", "Press “Quit & Reopen”"), L("Nabız kapanıp açılır, bu pencere “Hazır” der.", "Nabız restarts and this window says it's ready.")) {
                        Button(L("Kendim yeniden açayım", "Restart Nabız myself")) { ScreenAccess.relaunch() }
                            .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.accent))
                    }
                }
            }
            HStack {
                if !state.ready && !state.stuck {
                    Button(L("Çalışmıyor mu? Sıfırla", "Not working? Reset")) { ScreenAccess.resetAndAsk() }
                        .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.textMuted))
                }
                Spacer()
                Button(L("Kapat", "Close")) { ScreenAccess.close() }
                    .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.textMuted))
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.xxl)
        .padding(.bottom, Theme.Spacing.l)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .background(MenuMaterial().ignoresSafeArea())
        .appearanceRoot(opaqueFill: Theme.surface)
    }

    private var title: String {
        if state.ready { return L("Hazır", "Ready") }
        return L("Ekran görüntüsü için bir izin", "One permission for screenshots")
    }

    private var subtitle: String {
        if state.ready { return L("Nabız artık ekranı görebiliyor. ⌘⇧4 ya da ⌃⌥S ile dene.", "Nabız can see the screen now. Try ⌘⇧4 or ⌃⌥S.") }
        return L("macOS, ekranı okuyan her uygulama için bir kez sorar. Görüntüler Mac'inden çıkmaz.",
                 "macOS asks once for every app that reads the screen. Your screenshots never leave your Mac.")
    }

    private func primary(_ text: String) -> some View {
        Text(text).font(Theme.bodyStrong).foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.m).frame(height: 26)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func step<Action: View>(_ number: Int, _ title: String, _ detail: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Text(verbatim: "\(number)")
                .font(Theme.smallStrong).foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22)
                .background(Theme.accent.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title).font(Theme.bodyStrong).foregroundStyle(Theme.text)
                Text(detail).font(Theme.small).foregroundStyle(Theme.textMuted)
                action()
            }
            Spacer(minLength: 0)
        }
    }
}
