import AppKit
import SwiftUI

/// The editor's drawing surface: shows the document fitted to the window and turns clicks and drags into marks.
/// Marks stay selectable objects: click one to move it, drag its handles to reshape it, ⌫ to delete it.
final class ShotCanvasView: NSView, NSTextViewDelegate {
    let doc: ShotDocument
    /// Copy, save and the other bar actions, for the keyboard shortcuts.
    var perform: (ShotAction) -> Void = { _ in }

    private enum Drag {
        case none
        case create(UUID, origin: CGPoint)
        case move(UUID, last: CGPoint, moved: Bool)
        case handle(UUID, index: Int, fixed: CGPoint)
        case cropNew(origin: CGPoint)
        case cropMove(start: CGRect, origin: CGPoint)
        case cropHandle(index: Int, start: CGRect)
    }

    private var drag = Drag.none
    private var textEditor: ShotTextView?
    private var editorIsNew = false
    private var trackingArea: NSTrackingArea?

    init(doc: ShotDocument) {
        self.doc = doc
        super.init(frame: .zero)
        doc.canvas = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometry

    /// Image points to view points: the document fitted inside the view with a margin, never enlarged past 1:1.
    var zoom: CGFloat {
        let rect = doc.documentRect
        let room = bounds.insetBy(dx: 28, dy: 28)
        guard rect.width > 0, rect.height > 0, room.width > 0, room.height > 0 else { return 1 }
        return min(1, room.width / rect.width, room.height / rect.height)
    }

    private var origin: CGPoint {
        let rect = doc.documentRect
        return CGPoint(x: ((bounds.width - rect.width * zoom) / 2).rounded(), y: ((bounds.height - rect.height * zoom) / 2).rounded())
    }

    func toImage(_ p: CGPoint) -> CGPoint {
        let rect = doc.documentRect
        return CGPoint(x: (p.x - origin.x) / zoom + rect.minX, y: (p.y - origin.y) / zoom + rect.minY)
    }

    func toView(_ p: CGPoint) -> CGPoint {
        let rect = doc.documentRect
        return CGPoint(x: (p.x - rect.minX) * zoom + origin.x, y: (p.y - rect.minY) * zoom + origin.y)
    }

    func toView(_ r: CGRect) -> CGRect {
        CGRect(from: toView(r.origin), to: toView(CGPoint(x: r.maxX, y: r.maxY)))
    }

    /// How far off a click may land and still hit a mark, in image points.
    private var slop: CGFloat { 5 / zoom }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = doc.documentRect
        let page = CGRect(origin: origin, size: CGSize(width: rect.width * zoom, height: rect.height * zoom))
        let backing = window?.backingScaleFactor ?? 2
        // A soft lift under the screenshot when it has no frame of its own.
        if !doc.background.enabled || doc.tool == .crop {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 18, color: CGColor(gray: 0, alpha: 0.28))
            ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
            ctx.fill(page)
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        ShotRenderer.draw(doc, in: ctx, device: zoom * backing)
        ctx.restoreGState()
        // Shadow-free hairline so a white screenshot doesn't melt into a light window.
        if !doc.background.enabled || doc.tool == .crop {
            ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.25))
            ctx.setLineWidth(1 / backing)
            ctx.stroke(page.insetBy(dx: -0.5 / backing, dy: -0.5 / backing))
        }
        if doc.tool == .crop { drawCrop(ctx) } else { drawSelection(ctx) }
    }

    private var accent: NSColor { NSColor(Theme.accent) }

    private func drawSelection(_ ctx: CGContext) {
        guard let item = doc.selectedItem, item.id != doc.editingText else { return }
        ctx.saveGState()
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(1)
        if item.handles != .ends {
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(toView(ShotRenderer.frame(item)).insetBy(dx: -4, dy: -4).integral.insetBy(dx: 0.5, dy: 0.5))
            ctx.setLineDash(phase: 0, lengths: [])
        }
        for point in handlePoints(item) { drawHandle(ctx, toView(point)) }
        ctx.restoreGState()
    }

    private func drawHandle(_ ctx: CGContext, _ p: CGPoint) {
        let r: CGFloat = 4.5
        let box = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 2, color: CGColor(gray: 0, alpha: 0.35))
        ctx.setFillColor(.white)
        ctx.fillEllipse(in: box)
        ctx.restoreGState()
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: box.insetBy(dx: 0.75, dy: 0.75))
    }

    /// Ends for lines and arrows, corners for boxes; none for marks that only move.
    private func handlePoints(_ item: ShotItem) -> [CGPoint] {
        let r = item.rect
        switch item.handles {
        case .none: return []
        case .ends: return [item.start, item.end]
        case .corners:
            return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
        }
    }

    private func cropHandles(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
         CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY)]
    }

    /// Outside the crop dimmed, thirds inside, corner brackets and the size in pixels.
    private func drawCrop(_ ctx: CGContext) {
        let crop = toView(doc.cropDraft ?? doc.bounds)
        let page = toView(doc.bounds)
        ctx.saveGState()
        let dim = CGMutablePath()
        dim.addRect(page)
        dim.addRect(crop)
        ctx.addPath(dim)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.5))
        ctx.fillPath(using: .evenOdd)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.35))
        ctx.setLineWidth(0.5)
        for i in 1...2 {
            let x = crop.minX + crop.width * CGFloat(i) / 3, y = crop.minY + crop.height * CGFloat(i) / 3
            ctx.strokeLineSegments(between: [CGPoint(x: x, y: crop.minY), CGPoint(x: x, y: crop.maxY),
                                             CGPoint(x: crop.minX, y: y), CGPoint(x: crop.maxX, y: y)])
        }
        ctx.setStrokeColor(.white)
        ctx.setLineWidth(1)
        ctx.stroke(crop.insetBy(dx: 0.5, dy: 0.5))
        ctx.setLineWidth(3)
        ctx.setLineCap(.round)
        let arm = min(16, crop.width / 3, crop.height / 3)
        for (corner, sx, sy) in [(CGPoint(x: crop.minX, y: crop.minY), 1.0, 1.0), (CGPoint(x: crop.maxX, y: crop.minY), -1.0, 1.0),
                                 (CGPoint(x: crop.minX, y: crop.maxY), 1.0, -1.0), (CGPoint(x: crop.maxX, y: crop.maxY), -1.0, -1.0)] {
            ctx.move(to: CGPoint(x: corner.x + arm * sx, y: corner.y))
            ctx.addLine(to: corner)
            ctx.addLine(to: CGPoint(x: corner.x, y: corner.y + arm * sy))
        }
        ctx.strokePath()
        ctx.restoreGState()
        let pixels = (doc.cropDraft ?? doc.bounds)
        let label = "\(Int((pixels.width * doc.scale).rounded())) × \(Int((pixels.height * doc.scale).rounded()))"
        drawBadge(label, at: CGPoint(x: crop.midX, y: crop.maxY + 8 > page.maxY - 4 ? crop.maxY - 30 : crop.maxY + 8))
    }

    private func drawBadge(_ text: String, at top: CGPoint) {
        let string = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                                                                   .foregroundColor: NSColor.white])
        let size = string.size()
        let box = CGRect(x: top.x - size.width / 2 - 7, y: top.y, width: size.width + 14, height: size.height + 6)
        NSColor(white: 0, alpha: 0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        string.draw(at: CGPoint(x: box.minX + 7, y: box.minY + 3))
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = toImage(convert(event.locationInWindow, from: nil))
        if textEditor != nil {
            endTextEditing()
            if doc.tool != .text { return }
        }
        switch doc.tool {
        case .crop:
            let crop = doc.cropDraft ?? doc.bounds
            if let index = cropHandles(crop).firstIndex(where: { $0.distance(to: p) <= slop * 2 }) {
                drag = .cropHandle(index: index, start: crop)
            } else if crop.contains(p) {
                drag = .cropMove(start: crop, origin: p)
            } else {
                drag = .cropNew(origin: p)
            }
        case .select:
            if grabHandle(p) { return }
            if let item = topItem(at: p) {
                doc.selection = item.id
                if event.clickCount == 2 && item.kind == .text { beginTextEditing(item, isNew: false); return }
                drag = .move(item.id, last: p, moved: false)
            } else {
                doc.selection = nil
            }
        case .text:
            if let item = topItem(at: p), item.kind == .text {
                doc.selection = item.id
                beginTextEditing(item, isNew: false)
                return
            }
            let item = ShotItem(kind: .text, start: p, end: p, ink: doc.ink, size: doc.lineSize, style: doc.style(for: .text))
            doc.add(item)
            beginTextEditing(item, isNew: true)
        default:
            guard let kind = doc.tool.kind else { return }
            if grabHandle(p) { return }
            // The mark just drawn can be moved straight away without switching tools.
            if let selected = doc.selectedItem, ShotRenderer.hit(selected, p, slop: slop) {
                drag = .move(selected.id, last: p, moved: false)
                return
            }
            if kind == .counter, let counter = topItem(at: p), counter.kind == .counter {
                doc.selection = counter.id
                drag = .move(counter.id, last: p, moved: false)
                return
            }
            let item = ShotItem(kind: kind, start: p, end: p, points: kind == .pen ? [p] : [], ink: kind == .highlight && doc.ink == ShotInk.palette[0] ? ShotInk.palette[2] : doc.ink,
                                size: doc.lineSize, style: doc.style(for: kind))
            doc.add(item)
            drag = kind == .counter ? .none : .create(item.id, origin: p)
        }
    }

    /// Starts dragging a handle of the selected mark, if the click is on one.
    private func grabHandle(_ p: CGPoint) -> Bool {
        guard let item = doc.selectedItem else { return false }
        let points = handlePoints(item)
        guard let index = points.firstIndex(where: { $0.distance(to: p) <= slop * 1.6 }) else { return false }
        doc.checkpoint()
        let fixed: CGPoint = item.handles == .ends ? points[1 - index] : points[3 - index]
        drag = .handle(item.id, index: index, fixed: fixed)
        return true
    }

    private func topItem(at p: CGPoint) -> ShotItem? {
        doc.items.last { ShotRenderer.hit($0, p, slop: slop) }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = toImage(convert(event.locationInWindow, from: nil))
        let shift = event.modifierFlags.contains(.shift)
        switch drag {
        case .none:
            break
        case let .create(id, origin):
            doc.update(id) { item in
                if item.kind == .pen {
                    if let last = item.points.last, last.distance(to: p) < 0.75 / zoom { return }
                    item.points.append(shift ? p.constrained(from: origin, box: false) : p)
                    item.end = p
                } else {
                    let box = item.kind != .arrow && item.kind != .line
                    item.end = shift ? p.constrained(from: origin, box: box) : p
                }
            }
        case let .move(id, last, moved):
            if !moved {
                guard p.distance(to: last) > 1 / zoom else { return }
                doc.checkpoint()
            }
            doc.update(id) { $0 = $0.offset(by: CGVector(dx: p.x - last.x, dy: p.y - last.y)) }
            drag = .move(id, last: p, moved: true)
        case let .handle(id, _, fixed):
            doc.update(id) { item in
                let box = item.handles == .corners
                let target = shift ? p.constrained(from: fixed, box: box) : p
                item.start = fixed
                item.end = target
            }
        case let .cropNew(origin):
            let end = shift ? p.constrained(from: origin, box: true) : p
            doc.cropDraft = CGRect(from: origin, to: end).intersection(doc.bounds)
        case let .cropMove(start, origin):
            var moved = start.offsetBy(dx: p.x - origin.x, dy: p.y - origin.y)
            moved.origin.x = min(max(moved.minX, 0), doc.bounds.width - moved.width)
            moved.origin.y = min(max(moved.minY, 0), doc.bounds.height - moved.height)
            doc.cropDraft = moved
        case let .cropHandle(index, start):
            var minX = start.minX, minY = start.minY, maxX = start.maxX, maxY = start.maxY
            switch index {
            case 0: minX = p.x; minY = p.y
            case 1: maxX = p.x; minY = p.y
            case 2: minX = p.x; maxY = p.y
            case 3: maxX = p.x; maxY = p.y
            case 4: minY = p.y
            case 5: maxY = p.y
            case 6: minX = p.x
            default: maxX = p.x
            }
            doc.cropDraft = CGRect(from: CGPoint(x: minX, y: minY), to: CGPoint(x: maxX, y: maxY)).intersection(doc.bounds)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if case let .create(id, _) = drag, let item = doc.items.first(where: { $0.id == id }) {
            let tiny = switch item.kind {
            case .pen: item.points.count < 2
            case .arrow, .line: item.start.distance(to: item.end) < 4 / zoom
            default: item.rect.width < 3 / zoom || item.rect.height < 3 / zoom
            }
            if tiny { doc.cancelAdd(id) }
        }
        drag = .none
        window?.invalidateCursorRects(for: self)
    }

    override func scrollWheel(with event: NSEvent) {
        // Scrolling over the canvas changes the line size, like Flameshot's mouse wheel.
        guard doc.tool != .select, doc.tool != .crop, abs(event.scrollingDeltaY) > 2, event.phase != .changed || abs(event.scrollingDeltaY) > 6 else { return }
        let next = doc.lineSize.rawValue + (event.scrollingDeltaY > 0 ? 1 : -1)
        if let size = ShotSize(rawValue: next), event.momentumPhase == [] { doc.setSize(size) }
    }

    // MARK: Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }

    private func updateCursor(_ event: NSEvent) {
        let p = toImage(convert(event.locationInWindow, from: nil))
        if let item = doc.selectedItem, handlePoints(item).contains(where: { $0.distance(to: p) <= slop * 1.6 }) {
            NSCursor.crosshair.set()
            return
        }
        switch doc.tool {
        case .select:
            (topItem(at: p) != nil ? NSCursor.openHand : NSCursor.arrow).set()
        case .text:
            (topItem(at: p)?.kind == .text ? NSCursor.pointingHand : NSCursor.iBeam).set()
        case .crop:
            let crop = doc.cropDraft ?? doc.bounds
            (crop.contains(p) ? NSCursor.openHand : NSCursor.crosshair).set()
        default:
            if let selected = doc.selectedItem, ShotRenderer.hit(selected, p, slop: slop) { NSCursor.openHand.set() } else { NSCursor.crosshair.set() }
        }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        switch Int(event.keyCode) {
        case 51, 117:
            doc.deleteSelection()
        case 53:
            if doc.tool == .crop { doc.tool = .select } else if doc.selection != nil { doc.selection = nil } else { perform(.close) }
        case 36, 76:
            if doc.tool == .crop { doc.tool = .select } else if let item = doc.selectedItem, item.kind == .text { beginTextEditing(item, isNew: false) }
        case 123, 124, 125, 126:
            guard let id = doc.selection else { return }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let delta: CGVector = switch Int(event.keyCode) {
            case 123: CGVector(dx: -step, dy: 0)
            case 124: CGVector(dx: step, dy: 0)
            case 125: CGVector(dx: 0, dy: step)
            default: CGVector(dx: 0, dy: -step)
            }
            doc.checkpoint()
            doc.update(id) { $0 = $0.offset(by: delta) }
        default:
            guard flags.isEmpty, let typed = event.charactersIgnoringModifiers?.lowercased().first else { super.keyDown(with: event); return }
            if let tool = ShotTool.allCases.first(where: { $0.key == typed }) {
                doc.tool = tool
            } else if let digit = typed.wholeNumberValue, (1...ShotInk.palette.count).contains(digit) {
                doc.setInk(ShotInk.palette[digit - 1])
            } else if typed == "[" || typed == "]" {
                if let size = ShotSize(rawValue: doc.lineSize.rawValue + (typed == "]" ? 1 : -1)) { doc.setSize(size) }
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (flags, key) {
        case ([.command], "s"): perform(.save); return true
        case ([.command, .shift], "s"): perform(.saveAs); return true
        case ([.command], "d"): doc.duplicateSelection(); return true
        case ([.command, .shift], "c"): perform(.copyText); return true
        case ([.command], "p"): perform(.pin); return true
        case ([.command], "\r"): perform(.done); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    @objc func undo(_ sender: Any?) { doc.undo() }
    @objc func redo(_ sender: Any?) { doc.redo() }
    @objc func copy(_ sender: Any?) { perform(.copy) }
    @objc func delete(_ sender: Any?) { doc.deleteSelection() }
    override func selectAll(_ sender: Any?) {}

    // MARK: Text

    private func beginTextEditing(_ item: ShotItem, isNew: Bool) {
        endTextEditing()
        if !isNew { doc.checkpoint() }
        editorIsNew = isNew
        doc.tool = doc.tool == .select ? .select : .text
        doc.selection = item.id
        doc.editingText = item.id
        let editor = ShotTextView(frame: .zero)
        editor.delegate = self
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = CGSize(width: 100_000, height: 100_000)
        editor.textContainer?.lineFragmentPadding = 0
        editor.string = item.text
        editor.onFinish = { [weak self] in self?.endTextEditing() }
        textEditor = editor
        addSubview(editor)
        styleTextEditor()
        window?.makeFirstResponder(editor)
        editor.selectAll(nil)
    }

    /// Matches the editor to the mark: its font at the canvas zoom, its colour, its label.
    private func styleTextEditor() {
        guard let editor = textEditor, let id = doc.editingText, let item = doc.items.first(where: { $0.id == id }) else { return }
        let font = ShotRenderer.textFont(item)
        let scaled = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * zoom) ?? font
        editor.font = scaled
        editor.textColor = item.style == 1 ? item.ink.contrast.nsColor : item.ink.nsColor
        editor.insertionPointColor = editor.textColor ?? .labelColor
        let pad = ShotRenderer.labelPadding(item)
        editor.textContainerInset = NSSize(width: pad.width * zoom, height: pad.height * zoom)
        let frame = toView(ShotRenderer.textFrame(item))
        editor.frame = CGRect(x: frame.minX, y: frame.minY, width: max(frame.width + 4, 24), height: frame.height)
        editor.wantsLayer = true
        editor.layer?.cornerRadius = item.style == 1 ? frame.height * 0.28 : 4
        editor.layer?.backgroundColor = item.style == 1 ? item.ink.cgColor : NSColor(white: 0.5, alpha: 0.12).cgColor
        editor.layer?.borderColor = accent.cgColor
        editor.layer?.borderWidth = item.style == 1 ? 0 : 1
    }

    func textDidChange(_ notification: Notification) {
        guard let editor = textEditor, let id = doc.editingText else { return }
        doc.update(id) { $0.text = editor.string }
        styleTextEditor()
    }

    func endTextEditing() {
        guard let editor = textEditor, let id = doc.editingText else { return }
        textEditor = nil
        editor.removeFromSuperview()
        let text = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        doc.editingText = nil
        if text.isEmpty {
            if editorIsNew { doc.cancelAdd(id) } else { doc.items.removeAll { $0.id == id }; doc.selection = nil }
        } else {
            doc.update(id) { $0.text = editor.string.trimmingCharacters(in: .newlines) }
        }
        window?.makeFirstResponder(self)
    }

    /// Keeps the text editor in place when the window (and so the zoom) changes size.
    override func layout() {
        super.layout()
        styleTextEditor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// The text field over a text mark: Return finishes, ⇧Return or ⌥Return adds a line, ⎋ finishes too.
final class ShotTextView: NSTextView {
    var onFinish: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53:
            onFinish()
        case 36, 76 where event.modifierFlags.intersection([.shift, .option]).isEmpty:
            onFinish()
        default:
            super.keyDown(with: event)
        }
    }
}

/// The canvas in SwiftUI.
struct ShotCanvas: NSViewRepresentable {
    let doc: ShotDocument
    let perform: (ShotAction) -> Void

    func makeNSView(context: Context) -> ShotCanvasView {
        let view = ShotCanvasView(doc: doc)
        view.perform = perform
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: ShotCanvasView, context: Context) {
        view.perform = perform
        view.needsDisplay = true
    }
}

/// What the bar buttons and their shortcuts do.
enum ShotAction {
    case copy, save, saveAs, copyText, pin, share, done, close
}
