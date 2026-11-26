// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import SwiftUI

/// A fresh capture: the image, and what was already done with it (copied, saved to a file).
struct ShotCapture {
    let image: CGImage
    let scale: CGFloat
    /// Where it was saved, for "file" captures.
    var file: URL?
    var copied = false
}

// MARK: - The thumbnail after a capture

/// The small preview in the screen's lower-left corner after a capture, like CleanShot's: copy, save, mark up,
/// pin, drag it out, or let it slide away. A click opens the editor.
@MainActor
enum ShotOverlay {
    private static var panels: [ShotThumbnailPanel] = []

    static func show(_ capture: ShotCapture) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let width: CGFloat = 228
        let aspect = CGFloat(capture.image.height) / max(CGFloat(capture.image.width), 1)
        let height = min(max(width * aspect, 96), 228)
        let panel = ShotThumbnailPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        let view = ShotThumbnailView(capture: capture) { [weak panel] action in
            guard let panel else { return }
            handle(action, capture: capture, panel: panel)
        } hover: { [weak panel] inside in
            panel?.hovering = inside
            if !inside { panel?.scheduleDismiss() }
        }
        let host = NSHostingView(rootView: view)
        host.wantsLayer = true
        host.layer?.cornerRadius = 12
        host.layer?.masksToBounds = true
        panel.contentView = host
        // Newer ones stack above older ones.
        let visible = screen.visibleFrame
        let y = visible.minY + 16 + panels.reduce(0) { $0 + $1.frame.height + 12 }
        let end = NSRect(x: visible.minX + 16, y: y, width: width, height: height)
        panel.setFrame(end.offsetBy(dx: -(width + 40), dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = 1
        }
        panel.onDismiss = { dismiss(panel) }
        panels.append(panel)
        if panels.count > 4 { dismiss(panels[0]) }
        panel.scheduleDismiss()
    }

    private static func handle(_ action: ShotThumbnailAction, capture: ShotCapture, panel: ShotThumbnailPanel) {
        switch action {
        case .copy:
            if ShotExport.copy(capture.image, scale: capture.scale) { Monitor.panelActions.flash(L("Kopyalandı", "Copied")) }
        case .save:
            if let file = capture.file {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            } else {
                let url = Capture.newFile().deletingPathExtension().appendingPathExtension(ShotExport.fileType == "jpeg" ? "jpg" : ShotExport.fileType)
                if let data = ShotRenderer.encode(capture.image, type: url.pathExtension, scale: capture.scale), (try? data.write(to: url)) != nil {
                    Monitor.panelActions.flash(L("Kaydedildi: \(url.deletingLastPathComponent().lastPathComponent)", "Saved to \(url.deletingLastPathComponent().lastPathComponent)"))
                }
            }
        case .edit:
            let doc = ShotDocument(image: capture.image, scale: capture.scale, source: capture.file)
            doc.replacesSource = capture.file != nil
            ShotEditor.show(doc)
        case .pin:
            ShotPin.show(NSImage(cgImage: capture.image, size: NSSize(width: CGFloat(capture.image.width) / capture.scale,
                                                                       height: CGFloat(capture.image.height) / capture.scale)), doc: nil)
        case .close, .dragged:
            break
        }
        dismiss(panel)
    }

    static func dismiss(_ panel: ShotThumbnailPanel) {
        guard let index = panels.firstIndex(where: { $0 === panel }) else { return }
        panels.remove(at: index)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
            panel.animator().setFrame(panel.frame.offsetBy(dx: -(panel.frame.width + 40), dy: 0), display: true)
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panel.contentView = nil
            }
        }
        // The ones above slide down into the gap.
        var y = (panel.screen ?? NSScreen.main)?.visibleFrame.minY ?? 0
        y += 16
        for other in panels {
            NSAnimationContext.runAnimationGroup { _ in
                other.animator().setFrameOrigin(NSPoint(x: other.frame.minX, y: y))
            }
            y += other.frame.height + 12
        }
    }
}

final class ShotThumbnailPanel: NSPanel {
    var hovering = false
    var onDismiss: () -> Void = {}
    private var timer: Timer?

    override var canBecomeKey: Bool { false }

    /// Slides away after a while unless the pointer is on it.
    func scheduleDismiss() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 7, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.hovering else { return }
                self.onDismiss()
            }
        }
    }
}

enum ShotThumbnailAction { case copy, save, edit, pin, close, dragged }

