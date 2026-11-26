import AppKit
import CoreImage
import Observation

/// One screenshot being edited: the captured image, the marks on it, the crop and the frame, with undo.
/// The image never changes; everything else is applied when it is copied, saved or dragged out.
@MainActor
@Observable
final class ShotDocument {
    let image: CGImage
    /// Pixels per point: 2 for a Retina capture.
    let scale: CGFloat
    /// The file it came from, so Save can offer the same name.
    let source: URL?
    /// Save writes over `source`: it is a capture Nabız saved a moment ago, not someone's own picture.
    var replacesSource = false

    var items: [ShotItem] = [] { didSet { redraw() } }
    var selection: UUID? { didSet { redraw() } }
    var tool: ShotTool = .arrow {
        didSet {
            if tool != .select && tool != oldValue { selection = nil }
            if tool == .crop { cropDraft = crop ?? bounds }
            if oldValue == .crop && tool != .crop { commitCrop() }
            redraw()
        }
    }
    var ink: ShotInk { didSet { UserDefaults.standard.set(ShotInk.palette.firstIndex(of: ink) ?? 0, forKey: "shot.ink") } }
    var lineSize: ShotSize { didSet { UserDefaults.standard.set(lineSize.rawValue, forKey: "shot.size") } }
    /// The variant each tool last used.
    var styles: [ShotItem.Kind: Int] = [:]
    /// Applied crop, in image points; nil is the whole image.
    var crop: CGRect? { didSet { redraw() } }
    /// The crop being dragged while the crop tool is on.
    var cropDraft: CGRect? { didSet { redraw() } }
    var background = ShotBackground() { didSet { redraw() } }
    /// The text mark being typed into, hidden from the drawing while its editor is open.
    var editingText: UUID? { didSet { redraw() } }
    /// The bottom bar shows the frame settings instead of the mark settings.
    var framePanel = false

    /// A short note over the canvas ("Copied"), cleared after a moment.
    var toast: String?
    /// Counts changes, so closing can tell whether the last one was copied or saved.
    private(set) var changes = 0
    var savedChanges = 0
    var hasUnsavedChanges: Bool { changes != savedChanges && (!items.isEmpty || crop != nil) }

    private(set) var canUndo = false
    private(set) var canRedo = false

    @ObservationIgnored weak var canvas: NSView?
    @ObservationIgnored private var undoStack: [Snapshot] = []
    @ObservationIgnored private var redoStack: [Snapshot] = []
    @ObservationIgnored private var pixelated: CGImage?
    @ObservationIgnored private var blurred: CGImage?

    private struct Snapshot {
        var items: [ShotItem]
        var crop: CGRect?
        var background: ShotBackground
    }

    init(image: CGImage, scale: CGFloat, source: URL? = nil) {
        self.image = image
        self.scale = max(scale, 1)
        self.source = source
        let saved = UserDefaults.standard.object(forKey: "shot.ink") as? Int ?? 0
        ink = ShotInk.palette[min(max(saved, 0), ShotInk.palette.count - 1)]
        lineSize = ShotSize(rawValue: UserDefaults.standard.integer(forKey: "shot.size")) ?? .medium
        if let data = UserDefaults.standard.data(forKey: "shot.background"),
           let saved = try? JSONDecoder().decode(SavedBackground.self, from: data) {
            background = saved.background
        }
    }

    /// From a file on disk (png, jpg, heic, tiff, pdf's first page), keeping its Retina scale.
    convenience init?(contentsOf url: URL) {
        guard let image = NSImage(contentsOf: url) else { return nil }
        self.init(nsImage: image, source: url)
    }

    convenience init?(nsImage: NSImage, source: URL? = nil) {
        guard let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let pointWidth = nsImage.size.width
        let scale = pointWidth > 0 ? CGFloat(cg.width) / pointWidth : 1
        self.init(image: cg, scale: scale.rounded() == 0 ? 1 : scale, source: source)
    }

    // MARK: Geometry

    /// The whole image, in points.
    var bounds: CGRect { CGRect(x: 0, y: 0, width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale) }
    /// The part that is kept.
    var contentRect: CGRect { crop ?? bounds }
    /// What the canvas shows and the export holds: the content, plus the frame when it is on.
    /// While cropping, the whole image so the crop can grow back.
    var documentRect: CGRect {
        if tool == .crop { return bounds }
        return background.enabled ? contentRect.insetBy(dx: -background.padding, dy: -background.padding) : contentRect
    }

    var selectedItem: ShotItem? { items.first { $0.id == selection } }

    /// The style the next mark of this kind gets (and the selected one has).
    func style(for kind: ShotItem.Kind) -> Int { styles[kind] ?? 0 }

