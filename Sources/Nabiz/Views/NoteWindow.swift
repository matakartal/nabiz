import AppKit
import SwiftUI

/// A small note that floats over every app and Space: for a phone number, a todo, a command to paste later.
/// It is saved as you type and stays until you clear it.
@MainActor
enum NoteWindow {
    private static var panel: NSPanel?

    static var isVisible: Bool { panel?.isVisible == true }

    static func toggle() {
        if isVisible { panel?.orderOut(nil) } else { show() }
    }

    static func show() {
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 260),
                                styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                                backing: .buffered, defer: false)
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.minSize = NSSize(width: 240, height: 160)
            panel.contentViewController = NSHostingController(rootView: NoteView())
            panel.setFrameAutosaveName("NabizNote")
            if !panel.setFrameUsingName("NabizNote"), let screen = NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: screen.maxX - 340, y: screen.maxY - 280))
            }
            self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
    }
}

private struct NoteView: View {
    @AppStorage(Prefs.noteText) private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text)
                .font(Theme.body)
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .focused($focused)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.top, Theme.Spacing.xl)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: Theme.Spacing.l) {
                Text(L("\(text.count) karakter", "\(text.count) characters")).foregroundStyle(Theme.textMuted)
                Spacer()
                Button(L("Kopyala", "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .disabled(text.isEmpty)
                Button(L("Temizle", "Clear"), role: .destructive) { text = "" }
                    .disabled(text.isEmpty)
            }
            .buttonStyle(TextButtonStyle(font: Theme.small))
            .font(Theme.small)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: Theme.launcherFooter)
        }
        .frame(minWidth: 240, minHeight: 160)
        .background(MenuMaterial().ignoresSafeArea())
        .appearanceRoot(opaqueFill: Theme.surface)
        .onAppear { focused = true }
    }
}
