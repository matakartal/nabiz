import AppKit

/// What to record, picked on the live screen while the bar is open, like macOS's ⌘⇧5: the screen under the pointer
/// lights up (click it), the window under the pointer lights up (click it), or an area stays on screen to move and
/// resize before pressing Record. It remembers the last area.
@MainActor
enum RecPicker {
    private static var panels: [RecPickerPanel] = []
    static var mode: RecControl.Target = .area
    /// The area, in global (bottom-left) coordinates.
    static var area: NSRect = savedArea
    /// Other apps' windows, front to back: id and frame in global (bottom-left) coordinates.
    private(set) static var windows: [(id: CGWindowID, frame: NSRect)] = []
    static var hoveredScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
    }

    static func show(_ target: RecControl.Target) {
        mode = target
        if target == .window { windows = windowList() }
        if panels.isEmpty {
            panels = NSScreen.screens.map { RecPickerPanel(screen: $0) }
            for panel in panels {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                (panel.contentView as? RecPickerView)?.update(animated: false)
            }
            panels.first { $0.screen == hoveredScreen }?.makeKey()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panels.forEach { $0.animator().alphaValue = 1 }
            }
        }
        refresh()
    }

    static func close() {
        let closing = panels
        panels = []
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            closing.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated { closing.forEach { $0.orderOut(nil) } }
        }
    }

    /// Redraws; `animated` glides the dimming and the outline to their new place (hover, mode change).
    static func refresh(animated: Bool = true) {
        panels.forEach { ($0.contentView as? RecPickerView)?.update(animated: animated) }
    }

    /// The window under a global point.
    static func window(at point: NSPoint) -> (id: CGWindowID, frame: NSRect)? {
        windows.first { $0.frame.contains(point) }
    }

    /// The area on the screen holding most of it, in that screen's points (top-left origin).
    static func areaOnScreen() -> (NSScreen, CGRect)? {
        guard let screen = NSScreen.screens.max(by: { $0.frame.intersection(area).width * $0.frame.intersection(area).height
                                                    < $1.frame.intersection(area).width * $1.frame.intersection(area).height }) else { return nil }
        let part = area.intersection(screen.frame)
        guard part.width > 16, part.height > 16 else { return nil }
        UserDefaults.standard.set(NSStringFromRect(area), forKey: "rec.area")
        return (screen, CGRect(x: part.minX - screen.frame.minX, y: screen.frame.maxY - part.maxY, width: part.width, height: part.height))
    }

    private static var savedArea: NSRect {
        let saved = NSRectFromString(UserDefaults.standard.string(forKey: "rec.area") ?? "")
        if saved.width > 40, saved.height > 40, NSScreen.screens.contains(where: { $0.frame.intersects(saved) }) { return saved }
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: screen.midX - screen.width * 0.3, y: screen.midY - screen.height * 0.3, width: screen.width * 0.6, height: screen.height * 0.6)
    }

    private static func windowList() -> [(id: CGWindowID, frame: NSRect)] {
        let own = ProcessInfo.processInfo.processIdentifier
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != own,
                  ((info[kCGWindowAlpha as String] as? Double) ?? 1) > 0.01,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 60, rect.height > 40 else { return nil }
            return (CGWindowID(number), NSRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height))
        }
    }
}

/// One screen's see-through layer: dims what won't be recorded and takes the clicks.
final class RecPickerPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        // Under the bar (status bar level), over everything else.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        // Said out loud, so the see-through parts (the lit window, the area) take clicks too instead of passing
        // them to the app underneath.
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = RecPickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    override var canBecomeKey: Bool { true }
}

final class RecPickerView: NSView {
    private enum Drag { case none, move(NSRect, NSPoint), resize(Int, NSRect), draw(NSPoint) }
    private var drag = Drag.none
    /// The shade over what won't be recorded (with a hole for what will) and the outline around it, as layers so
    /// they can glide from one window to the next instead of jumping.
    private let shade = CAShapeLayer()
    private let outline = CAShapeLayer()
    private var lastMode: RecControl.Target?
    private var lastHole: NSRect?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // An all-but-invisible coat, so no pixel is fully clear and every click lands here.
        layer?.backgroundColor = CGColor(gray: 0, alpha: 0.003)
        shade.fillRule = .evenOdd
        shade.fillColor = CGColor(gray: 0, alpha: 0.38)
        outline.fillColor = nil
        layer?.addSublayer(shade)
        layer?.addSublayer(outline)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    /// The hole: the screen with the pointer, the window under it, or the area.
    private func hole() -> NSRect? {
        guard let window else { return nil }
        switch RecPicker.mode {
        case .screen: return window.frame.contains(NSEvent.mouseLocation) ? bounds : nil
        case .window: return RecPicker.window(at: NSEvent.mouseLocation).map { local($0.frame) }
        case .area: return local(RecPicker.area)
        }
    }