    // MARK: Editing

    /// Call before every change that Undo should take back.
    func checkpoint() {
        undoStack.append(Snapshot(items: items, crop: crop, background: background))
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        changes += 1
        refreshUndo()
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(Snapshot(items: items, crop: crop, background: background))
        changes += 1
        restore(last)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(items: items, crop: crop, background: background))
        changes += 1
        restore(next)
    }

    private func restore(_ snapshot: Snapshot) {
        items = snapshot.items
        crop = snapshot.crop
        background = snapshot.background
        if let selection, !items.contains(where: { $0.id == selection }) { self.selection = nil }
        refreshUndo()
    }

    private func refreshUndo() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func add(_ item: ShotItem) {
        checkpoint()
        items.append(item)
        selection = item.id
    }

    /// Takes back a mark that was just added (a click without a drag), with its undo step.
    func cancelAdd(_ id: UUID) {
        items.removeAll { $0.id == id }
        if selection == id { selection = nil }
        if !undoStack.isEmpty { undoStack.removeLast() }
        refreshUndo()
    }

    func update(_ id: UUID, _ change: (inout ShotItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    func deleteSelection() {
        guard let selection else { return }
        checkpoint()
        items.removeAll { $0.id == selection }
        self.selection = nil
    }

    func duplicateSelection() {
        guard let item = selectedItem else { return }
        var copy = item.offset(by: CGVector(dx: 16, dy: 16))
        copy.id = UUID()
        add(copy)
    }

    /// The colour, size or style picked in the bar also changes the selected mark.
    func setInk(_ ink: ShotInk) {
        self.ink = ink
        if let selection { checkpoint(); update(selection) { $0.ink = ink } }
    }

    func setSize(_ size: ShotSize) {
        lineSize = size
        if let selection { checkpoint(); update(selection) { $0.size = size } }
    }

    func setStyle(_ style: Int, for kind: ShotItem.Kind) {
        styles[kind] = style
        if let item = selectedItem, item.kind == kind { checkpoint(); update(item.id) { $0.style = style } }
        redraw()
    }

    func setBackground(_ change: (inout ShotBackground) -> Void) {
        checkpoint()
        var next = background
        change(&next)
        background = next
        if let data = try? JSONEncoder().encode(SavedBackground(background: next)) {
            UserDefaults.standard.set(data, forKey: "shot.background")
        }
    }

    /// Ends the crop tool: the draft becomes the crop (the whole image means no crop).
    func commitCrop() {
        guard let draft = cropDraft?.intersection(bounds), draft.width >= 4, draft.height >= 4 else { cropDraft = nil; return }
        let next: CGRect? = draft.integral == bounds.integral ? nil : draft
        if next != crop {
            checkpoint()
            crop = next
        }
        cropDraft = nil
    }

    func resetCrop() {
        if tool == .crop { cropDraft = bounds; return }
        guard crop != nil else { return }
        checkpoint()
        crop = nil
    }

    /// Step numbers count up in the order they were placed; deleting one renumbers the rest.
    func number(of item: ShotItem) -> Int {
        var count = 0
        for other in items where other.kind == .counter {
            count += 1
            if other.id == item.id { return count }
        }
        return count
    }

    func redraw() { canvas?.needsDisplay = true }

    // MARK: Hidden regions

    /// The whole image pixelated or blurred once; a hide mark shows its part of it.
    func hidden(pixelate: Bool) -> CGImage? {
        if pixelate, let pixelated { return pixelated }
        if !pixelate, let blurred { return blurred }
        let input = CIImage(cgImage: image)
        let output: CIImage = if pixelate {
            input.clampedToExtent()
                .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(8, 7 * scale), kCIInputCenterKey: CIVector(x: 0, y: 0)])
                .cropped(to: input.extent)
        } else {
            input.clampedToExtent().applyingGaussianBlur(sigma: 9 * scale).cropped(to: input.extent)
        }
        let context = CIContext(options: [.cacheIntermediates: false])
        let made = context.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)
        if pixelate { pixelated = made } else { blurred = made }
        return made
    }
}

/// ShotBackground's stored form.
private struct SavedBackground: Codable {
    var enabled: Bool
    var preset: Int
    var padding: CGFloat
    var radius: CGFloat
    var shadow: Bool

    init(background: ShotBackground) {
        enabled = background.enabled
        preset = background.preset
        padding = background.padding
        radius = background.radius
        shadow = background.shadow
    }

    var background: ShotBackground {
        ShotBackground(enabled: enabled, preset: min(max(preset, 0), ShotBackground.presets.count - 1),
                       padding: padding, radius: radius, shadow: shadow)
    }
}
