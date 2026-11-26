// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import SwiftUI

/// Tidies the menu bar: a divider and a small arrow sit left of Nabız. Icons ⌘-dragged left of the divider hide when
/// the arrow folds the bar, and come back when it's clicked again (then fold away on their own after a few seconds).
///
/// Folding stretches the divider so wide that everything to its left is pushed off the screen; nothing is moved or
/// removed, so turning it off puts every icon back where it was.
@MainActor
final class MenuBarHider: NSObject {
    static let shared = MenuBarHider()

    private var arrow: NSStatusItem?
    private var divider: NSStatusItem?
    private(set) var folded = false
    private var foldTimer: Timer?
    /// Long enough to leave no room for what is left of the divider, short enough that the menu bar still lays it out:
    /// since macOS 26 an item longer than about half the screen is dropped (and the icons it should hide stay), so the
    /// classic 10 000 pt divider no longer works. Measured on a 2056 pt screen: 800–1000 pt hides cleanly, 1200 doesn't.
    private var foldedLength: CGFloat {
        let screen = arrow?.button?.window?.screen ?? NSScreen.main
        return max((screen?.frame.width ?? 1440) * 0.45, 500)
    }
    private static let hintedKey = "menuBarHiderHinted"

    /// Puts the items in or takes them out to match Settings. Call after Nabız's own item exists, so these land left of it.
    func update() {
        let on = Prefs.bool(Prefs.menuBarHider)
        if on && arrow == nil { install() } else if !on && arrow != nil { uninstall() }
    }

    func toggle() {
        guard arrow != nil else { return }
        folded ? unfold() : fold()
    }

    // MARK: Items

    private func install() {
        // Made first, so it sits right of the divider: new items go to the left of the ones already there.
        let arrow = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        arrow.autosaveName = "app.nabiz.hider.arrow"
        arrow.button?.target = self
        arrow.button?.action = #selector(arrowClicked)
        arrow.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        arrow.button?.setAccessibilityLabel(L("Gizli menü çubuğu simgeleri", "Hidden menu bar icons"))
        let divider = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        divider.autosaveName = "app.nabiz.hider.divider"
        divider.button?.image = Self.dividerImage
        divider.button?.toolTip = L("Bu çizginin solundaki simgeler gizlenir. Taşımak için ⌘ basılı tutup sürükle.",
                                   "Icons left of this line hide. Hold ⌘ and drag to move them.")
        divider.button?.setAccessibilityLabel(L("Gizleme çizgisi", "Hiding divider"))
        self.arrow = arrow
        self.divider = divider
        if UserDefaults.standard.bool(forKey: Self.hintedKey) {
            // Later launches start tidy; a moment's wait lets the menu bar place the items first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { self.fold() } }
        } else {
            unfold(autoFold: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { self.showHint() } }
        }
        updateArrow()
    }

    private func uninstall() {
        foldTimer?.invalidate()
        divider?.length = NSStatusItem.variableLength
        if let arrow { NSStatusBar.system.removeStatusItem(arrow) }
        if let divider { NSStatusBar.system.removeStatusItem(divider) }
        arrow = nil
        divider = nil
        folded = false
    }

    // MARK: Folding

    private func fold() {
        guard let divider, canFold else { return }
        foldTimer?.invalidate()
        divider.button?.image = nil
        divider.length = foldedLength
        folded = true
        updateArrow()
    }

    private func unfold(autoFold: Bool = true) {
        guard let divider else { return }
        divider.length = NSStatusItem.variableLength
        divider.button?.image = Self.dividerImage
        folded = false
        updateArrow()
        scheduleFold(after: autoFold ? TimeInterval(Prefs.int(Prefs.menuBarHiderDelay)) : 0)
    }

    /// Folds again after the delay in Settings, waiting while the pointer is still in the menu bar.
    private func scheduleFold(after seconds: TimeInterval) {
        foldTimer?.invalidate()
        guard seconds > 0 else { return }
        foldTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated {
                let hider = MenuBarHider.shared
                guard !hider.folded else { return }
                if hider.pointerInMenuBar { hider.scheduleFold(after: 3) } else { hider.fold() }
            }
        }
    }

    /// Only while the divider is left of the arrow: folded the other way round, the arrow itself would vanish.
    private var canFold: Bool {
        guard let dividerX = divider?.button?.window?.frame.minX, let arrowX = arrow?.button?.window?.frame.minX else { return false }
        return dividerX < arrowX
    }

    private var pointerInMenuBar: Bool {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return false }
        return point.y >= screen.frame.maxY - NSStatusBar.system.thickness - 4
    }

    private func updateArrow() {
        let name = folded ? "chevron.compact.left" : "chevron.compact.right"
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        image?.isTemplate = true
        arrow?.button?.image = image
        arrow?.button?.toolTip = folded ? L("Gizli simgeleri göster", "Show hidden icons") : L("Simgeleri gizle", "Hide icons")
    }

    @objc private func arrowClicked() {
        let event = NSApp.currentEvent
        guard event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true else {
            if folded {
                unfold()
            } else if canFold {
                fold()
            } else {
                showHint()
            }
            return
        }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: folded ? L("Gizli simgeleri göster", "Show Hidden Icons") : L("Simgeleri gizle", "Hide Icons"),
                                     keyEquivalent: "") { MenuBarHider.shared.toggle() })
        menu.addItem(ClosureMenuItem(title: L("Nasıl kullanılır?", "How Does It Work?"), keyEquivalent: "") { MenuBarHider.shared.showHint() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: L("Menü çubuğu ayarları…", "Menu Bar Settings…"), keyEquivalent: "") {
            SettingsWindow.show(.menuBar, anchor: "menuBar.hider")
        })
        menu.addItem(ClosureMenuItem(title: L("Gizlemeyi kapat", "Turn Off Hiding"), keyEquivalent: "") {
            UserDefaults.standard.set(false, forKey: Prefs.menuBarHider)
        })
        arrow?.menu = menu
        arrow?.button?.performClick(nil)
        arrow?.menu = nil
    }

    // MARK: The hint

    private var popover: NSPopover?

    /// A short note under the divider: what to drag where.
    func showHint() {
        guard let button = divider?.button, button.window != nil else { return }
        if folded { unfold(autoFold: false) }
        UserDefaults.standard.set(true, forKey: Self.hintedKey)
        popover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: HiderHint())
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
    }

    /// A one-point line, the height of a menu bar icon, drawn in the bar's own text colour at half strength.
    private static let dividerImage: NSImage = {
        let image = NSImage(size: NSSize(width: 8, height: 16), flipped: false) { rect in
            NSColor.black.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.midX - 0.5, y: 1, width: 1, height: rect.height - 2), xRadius: 0.5, yRadius: 0.5).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

private struct HiderHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(L("Menü çubuğunu sadeleştir", "Tidy the menu bar")).font(Theme.body.weight(.semibold))
            Text(L("⌘ tuşunu basılı tut ve gizlemek istediğin simgeleri bu çizginin soluna sürükle. Oktaki tık onları gizler ve geri getirir.",
                   "Hold ⌘ and drag the icons you want to hide to the left of this line. Clicking the arrow hides them and brings them back."))
                .font(Theme.small).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.l)
        .frame(width: 280, alignment: .leading)
    }
}
