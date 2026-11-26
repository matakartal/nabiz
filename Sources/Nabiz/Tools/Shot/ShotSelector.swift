import AppKit
import ScreenCaptureKit

/// Nabız's own area picker, like CleanShot's and Shottr's: the screen is frozen first, then you pick on the still
/// picture with a crosshair, a magnifier showing the pixels and colour under the pointer, the size as you drag, and
/// the window under the pointer lit up (a click takes that window). Esc cancels, ↩ takes the whole screen,
/// arrows nudge the pointer by a point, Space while dragging moves the selection, ⇧ makes a square, ⌥ draws from
/// the centre, C copies the colour under the pointer.
@MainActor
final class ShotSelector {
    struct Result {
        let image: CGImage
        let scale: CGFloat
        /// The picked part, in points, top-left origin, on `screen`.
        let rect: CGRect
        let screen: NSScreen
    }

    /// One screen's frozen picture.
    struct Frozen {
        let screen: NSScreen
        let image: CGImage
        let scale: CGFloat
    }

    private static var current: ShotSelector?

    /// Whether macOS lets Nabız read the screen; without it the system's picker is used instead.
    static var available: Bool { CGPreflightScreenCaptureAccess() }

    /// Freezes every screen and lets the user pick. `nil` when cancelled (or the screen couldn't be read).
    static func begin(windowMode: Bool = false, denied: @escaping () -> Void = {}, done: @escaping (Result?) -> Void) {
        // Pressing the shortcut again while picking cancels, like macOS's own.
        if let current { current.cancel(); return }
        let previous = NSWorkspace.shared.frontmostApplication
        Task {
            let frozen = await freeze()
            ShotLog.write("froze \(frozen.count) of \(NSScreen.screens.count) screens")
            guard !frozen.isEmpty else { denied(); done(nil); return }
            let selector = ShotSelector(frozen: frozen, windowMode: windowMode, previous: previous, done: done)
            current = selector
            selector.show()
        }
    }