struct ShotThumbnailView: View {
    let capture: ShotCapture
    let act: (ShotThumbnailAction) -> Void
    let hover: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
            Image(decorative: capture.image, scale: capture.scale)
                .resizable()
                .aspectRatio(contentMode: .fit)
            ShotThumbnailDrag(capture: capture) { act(.edit) } dragged: { act(.dragged) }
            if hovering {
                Color.black.opacity(0.42).allowsHitTesting(false)
                VStack(spacing: 6) {
                    pill(L("Kopyala", "Copy")) { act(.copy) }
                    pill(capture.file == nil ? L("Kaydet", "Save") : L("Finder'da göster", "Show in Finder")) { act(.save) }
                }
                VStack {
                    HStack {
                        corner("xmark", L("Kapat", "Close")) { act(.close) }
                        Spacer()
                        corner("pencil.tip.crop.circle", L("Düzenle", "Mark up")) { act(.edit) }
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        corner("pin", L("Ekrana sabitle", "Pin to screen")) { act(.pin) }
                    }
                }
                .padding(6)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hovering = inside }
            hover(inside)
        }
        .environment(\.colorScheme, .dark)
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.smallStrong).foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.m).frame(minWidth: 96).frame(height: 24)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    private func corner(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The thumbnail's image as a drag source: drag it out as a file, click it to mark it up.
private struct ShotThumbnailDrag: NSViewRepresentable {
    let capture: ShotCapture
    let click: () -> Void
    let dragged: () -> Void

    func makeNSView(context: Context) -> ShotDragView {
        let view = ShotDragView()
        view.symbol = nil
        view.toolTip = L("Tıkla: düzenle · Sürükle: dosya olarak bırak", "Click to mark up · Drag to drop as a file")
        let capture = capture
        view.provide = { capture.file ?? ShotExport.temporaryFile(capture.image, scale: capture.scale) }
        view.onClick = click
        view.onDragEnd = dragged
        return view
    }

    func updateNSView(_ nsView: ShotDragView, context: Context) {}
}

// MARK: - Pinned to the screen

/// A screenshot floating over every app and Space: drag to move, scroll or pinch to resize, double-click or ⎋ to
/// close, right-click for copy, opacity and the editor.
@MainActor
enum ShotPin {
    private static var pins: [NSPanel] = []

    static func show(_ image: NSImage, doc: ShotDocument?) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        var size = image.size
        let limit = CGSize(width: screen.visibleFrame.width * 0.5, height: screen.visibleFrame.height * 0.5)
        let fit = min(1, limit.width / max(size.width, 1), limit.height / max(size.height, 1))
        size = CGSize(width: (size.width * fit).rounded(), height: (size.height * fit).rounded())
        let mouse = NSEvent.mouseLocation
        var frame = NSRect(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2, width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, screen.visibleFrame.minX), screen.visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, screen.visibleFrame.minY), screen.visibleFrame.maxY - frame.height)
        let panel = ShotPinPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.aspectRatio = image.size
        let view = ShotPinView(image: image)
        view.close = { [weak panel] in if let panel { close(panel) } }
        view.edit = {
            if let doc { ShotEditor.show(doc) } else if let fresh = ShotDocument(nsImage: image) { ShotEditor.show(fresh) }
        }
        panel.contentView = view
        panel.orderFrontRegardless()
        panel.makeKey()
        pins.append(panel)
    }

    static func close(_ panel: NSPanel) {
        panel.orderOut(nil)
        panel.contentView = nil
        pins.removeAll { $0 === panel }
    }
}

final class ShotPinPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class ShotPinView: NSView {
    let image: NSImage
    var close: () -> Void = {}
    var edit: () -> Void = {}
    private var hovering = false

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    private var closeBox: NSRect { NSRect(x: 8, y: bounds.height - 30, width: 22, height: 22) }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
        guard hovering else { return }
        NSColor(white: 0, alpha: 0.55).setFill()
        NSBezierPath(ovalIn: closeBox).fill()
        let cross = NSBezierPath()
        let box = closeBox.insetBy(dx: 7.5, dy: 7.5)
        cross.move(to: NSPoint(x: box.minX, y: box.minY)); cross.line(to: NSPoint(x: box.maxX, y: box.maxY))
        cross.move(to: NSPoint(x: box.minX, y: box.maxY)); cross.line(to: NSPoint(x: box.maxX, y: box.minY))
        cross.lineWidth = 1.6
        cross.lineCapStyle = .round
        NSColor.white.setStroke()
        cross.stroke()
        NSColor(white: 1, alpha: 0.25).setStroke()
        let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        edge.lineWidth = 1
        edge.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if hovering && closeBox.insetBy(dx: -4, dy: -4).contains(p) { close(); return }
        if event.clickCount == 2 { close(); return }
        window?.makeKey()
        window?.performDrag(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }
    }

    @objc func copy(_ sender: Any?) {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ShotExport.copy(cg, scale: CGFloat(cg.width) / max(image.size.width, 1))
            Monitor.panelActions.flash(L("Kopyalandı", "Copied"))
        }
    }

    override func scrollWheel(with event: NSEvent) { resize(by: 1 + event.scrollingDeltaY * 0.01) }
    override func magnify(with event: NSEvent) { resize(by: 1 + event.magnification) }

    /// Grows or shrinks around the window's centre, keeping the image's shape.
    private func resize(by factor: CGFloat) {
        guard let window, factor.isFinite, factor > 0 else { return }
        let old = window.frame
        let width = min(max(old.width * factor, 80), image.size.width * 4)
        let height = width * image.size.height / max(image.size.width, 1)
        window.setFrame(NSRect(x: old.midX - width / 2, y: old.midY - height / 2, width: width, height: height), display: true)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(item(L("Kopyala", "Copy"), #selector(copy(_:))))
        menu.addItem(item(L("Düzenle", "Mark up"), #selector(editNow)))
        menu.addItem(item(L("Gerçek boyut", "Actual size"), #selector(actualSize)))
        let opacity = NSMenuItem(title: L("Saydamlık", "Opacity"), action: nil, keyEquivalent: "")
        let options = NSMenu()
        for percent in [100, 80, 60, 40] {
            let entry = item("%\(percent)", #selector(setOpacity(_:)))
            entry.tag = percent
            entry.state = Int(((window?.alphaValue ?? 1) * 100).rounded()) == percent ? .on : .off
            options.addItem(entry)
        }
        opacity.submenu = options
        menu.addItem(opacity)
        menu.addItem(.separator())
        menu.addItem(item(L("Kapat", "Close"), #selector(closeNow)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func editNow() { edit(); close() }
    @objc private func closeNow() { close() }
    @objc private func setOpacity(_ sender: NSMenuItem) { window?.alphaValue = CGFloat(sender.tag) / 100 }

    @objc private func actualSize() {
        guard let window else { return }
        let old = window.frame
        window.setFrame(NSRect(x: old.midX - image.size.width / 2, y: old.midY - image.size.height / 2,
                               width: image.size.width, height: image.size.height), display: true)
    }
}
