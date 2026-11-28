// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import AVFoundation
import EventKit
import ServiceManagement
import SwiftUI

/// Shown once, on first launch: what Nabız is, where it lives, whether it should open at login, then the
/// permissions that switch on its extras (each one optional). Closing it any way counts as seen.
@MainActor
enum WelcomeWindow {
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    static func showIfFirstLaunch(openPanel: @escaping @MainActor () -> Void) {
        guard !Prefs.bool(Prefs.onboarded) else { return }
        // A new install meets everything here; the panel's "New in this version" is for people who update.
        UserDefaults.standard.set(WhatsNew.id, forKey: Prefs.seenVersion)
        let view = WelcomeView {
            Self.window?.close()
            openPanel()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(Theme.surface)
        window.center()
        self.window = window
        // The red button too: once seen, the welcome doesn't come back at every launch.
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                UserDefaults.standard.set(true, forKey: Prefs.onboarded)
                if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
                closeObserver = nil
                Self.window = nil
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            NSRunningApplication.current.activate(from: front, options: [])
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

struct WelcomeView: View {
    let onStart: () -> Void
    @State private var openAtLogin = true
    @State private var step: Step
    /// Why macOS refused to add Nabız to the login items, if it did.
    @State private var loginError: String?

    enum Step { case intro, permissions }

    init(step: Step = .intro, onStart: @escaping () -> Void) {
        self.onStart = onStart
        _step = State(initialValue: step)
    }

    var body: some View {
        Group {
            switch step {
            case .intro: intro
            case .permissions: permissions
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 460)
        .background(Theme.surface)
    }

    private var intro: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.m) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 88, height: 88)
                Text(L("Nabız'a hoş geldin", "Welcome to Nabız")).font(Theme.title).foregroundStyle(Theme.text)
                Text(L("Mac'inin nabzı artık menü çubuğunda.", "Your Mac's pulse, now in the menu bar."))
                    .font(Theme.body).foregroundStyle(Theme.textMuted)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Feature(symbol: "menubar.arrow.up.rectangle",
                        title: L("Menü çubuğunda", "In the menu bar"),
                        detail: L("CPU ve RAM sağ üstte. Tıklayınca panel açılır.", "CPU and RAM at the top right. Click to open the panel."))
                Feature(symbol: "bolt.heart",
                        title: L("Tek tuşla çözüm", "One-tap fixes"),
                        detail: L("Mac yavaşlarsa sebebini ve çözümünü gösterir.", "When the Mac slows down, it shows why and fixes it."))
                Feature(symbol: "sparkles",
                        title: L("AI ve başlatıcı", "AI and the launcher"),
                        detail: L("\(HotKey.label(.launcher)) ile her şeyi bul ya da sor; \(HotKey.label(.aiChat)) ile AI sohbeti aç.",
                                  "\(HotKey.label(.launcher)) finds anything or asks AI; \(HotKey.label(.aiChat)) opens the AI chat."))
                Feature(symbol: "square.grid.2x2",
                        title: L("Araçlar ve piyasalar", "Tools and markets"),
                        detail: L("Hesap makinesi, döviz, Hyperliquid fiyatları, AI limitleri.",
                                  "Calculator, currencies, Hyperliquid prices, AI limits."))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: Theme.Spacing.m) {
                Toggle(L("Mac açılınca Nabız da açılsın", "Open Nabız when the Mac starts"), isOn: $openAtLogin)
                    .toggleStyle(.switch)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    if openAtLogin { registerAtLogin() }
                    withAnimation(.easeOut(duration: 0.2)) { step = .permissions }
                } label: {
                    Text(L("Devam", "Continue")).font(Theme.bodyStrong).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(L("İzinler", "Permissions")).font(Theme.title).foregroundStyle(Theme.text)
                Text(L("Hepsi isteğe bağlı. Bir özelliği ilk kullandığında da sorulur.",
                       "All optional. Each is also asked for the first time you use it."))
                    .font(Theme.small).foregroundStyle(Theme.textMuted)
            }
            // macOS doesn't announce permission changes, so the rows look again every second.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(spacing: 0) {
                    ForEach(Permission.allCases) { PermissionRow(permission: $0) }
                    if let loginError {
                        LoginFailedRow(reason: loginError) { registerAtLogin() }
                    }
                }
            }
            Text(L("Kısayolları (\(HotKey.label(.launcher)) gibi) sonra Ayarlar → Kısayollar'dan değiştirebilirsin.",
                   "You can change the shortcuts (like \(HotKey.label(.launcher))) later in Settings → Shortcuts."))
                .font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("Geri", "Back")) { withAnimation(.easeOut(duration: 0.2)) { step = .intro } }
                Spacer()
                Button(L("Atla", "Skip")) { finish() }
                Button { finish() } label: {
                    Text(L("Başla", "Get started")).font(Theme.bodyStrong).padding(.horizontal, Theme.Spacing.m)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Prefs.onboarded)
        onStart()
    }

    private func registerAtLogin() {
        do {
            try SMAppService.mainApp.register()
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
    }
}