    /// Every screen at full resolution, through ScreenCaptureKit.
    static func freeze() async -> [Frozen] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            ShotLog.write("shareable content failed: \(error)")
            return []
        }
        var result: [Frozen] = []
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == number }) else { continue }
            let scale = screen.backingScaleFactor
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * scale)
            config.height = Int(screen.frame.height * scale)
            config.showsCursor = false
            config.captureResolution = .best
            if let space = screen.colorSpace?.cgColorSpace?.name { config.colorSpaceName = space }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            do {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                result.append(Frozen(screen: screen, image: image, scale: scale))
            } catch {
                ShotLog.write("capture failed on display \(number): \(error)")
            }
        }
        return result
    }

    // MARK: State

    let frozen: [Frozen]
    let windowMode: Bool
    private let previous: NSRunningApplication?
    private let done: (Result?) -> Void
    private var windows: [ShotSelectorWindow] = []
    /// Other apps' windows, front to back, in global top-left coordinates.
    private let windowRects: [CGRect]

    /// The pointer, in global (bottom-left) screen coordinates.
    var mouse = NSEvent.mouseLocation
    /// The drag, in the active screen's view coordinates (top-left).
    var dragStart: CGPoint?
    var dragEnd: CGPoint?
    var dragScreen: NSScreen?
    var moving = false
    private var finished = false

    private init(frozen: [Frozen], windowMode: Bool, previous: NSRunningApplication?, windows: [CGRect]? = nil,
                 done: @escaping (Result?) -> Void) {
        self.frozen = frozen
        self.windowMode = windowMode
        self.previous = previous
        self.done = done
        windowRects = windows ?? Self.windowList()
    }

    /// For `--snapshot … --selector image.png [--drag]`: the picker drawn over a picture, pointer in the middle.
    static func preview(_ image: CGImage, drag: Bool) -> NSImage? {
        guard let screen = NSScreen.main else { return nil }
        let size = screen.frame.size
        let frozen = Frozen(screen: screen, image: image, scale: CGFloat(image.width) / size.width)
        let window = CGRect(x: size.width * 0.55, y: size.height * 0.2, width: size.width * 0.35, height: size.height * 0.45)
        let selector = ShotSelector(frozen: [frozen], windowMode: false, previous: nil, windows: drag ? [] : [
            window.offsetBy(dx: Self.cgFrame(screen).minX, dy: Self.cgFrame(screen).minY)]) { _ in }
        selector.mouse = NSPoint(x: screen.frame.minX + size.width * 0.62, y: screen.frame.maxY - size.height * 0.4)
        if drag {
            selector.dragScreen = screen
            selector.dragStart = CGPoint(x: size.width * 0.2, y: size.height * 0.2)
            selector.dragEnd = CGPoint(x: size.width * 0.62, y: size.height * 0.4)
        }
        let overlay = ShotSelectorOverlay(shot: frozen, selector: selector)
        overlay.frame = CGRect(origin: .zero, size: size)
        return NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: rect)
            ctx.restoreGState()
            withExtendedLifetime(selector) { overlay.draw(rect) }
            return true
        }
    }

    private static func windowList() -> [CGRect] {
        let own = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != own,
                  ((info[kCGWindowAlpha as String] as? Double) ?? 1) > 0.01,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 40, rect.height > 30 else { return nil }
            return rect
        }
    }

    private func show() {
        for shot in frozen {
            let window = ShotSelectorWindow(shot: shot, selector: self)
            windows.append(window)
            window.orderFrontRegardless()
        }
        let underMouse = windows.first { $0.frame.contains(NSEvent.mouseLocation) } ?? windows.first
        underMouse?.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.set()
        refresh()
    }

    func refresh() {
        for window in windows { window.overlay.needsDisplay = true }
    }

    // MARK: Geometry

    /// Global top-left (CoreGraphics) coordinates of a screen's frame.
    static func cgFrame(_ screen: NSScreen) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return CGRect(x: screen.frame.minX, y: mainHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
    }

    /// The pointer in a screen's view coordinates (top-left), or nil when it is on another screen.
    func mouse(in screen: NSScreen) -> CGPoint? {
        guard screen.frame.insetBy(dx: -0.5, dy: -0.5).contains(mouse) else { return nil }
        return CGPoint(x: mouse.x - screen.frame.minX, y: screen.frame.maxY - mouse.y)
    }

    /// The front window under the pointer, in that screen's view coordinates.
    func hoveredWindow(in screen: NSScreen) -> CGRect? {
        guard dragStart == nil, let local = mouse(in: screen) else { return nil }
        let frame = Self.cgFrame(screen)
        let global = CGPoint(x: local.x + frame.minX, y: local.y + frame.minY)
        guard let rect = windowRects.first(where: { $0.contains(global) }) else { return nil }
        return rect.offsetBy(dx: -frame.minX, dy: -frame.minY).intersection(CGRect(origin: .zero, size: screen.frame.size))
    }

    /// The selection being dragged on this screen.
    func selection(in screen: NSScreen) -> CGRect? {
        guard dragScreen == screen, let start = dragStart, let end = dragEnd else { return nil }
        return CGRect(from: start, to: end)
    }

    // MARK: Ending

    func finish(_ rect: CGRect, on screen: NSScreen) {
        guard !finished, let shot = frozen.first(where: { $0.screen == screen }) else { cancel(); return }
        let pixels = CGRect(x: rect.minX * shot.scale, y: rect.minY * shot.scale, width: rect.width * shot.scale, height: rect.height * shot.scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: shot.image.width, height: shot.image.height))
        guard pixels.width >= 1, pixels.height >= 1, let cropped = shot.image.cropping(to: pixels) else { cancel(); return }
        close()
        ShotLog.write("picked \(cropped.width)×\(cropped.height)")
        done(Result(image: cropped, scale: shot.scale, rect: rect, screen: screen))
    }

    func cancel() {
        guard !finished else { return }
        ShotLog.write("picker cancelled")
        close()
        done(nil)
    }

    private func close() {
        finished = true
        for window in windows { window.orderOut(nil); window.contentView = nil }
        windows = []
        Self.current = nil
        NSCursor.arrow.set()
        if NSApp.isActive, let previous, previous != NSRunningApplication.current { previous.activate() }
    }

    /// The colour of the pixel under the pointer, as "#RRGGBB".
    func colourHex() -> String? {
        guard let shot = frozen.first(where: { mouse(in: $0.screen) != nil }), let p = mouse(in: shot.screen) else { return nil }
        let x = Int(p.x * shot.scale), y = Int(p.y * shot.scale)
        guard let pixel = shot.image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var data = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return String(format: "#%02X%02X%02X", data[0], data[1], data[2])
    }
}

