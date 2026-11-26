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
            panels.forEach { $0.orderFrontRegardless() }
            panels.first { $0.screen == hoveredScreen }?.makeKey()
        }
        refresh()
    }

    static func close() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }

    static func refresh() {
        panels.forEach { $0.contentView?.needsDisplay = true }
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

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
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

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let window else { return }
        let mouseHere = window.frame.contains(NSEvent.mouseLocation)
        switch RecPicker.mode {
        case .screen:
            if mouseHere {
                ctx.setFillColor(accent.withAlphaComponent(0.10).cgColor)
                ctx.fill(bounds)
                ctx.setStrokeColor(accent.cgColor)
                ctx.setLineWidth(6)
                ctx.stroke(bounds.insetBy(dx: 3, dy: 3))
                hint(L("Bu ekranı kaydetmek için tıkla", "Click to record this screen"), at: NSPoint(x: bounds.midX, y: bounds.midY))
            } else {
                ctx.setFillColor(CGColor(gray: 0, alpha: 0.3))
                ctx.fill(bounds)
            }
        case .window:
            let hovered = RecPicker.window(at: NSEvent.mouseLocation)
            let lit = hovered.map { local($0.frame) }
            let dim = CGMutablePath()
            dim.addRect(bounds)
            if let lit { dim.addRect(lit) }
            ctx.addPath(dim)
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.35))
            ctx.fillPath(using: .evenOdd)
            if let lit, bounds.intersects(lit) {
                ctx.setFillColor(accent.withAlphaComponent(0.12).cgColor)
                ctx.fill(lit)
                ctx.setStrokeColor(accent.cgColor)
                ctx.setLineWidth(4)
                ctx.stroke(lit.insetBy(dx: 2, dy: 2))
                hint(L("Bu pencereyi kaydetmek için tıkla", "Click to record this window"), at: NSPoint(x: lit.midX, y: lit.midY))
            }
        case .area:
            let box = local(RecPicker.area)
            let dim = CGMutablePath()
            dim.addRect(bounds)
            dim.addRect(box)
            ctx.addPath(dim)
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.4))
            ctx.fillPath(using: .evenOdd)
            guard bounds.intersects(box) else { return }
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            ctx.stroke(box.insetBy(dx: -0.5, dy: -0.5))
            ctx.setLineDash(phase: 0, lengths: [])
            for handle in handles(box) {
                let dot = NSRect(x: handle.x - 5, y: handle.y - 5, width: 10, height: 10)
                ctx.setFillColor(.white)
                ctx.fillEllipse(in: dot)
                ctx.setStrokeColor(accent.cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: dot.insetBy(dx: 0.75, dy: 0.75))
            }
            let label = "\(Int(RecPicker.area.width)) × \(Int(RecPicker.area.height))"
            badge(label, at: NSPoint(x: box.midX, y: box.minY - 30 > 8 ? box.minY - 30 : box.minY + 10))
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
        RecPicker.refresh()
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
