import AppKit
import ServiceManagement
import SwiftUI

/// Shown once, on first launch: what Nabız is, where it lives, and whether it should open at login.
@MainActor
enum WelcomeWindow {
    private static var window: NSWindow?

    static func showIfFirstLaunch(openPanel: @escaping @MainActor () -> Void) {
        guard !Prefs.bool(Prefs.onboarded) else { return }
        // A new install meets everything here; the panel's "New in this version" is for people who update.
        UserDefaults.standard.set(WhatsNew.id, forKey: Prefs.seenVersion)
        let view = WelcomeView {
            UserDefaults.standard.set(true, forKey: Prefs.onboarded)
            window?.close()
            window = nil
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

    var body: some View {
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
                    if openAtLogin { try? SMAppService.mainApp.register() }
                    onStart()
                } label: {
                    Text(L("Başla", "Get started")).font(Theme.bodyStrong).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 420)
        .background(Theme.surface)
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