// MARK: - The window over each screen

/// A non-activating panel: it takes the keyboard and the first click at once, without waiting for macOS to bring
/// Nabız (a menu bar app) to the front, which it may refuse to do straight away.
final class ShotSelectorWindow: NSPanel {
    let overlay: ShotSelectorOverlay

    init(shot: ShotSelector.Frozen, selector: ShotSelector) {
        overlay = ShotSelectorOverlay(shot: shot, selector: selector)
        super.init(contentRect: shot.screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        setFrame(shot.screen.frame, display: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // The frozen picture sits in a layer (drawn by the GPU once); only the marks on top redraw as the pointer moves.
        let root = NSView(frame: NSRect(origin: .zero, size: shot.screen.frame.size))
        root.wantsLayer = true
        root.layer?.contents = shot.image
        root.layer?.contentsGravity = .resize
        overlay.frame = root.bounds
        overlay.autoresizingMask = [.width, .height]
        root.addSubview(overlay)
        contentView = root
        makeFirstResponder(overlay)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ShotSelectorOverlay: NSView {
    let shot: ShotSelector.Frozen
    unowned let selector: ShotSelector
    private var spaceOrigin: CGPoint?

    init(shot: ShotSelector.Frozen, selector: ShotSelector) {
        self.shot = shot
        self.selector = selector
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    private var screen: NSScreen { shot.screen }
    private var accent: NSColor { NSColor(Theme.accent) }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let selection = selector.selection(in: screen)
        let window = selector.hoveredWindow(in: screen)
        let mouse = selector.mouse(in: screen)
        // Dim everything but the selection, or the window that a click would take.
        let clear = selection ?? window
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let clear { dim.addRect(clear) }
        ctx.addPath(dim)
        ctx.setFillColor(CGColor(gray: 0, alpha: selection != nil ? 0.42 : (clear != nil ? 0.32 : 0.18)))
        ctx.fillPath(using: .evenOdd)

        if let selection {
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
            ctx.setLineWidth(1)
            ctx.stroke(selection.insetBy(dx: -0.5, dy: -0.5))
            drawSizeBadge(selection)
        } else if let window {
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(3)
            ctx.stroke(window.insetBy(dx: 1.5, dy: 1.5))
            drawSizeBadge(window)
        }
        guard let mouse else { return }
        if selection == nil && !selector.windowMode { drawCrosshair(ctx, at: mouse) }
        drawLoupe(ctx, at: mouse)
        if selection == nil && window == nil && !selector.windowMode { drawHint() }
    }

    /// Full-length guide lines through the pointer, light with a dark edge so they show on anything.
    private func drawCrosshair(_ ctx: CGContext, at p: CGPoint) {
        let x = p.x.rounded() + 0.5, y = p.y.rounded() + 0.5
        ctx.saveGState()
        ctx.setLineWidth(1)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.35))
        ctx.strokeLineSegments(between: [CGPoint(x: x + 1, y: 0), CGPoint(x: x + 1, y: bounds.height),
                                         CGPoint(x: 0, y: y + 1), CGPoint(x: bounds.width, y: y + 1)])
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.7))
        ctx.strokeLineSegments(between: [CGPoint(x: x, y: 0), CGPoint(x: x, y: bounds.height),
                                         CGPoint(x: 0, y: y), CGPoint(x: bounds.width, y: y)])
        ctx.restoreGState()
    }