    func update(animated: Bool) {
        let rect = hole()
        // Nothing moved (the pointer stayed over the same window): leave the running glide alone.
        if rect == lastHole, lastMode == RecPicker.mode, animated { return }
        lastHole = rect
        // Always "screen + one rect" (an empty one in the middle when there's no hole), so the paths animate.
        let gap = rect ?? NSRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
        let shadePath = CGMutablePath()
        shadePath.addRect(bounds)
        shadePath.addRect(gap)
        let mode = RecPicker.mode
        let ring = mode == .area ? gap.insetBy(dx: -0.5, dy: -0.5) : gap.insetBy(dx: 2, dy: 2)
        let outlinePath = CGPath(roundedRect: ring, cornerWidth: mode == .window ? 8 : 0, cornerHeight: mode == .window ? 8 : 0, transform: nil)
        let modeChanged = lastMode != mode
        lastMode = mode
        CATransaction.begin()
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            CATransaction.setAnimationDuration(modeChanged ? 0.24 : 0.16)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1))
            for (layer, path) in [(shade, shadePath as CGPath), (outline, outlinePath)] {
                let move = CABasicAnimation(keyPath: "path")
                move.fromValue = layer.presentation()?.path ?? layer.path
                move.toValue = path
                layer.add(move, forKey: "path")
            }
        } else {
            CATransaction.setDisableActions(true)
        }
        shade.frame = bounds
        outline.frame = bounds
        shade.path = shadePath
        outline.path = outlinePath
        shade.fillColor = CGColor(gray: 0, alpha: mode == .screen ? (rect == nil ? 0.3 : 0) : 0.38)
        outline.strokeColor = mode == .area ? CGColor(gray: 1, alpha: 0.95) : accent.cgColor
        outline.lineWidth = mode == .area ? 1 : (mode == .screen ? 6 : 4)
        outline.lineDashPattern = mode == .area ? [6, 4] : nil
        outline.opacity = rect == nil ? 0 : 1
        CATransaction.commit()
        needsDisplay = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var screen: NSScreen? { window?.screen }
    private var accent: NSColor { NSColor(Theme.accent) }

    /// Global (bottom-left) to this view (bottom-left, not flipped).
    private func local(_ rect: NSRect) -> NSRect {
        guard let frame = window?.frame else { return rect }
        return rect.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }

    private func global(_ point: NSPoint) -> NSPoint {
        guard let frame = window?.frame else { return point }
        return NSPoint(x: point.x + frame.minX, y: point.y + frame.minY)
    }

    // MARK: Drawing

    /// Handles, size and hints, on top of the layers.
    override func draw(_ dirtyRect: NSRect) {
        guard let window else { return }
        switch RecPicker.mode {
        case .screen:
            if window.frame.contains(NSEvent.mouseLocation) {
                hint(L("Bu ekranı kaydetmek için tıkla", "Click to record this screen"), at: NSPoint(x: bounds.midX, y: bounds.midY))
            }
        case .window:
            if let lit = RecPicker.window(at: NSEvent.mouseLocation).map({ local($0.frame) }), bounds.intersects(lit) {
                hint(L("Bu pencereyi kaydetmek için tıkla", "Click to record this window"), at: NSPoint(x: lit.midX, y: lit.midY))
            }
        case .area:
            let box = local(RecPicker.area)
            guard bounds.intersects(box), let ctx = NSGraphicsContext.current?.cgContext else { return }
            for handle in handles(box) {
                let dot = NSRect(x: handle.x - 5, y: handle.y - 5, width: 10, height: 10)
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: CGColor(gray: 0, alpha: 0.4))
                ctx.setFillColor(.white)
                ctx.fillEllipse(in: dot)
                ctx.restoreGState()
                ctx.setStrokeColor(accent.cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: dot.insetBy(dx: 0.75, dy: 0.75))
            }
            let label = "\(Int(RecPicker.area.width)) × \(Int(RecPicker.area.height))"
            badge(label, at: NSPoint(x: box.midX, y: box.minY - 30 > 8 ? box.minY - 24 : box.minY + 16))
        }
    }

    private func handles(_ r: NSRect) -> [NSPoint] {
        [NSPoint(x: r.minX, y: r.maxY), NSPoint(x: r.maxX, y: r.maxY), NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.maxX, y: r.minY),
         NSPoint(x: r.midX, y: r.maxY), NSPoint(x: r.midX, y: r.minY), NSPoint(x: r.minX, y: r.midY), NSPoint(x: r.maxX, y: r.midY)]
    }

    private func hint(_ text: String, at centre: NSPoint) {
        badge(text, at: centre, size: 14)
    }

    private func badge(_ text: String, at centre: NSPoint, size: CGFloat = 12) {
        let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: NSColor.white])
        let measured = string.size()
        let box = NSRect(x: centre.x - measured.width / 2 - 12, y: centre.y - measured.height / 2 - 5, width: measured.width + 24, height: measured.height + 10)
        NSColor(white: 0.08, alpha: 0.8).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        string.draw(at: NSPoint(x: box.minX + 12, y: box.minY + 5))
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) { RecPicker.refresh() }

    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }

    private func updateCursor(_ event: NSEvent) {
        switch RecPicker.mode {
        case .screen, .window: NSCursor.pointingHand.set()
        case .area:
            let p = global(convert(event.locationInWindow, from: nil))
            if handles(RecPicker.area).contains(where: { hypot($0.x - p.x, $0.y - p.y) < 10 }) { NSCursor.crosshair.set() }
            else if RecPicker.area.contains(p) { NSCursor.openHand.set() } else { NSCursor.crosshair.set() }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = global(convert(event.locationInWindow, from: nil))
        switch RecPicker.mode {
        case .screen:
            if let screen { RecControl.record(screen: screen, rect: nil, window: nil) }
        case .window:
            guard let picked = RecPicker.window(at: p),
                  let screen = NSScreen.screens.max(by: { $0.frame.intersection(picked.frame).width < $1.frame.intersection(picked.frame).width })
            else { return }
            let rect = CGRect(x: picked.frame.minX - screen.frame.minX, y: screen.frame.maxY - picked.frame.maxY,
                              width: picked.frame.width, height: picked.frame.height)
            RecControl.record(screen: screen, rect: rect, window: picked.id)
        case .area:
            let area = RecPicker.area
            if let index = handles(area).firstIndex(where: { hypot($0.x - p.x, $0.y - p.y) < 10 }) {
                drag = .resize(index, area)
            } else if area.contains(p) {
                drag = .move(area, p)
                NSCursor.closedHand.set()
            } else {
                drag = .draw(p)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = global(convert(event.locationInWindow, from: nil))
        switch drag {
        case .none:
            return
        case let .move(start, origin):
            RecPicker.area = start.offsetBy(dx: p.x - origin.x, dy: p.y - origin.y)
        case let .draw(origin):
            RecPicker.area = NSRect(x: min(origin.x, p.x), y: min(origin.y, p.y), width: abs(p.x - origin.x), height: abs(p.y - origin.y))
        case let .resize(index, start):
            var minX = start.minX, minY = start.minY, maxX = start.maxX, maxY = start.maxY
            switch index {
            case 0: minX = p.x; maxY = p.y
            case 1: maxX = p.x; maxY = p.y
            case 2: minX = p.x; minY = p.y
            case 3: maxX = p.x; minY = p.y
            case 4: maxY = p.y
            case 5: minY = p.y
            case 6: minX = p.x
            default: maxX = p.x
            }
            RecPicker.area = NSRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
        }
        RecPicker.refresh(animated: false)
    }

    override func mouseUp(with event: NSEvent) {
        if case .draw = drag, RecPicker.area.width < 40 || RecPicker.area.height < 40 {
            // A click outside: keep a sensible box around the click instead of a sliver.
            let p = global(convert(event.locationInWindow, from: nil))
            RecPicker.area = NSRect(x: p.x - 320, y: p.y - 200, width: 640, height: 400)
        }
        drag = .none
        RecPicker.refresh()
        window?.invalidateCursorRects(for: self)
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: RecControl.closeBar()
        case 36, 76: if RecPicker.mode != .window { RecControl.begin() }
        default: super.keyDown(with: event)
        }
    }
}