/// The permissions Nabız can use, what each unlocks and how to ask for it.
enum Permission: String, CaseIterable, Identifiable {
    case screen, accessibility, calendar, microphone

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .screen: "camera.viewfinder"
        case .accessibility: "hand.point.up.left"
        case .calendar: "calendar"
        case .microphone: "mic"
        }
    }

    var title: String {
        switch self {
        case .screen: L("Ekran kaydı", "Screen Recording")
        case .accessibility: L("Erişilebilirlik", "Accessibility")
        case .calendar: L("Takvim", "Calendar")
        case .microphone: L("Mikrofon", "Microphone")
        }
    }

    var unlocks: String {
        switch self {
        case .screen: L("ekran görüntüsü ve kayıt", "screenshots and recordings")
        case .accessibility: L("yapıştırma ve pencere yerleşimi", "pasting and window layouts")
        case .calendar: L("paneldeki toplantılar ve katılma", "meetings in the panel, one-click join")
        case .microphone: L("dikte ve kayıtta sesin", "dictation and your voice in recordings")
        }
    }

    var pane: String {
        switch self {
        case .screen: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        case .calendar: "Privacy_Calendars"
        case .microphone: "Privacy_Microphone"
        }
    }

    @MainActor var granted: Bool {
        switch self {
        case .screen: ScreenAccess.granted
        case .accessibility: Paster.isTrusted
        case .calendar: EKEventStore.authorizationStatus(for: .event) == .fullAccess
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    /// The system's own prompt when macOS still asks; its Settings page once it has been answered.
    @MainActor func request() {
        switch self {
        case .screen:
            ScreenAccess.openSettings()
        case .accessibility:
            Paster.requestTrust()
        case .calendar:
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                Task {
                    let allowed = (try? await EKEventStore().requestFullAccessToEvents()) ?? false
                    // Asked for here, so the panel shows today's meetings right away.
                    if allowed { UserDefaults.standard.set(true, forKey: Prefs.calendarEnabled) }
                }
            } else {
                openSettings()
            }
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                Task { _ = await AVCaptureDevice.requestAccess(for: .audio) }
            } else {
                openSettings()
            }
        }
    }

    @MainActor func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}

private struct PermissionRow: View {
    let permission: Permission

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: permission.symbol).font(Theme.body).foregroundStyle(Theme.accent).frame(width: Theme.menuIcon)
            Text(verbatim: permission.title).font(Theme.body).foregroundStyle(Theme.text)
            Text(verbatim: permission.unlocks).font(Theme.small).foregroundStyle(Theme.textMuted)
                .lineLimit(1).truncationMode(.tail).help(permission.unlocks)
            Spacer(minLength: Theme.Spacing.s)
            if permission.granted {
                Label(L("Verildi", "Granted"), systemImage: "checkmark.circle.fill")
                    .font(Theme.small).foregroundStyle(Palette.green.mark)
            } else {
                Button(L("İzin ver", "Grant")) { permission.request() }
                    .controlSize(.small)
                    .accessibilityLabel(L("\(permission.title) izni ver", "Grant \(permission.title)"))
            }
        }
        .frame(height: Theme.menuRow + Theme.Spacing.s)
        .accessibilityElement(children: .combine)
    }
}

/// macOS said no to "open at login": the reason, and a way to do it by hand.
private struct LoginFailedRow: View {
    let reason: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "power").font(Theme.body).foregroundStyle(Theme.warning.mark).frame(width: Theme.menuIcon)
            Text(L("Açılışta açılamadı", "Couldn't open at login")).font(Theme.body).foregroundStyle(Theme.text)
            Text(verbatim: reason).font(Theme.small).foregroundStyle(Theme.textMuted)
                .lineLimit(1).truncationMode(.tail)
                .help(L("\(reason) Sistem Ayarları → Genel → Giriş Öğeleri'nden Nabız'ı ekleyebilirsin.",
                        "\(reason) You can add Nabız in System Settings → General → Login Items."))
            Spacer(minLength: Theme.Spacing.s)
            Button(L("Giriş öğeleri…", "Login Items…")) {
                retry()
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
            }
            .controlSize(.small)
        }
        .frame(height: Theme.menuRow + Theme.Spacing.s)
    }
}

private struct Feature: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .font(Theme.title)
                .foregroundStyle(Theme.accent)
                .frame(width: Theme.Spacing.xxl)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(verbatim: title).font(Theme.bodyStrong).foregroundStyle(Theme.text)
                Text(verbatim: detail).font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