    /// The magnifier: 17 × 17 screen pixels blown up with a grid, the centre pixel framed, its colour and position below.
    private func drawLoupe(_ ctx: CGContext, at p: CGPoint) {
        let cells = 17, cell: CGFloat = 9
        let side = CGFloat(cells) * cell
        let px = Int(p.x * shot.scale), py = Int(p.y * shot.scale)
        let source = CGRect(x: px - cells / 2, y: py - cells / 2, width: cells, height: cells)
        let infoHeight: CGFloat = 36
        // Below-right of the pointer, flipped to the other side near the screen's edges.
        var origin = CGPoint(x: p.x + 26, y: p.y + 26)
        if origin.x + side > bounds.width - 8 { origin.x = p.x - 26 - side }
        if origin.y + side + infoHeight > bounds.height - 8 { origin.y = p.y - 26 - side - infoHeight }
        let box = CGRect(origin: origin, size: CGSize(width: side, height: side))
        let card = CGRect(x: box.minX, y: box.minY, width: side, height: side + infoHeight)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 20, color: CGColor(gray: 0, alpha: 0.45))
        ctx.addPath(CGPath(roundedRect: card, cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 0.92))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        let top = CGMutablePath()
        top.addRoundedRect(in: CGRect(x: box.minX, y: box.minY, width: side, height: side + 12), cornerWidth: 12, cornerHeight: 12)
        ctx.addPath(top)
        ctx.clip()
        ctx.clip(to: box)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(box)
        let clamped = source.intersection(CGRect(x: 0, y: 0, width: shot.image.width, height: shot.image.height))
        if !clamped.isNull, let crop = shot.image.cropping(to: clamped) {
            let target = CGRect(x: box.minX + (clamped.minX - source.minX) * cell, y: box.minY + (clamped.minY - source.minY) * cell,
                                width: clamped.width * cell, height: clamped.height * cell)
            ctx.interpolationQuality = .none
            ctx.saveGState()
            ctx.translateBy(x: 0, y: target.maxY + target.minY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(crop, in: target)
            ctx.restoreGState()
        }
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.14))
        ctx.setLineWidth(0.5)
        for i in 1..<cells {
            let o = CGFloat(i) * cell
            ctx.strokeLineSegments(between: [CGPoint(x: box.minX + o, y: box.minY), CGPoint(x: box.minX + o, y: box.maxY),
                                             CGPoint(x: box.minX, y: box.minY + o), CGPoint(x: box.maxX, y: box.minY + o)])
        }
        let centre = CGRect(x: box.minX + CGFloat(cells / 2) * cell, y: box.minY + CGFloat(cells / 2) * cell, width: cell, height: cell)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.8))
        ctx.setLineWidth(2)
        ctx.stroke(centre.insetBy(dx: -1, dy: -1))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(1)
        ctx.stroke(centre.insetBy(dx: -0.5, dy: -0.5))
        ctx.restoreGState()

        let hex = selector.colourHex() ?? ""
        let swatch = CGRect(x: card.minX + 10, y: box.maxY + 10, width: 14, height: 14)
        if let colour = NSColor(hexString: hex) {
            colour.setFill()
            NSBezierPath(roundedRect: swatch, xRadius: 4, yRadius: 4).fill()
            NSColor(white: 1, alpha: 0.3).setStroke()
            NSBezierPath(roundedRect: swatch.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()
        }
        let mono = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        NSAttributedString(string: hex, attributes: [.font: mono, .foregroundColor: NSColor.white])
            .draw(at: CGPoint(x: swatch.maxX + 6, y: swatch.minY))
        let position = NSAttributedString(string: "\(Int(p.x)), \(Int(p.y))",
                                          attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                                                       .foregroundColor: NSColor(white: 1, alpha: 0.55)])
        position.draw(at: CGPoint(x: card.maxX - position.size().width - 10, y: swatch.minY + 1))
    }

    /// "1280 × 720" just under the selection (or inside it at the screen's bottom edge).
    private func drawSizeBadge(_ rect: CGRect) {
        let text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
        let string = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                                                                   .foregroundColor: NSColor.white])
        let size = string.size()
        var box = CGRect(x: rect.minX, y: rect.maxY + 8, width: size.width + 16, height: size.height + 8)
        if box.maxY > bounds.height - 4 { box.origin.y = rect.maxY - box.height - 8; box.origin.x = rect.minX + 8 }
        box.origin.x = min(max(box.minX, 4), bounds.width - box.width - 4)
        NSColor(white: 0.08, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        string.draw(at: CGPoint(x: box.minX + 8, y: box.minY + 4))
    }

    /// A one-line reminder of the keys, at the top of the screen with the pointer.
    private func drawHint() {
        let text = L("Sürükle: alan · Tıkla: pencere · ↩ tüm ekran · Boşluk: taşı · ⇧ kare · C renk · ⎋ vazgeç",
                     "Drag: area · Click: window · ↩ whole screen · Space: move · ⇧ square · C colour · ⎋ cancel")
        let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                                                   .foregroundColor: NSColor(white: 1, alpha: 0.9)])
        let size = string.size()
        let top = (screen.frame.maxY - screen.visibleFrame.maxY) + 14
        let box = CGRect(x: (bounds.width - size.width) / 2 - 14, y: top, width: size.width + 28, height: size.height + 12)
        NSColor(white: 0.08, alpha: 0.8).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        string.draw(at: CGPoint(x: box.minX + 14, y: box.minY + 6))
    }

    // MARK: Mouse

    private func local(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    override func mouseMoved(with event: NSEvent) {
        selector.mouse = NSEvent.mouseLocation
        selector.refresh()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        selector.mouse = NSEvent.mouseLocation
        let p = local(event)
        selector.dragScreen = screen
        selector.dragStart = p
        selector.dragEnd = p
        selector.refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        selector.mouse = NSEvent.mouseLocation
        guard selector.dragScreen == screen, var start = selector.dragStart, let end = selector.dragEnd else { return }
        var p = local(event)
        if selector.moving {
            // Space held: the whole selection follows the pointer.
            let dx = p.x - end.x, dy = p.y - end.y
            start = CGPoint(x: start.x + dx, y: start.y + dy)
            selector.dragStart = start
            selector.dragEnd = p
        } else {
            if event.modifierFlags.contains(.shift) {
                let side = max(abs(p.x - start.x), abs(p.y - start.y))
                p = CGPoint(x: start.x + (p.x < start.x ? -side : side), y: start.y + (p.y < start.y ? -side : side))
            }
            selector.dragEnd = p
            if event.modifierFlags.contains(.option), let anchor = spaceOrigin ?? selector.dragStart {
                spaceOrigin = anchor
                selector.dragStart = CGPoint(x: anchor.x * 2 - p.x, y: anchor.y * 2 - p.y)
                selector.dragEnd = p
            }
        }
        selector.refresh()
    }

    override func mouseUp(with event: NSEvent) {
        defer { spaceOrigin = nil }
        guard selector.dragScreen == screen, let start = selector.dragStart, let end = selector.dragEnd else { return }
        let rect = CGRect(from: start, to: end).intersection(bounds)
        if rect.width < 4 && rect.height < 4 {
            // A click: the window under the pointer, else the whole screen.
            selector.dragStart = nil
            selector.dragEnd = nil
            selector.finish(selector.hoveredWindow(in: screen) ?? bounds, on: screen)
        } else {
            selector.finish(rect, on: screen)
        }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53:
            selector.cancel()
        case 36, 76:
            let target = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? screen
            selector.finish(CGRect(origin: .zero, size: target.frame.size), on: target)
        case 49:
            selector.moving = true
        case 123, 124, 125, 126:
            // Nudge the pointer for pixel-exact edges.
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            var p = NSEvent.mouseLocation
            switch Int(event.keyCode) {
            case 123: p.x -= step
            case 124: p.x += step
            case 125: p.y -= step
            default: p.y += step
            }
            let main = NSScreen.screens.first?.frame.height ?? 0
            CGWarpMouseCursorPosition(CGPoint(x: p.x, y: main - p.y))
            selector.mouse = p
            if selector.dragStart != nil, let screenLocal = selector.mouse(in: screen) { selector.dragEnd = screenLocal }
            selector.refresh()
        default:
            if event.charactersIgnoringModifiers?.lowercased() == "c", let hex = selector.colourHex() {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hex, forType: .string)
                selector.cancel()
                Monitor.panelActions.flash(L("\(hex) kopyalandı", "\(hex) copied"))
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { selector.moving = false }
    }
}

extension NSColor {
    /// "#RRGGBB" in sRGB.
    convenience init?(hexString: String) {
        let digits = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

/// A short trail in ~/Library/Logs/Nabiz/screenshots.log, for when a capture doesn't start.
enum ShotLog {
    nonisolated static func write(_ line: String) {
        let folder = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Nabiz", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("screenshots.log")
        let entry = "\(Date().formatted(.iso8601)) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try? handle.close()
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }
}
