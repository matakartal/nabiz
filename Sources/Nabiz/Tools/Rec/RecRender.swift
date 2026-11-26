import AppKit
import AVFoundation
import Metal
import CoreImage
import CoreImage.CIFilterBuiltins

/// Everything needed to draw one frame of a styled recording, worked out once: the camera's zoom and position and
/// the smoothed pointer at 60 steps a second, the background, shadow and corner mask. Immutable, so AVFoundation
/// can call `frame` from its own threads while the editor builds the next plan.
final class RecPlan: @unchecked Sendable {
    /// Recorded video, in pixels.
    let source: CGSize
    /// The finished frame, in pixels.
    let output: CGSize
    /// Output pixels per source pixel (below 1 for a lighter preview or a 1080p export).
    let k: CGFloat
    /// Where the video sits in the output (Core Image, bottom-left origin).
    let content: CGRect
    /// Source pixels per screen point (2 on Retina).
    let screenScale: CGFloat
    let style: RecStyle

    private let fps = 60.0
    /// Where the pointer is drawn and how it reacts to clicks.
    private let cursorPath: RecCursorPath
    /// Where the camera looks.
    private let lens: RecLens
    private let clicks: [RecTrack.Point]
    private let shapes: [RecTrack.Shape]
    private let cursors: [(image: CIImage, info: RecCursor)]
    private let base: CIImage
    private let mask: CIImage?
    private let ring: CIImage
    /// Recording time ↔ played time, with the speed-ups.
    let map: RecTimeMap
    /// How visible the pointer is (it fades after standing still).
    private let keys: [RecTrack.Key]
    private let keyImages: [String: CIImage]
    private let cameraOn: Bool
    private let captions: [RecCaption]
    private let captionImages: [UUID: CIImage]
    /// Each note's label and arrow, drawn once and placed in output pixels.
    private let notes: [(note: RecNote, image: CIImage)]

    /// `maxWidth` caps the output width (preview, 1080p, 4K); nil keeps the recording's full size.
    init(meta: RecMeta, edit: RecEdit, maxWidth: CGFloat?) {
        let style = edit.style
        self.style = style
        source = CGSize(width: meta.width, height: meta.height)
        screenScale = CGFloat(meta.scale)
        let pad = (CGFloat(style.padding) * source.width).rounded()
        // The frame: the video plus padding, widened or heightened to the chosen shape (16:9, 9:16, 1:1…).
        let inner = CGSize(width: source.width + pad * 2, height: source.height + pad * 2)
        var canvas = inner
        if let ratio = style.aspectRatio.map({ CGFloat($0) }) {
            if inner.width / inner.height > ratio { canvas.height = inner.width / ratio } else { canvas.width = inner.height * ratio }
        }
        let fit = maxWidth.map { min(1, $0 / max(canvas.width, canvas.height * 16 / 9)) } ?? 1
        // Even pixel sizes for the encoder.
        output = CGSize(width: (canvas.width * fit / 2).rounded() * 2, height: (canvas.height * fit / 2).rounded() * 2)
        k = output.width / canvas.width
        content = CGRect(x: ((output.width - source.width * k) / 2).rounded(), y: ((output.height - source.height * k) / 2).rounded(),
                         width: source.width * k, height: source.height * k)
        map = RecTimeMap(edit.timeSegments, duration: meta.duration)
        keys = style.showKeys ? meta.track.keys : []
        cameraOn = style.camera && meta.cameraOffset != nil

        cursorPath = RecCursorPath(track: meta.track, size: source, smoothing: style.smoothCursor ? 0.3 : 0)
        lens = RecLens(regions: edit.zooms.map { zoom in
            RecLens.Region(start: zoom.start, end: zoom.end, scale: zoom.scale, focus: zoom.focusX.map { ($0, zoom.focusY ?? 0.5) })
        }, cursor: cursorPath, typing: meta.track.carets.map { caret in
            (t: caret.t, x: caret.x / max(Double(meta.width), 1), y: caret.y / max(Double(meta.height), 1))
        })
        var keyImages: [String: CIImage] = [:]
        for key in keys where keyImages[key.text] == nil {
            keyImages[key.text] = Self.keyImage(key.text, height: output.height * 0.055)
        }
        self.keyImages = keyImages
        captions = style.showCaptions ? edit.captions : []
        var captionImages: [UUID: CIImage] = [:]
        for caption in captions {
            captionImages[caption.id] = Self.pill(caption.text, height: output.height * 0.062, fill: CGColor(gray: 0.06, alpha: 0.78))
        }
        self.captionImages = captionImages
        let accent = MainActor.assumeIsolated { NSColor(Theme.accent).usingColorSpace(.sRGB)?.cgColor } ?? CGColor(srgbRed: 0.1, green: 0.7, blue: 0.4, alpha: 1)
        let outputSize = output, videoBox = content
        notes = edit.notes.map { note in (note, Self.noteImage(note, in: outputSize, on: videoBox, accent: accent)) }
        clicks = meta.track.clicks
        shapes = meta.track.shapes
        var cursors: [(CIImage, RecCursor)] = meta.cursors.compactMap { info in
            let url = RecStore.folder(for: meta.id).appendingPathComponent(info.file)
            return CIImage(contentsOf: url).map { ($0, info) }
        }
        if cursors.isEmpty, let arrow = Self.arrow() { cursors = [arrow] }
        self.cursors = cursors
        ring = Self.ringImage()

        // Background, shadow and the rounded corners, drawn once.
        let extent = CGRect(origin: .zero, size: output)
        if pad > 0 || style.aspectRatio != nil {
            let (from, to) = ShotBackground.presets[min(max(style.background, 0), ShotBackground.presets.count - 1)]
            let gradient = CIFilter.linearGradient()
            gradient.point0 = CGPoint(x: 0, y: output.height)
            gradient.point1 = CGPoint(x: output.width, y: 0)
            gradient.color0 = CIColor(cgColor: from.cgColor)
            gradient.color1 = CIColor(cgColor: to.cgColor)
            var background = gradient.outputImage?.cropped(to: extent) ?? CIImage(color: .black).cropped(to: extent)
            switch style.backgroundKind {
            case "solid":
                background = CIImage(color: CIColor(hex: style.solidColor) ?? .black).cropped(to: extent)
            case "wallpaper", "image":
                if !style.backgroundImage.isEmpty, let picture = MainActor.assumeIsolated({
                    RecBackdrop.image(URL(fileURLWithPath: style.backgroundImage), size: extent.size, blur: style.backgroundBlur)
                }) {
                    background = CIImage(cgImage: picture)
                }
            default:
                break
            }
            let radius = CGFloat(style.radius) * source.width * k
            if style.shadow {
                let shape = CIFilter.roundedRectangleGenerator()
                shape.extent = content.offsetBy(dx: 0, dy: -source.width * k * 0.008)
                shape.radius = Float(radius)
                shape.color = CIColor(red: 0, green: 0, blue: 0, alpha: 0.5)
                if let shadow = shape.outputImage?.applyingGaussianBlur(sigma: Double(source.width * k * 0.018)).cropped(to: extent) {
                    background = shadow.composited(over: background)
                }
            }
            base = background
            let corners = CIFilter.roundedRectangleGenerator()
            corners.extent = content
            corners.radius = Float(radius)
            corners.color = .white
            mask = corners.outputImage?.cropped(to: extent)
        } else {
            base = CIImage(color: .black).cropped(to: extent)
            mask = nil
        }
    }

    // MARK: Frame

    /// One finished frame. `played` is the time in the (possibly sped-up) result.
    func frame(source frame: CIImage, camera face: CIImage? = nil, time played: Double) -> CIImage {
        let time = map.source(played)
        let (z, f) = camera(at: time)
        let transform = self.transform(zoom: z, focus: f)
        var video = frame.transformed(by: transform).cropped(to: content)
        if style.motionBlur, let blurred = cameraBlur(frame, played: played, time: time, transform: transform) { video = blurred }
        var image: CIImage
        if let mask {
            let blend = CIFilter.blendWithMask()
            blend.inputImage = video
            blend.backgroundImage = base
            blend.maskImage = mask
            image = blend.outputImage ?? video.composited(over: base)
        } else {
            image = video.composited(over: base)
        }
        let s = k * CGFloat(z)
        if style.clickRings { image = rings(at: time, transform: transform, scale: s).composited(over: image) }
        if let cursor = cursor(at: time, transform: transform, scale: s) { image = cursor.composited(over: image) }
        if let key = keyOverlay(at: time, raised: caption(at: time) != nil) { image = key.composited(over: image) }
        if let line = captionOverlay(at: time) { image = line.composited(over: image) }
        // Notes stick to what they point at: they move and grow with the zoom like the video under them.
        let still = self.transform(zoom: 1, focus: CGPoint(x: source.width / 2, y: source.height / 2))
        let follow = still.inverted().concatenating(transform)
        for (note, picture) in notes where time >= note.start - 0.2 && time <= note.end + 0.2 {
            let alpha = min(1, (time - note.start + 0.2) / 0.2, (note.end + 0.2 - time) / 0.2)
            image = picture.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
                .transformed(by: follow).cropped(to: content).composited(over: image)
        }
        if cameraOn, let face, let bubble = bubble(face) { image = bubble.composited(over: image) }
        return image.cropped(to: CGRect(origin: .zero, size: output))
    }

    /// A fast camera move (a zoom going in or out, a pan between spots) gets the smear a real camera's shutter
    /// gives it: the frame is placed at a few moments across the last half frame and the copies are averaged.
    /// A still or slow camera costs nothing extra.
    private func cameraBlur(_ frame: CIImage, played: Double, time: Double, transform now: CGAffineTransform) -> CIImage? {
        let before = map.source(max(0, played - 0.5 / fps))
        guard time - before > 0.0001 else { return nil }
        let (z0, f0) = camera(at: before)
        let back = now.inverted().concatenating(transform(zoom: z0, focus: f0))
        let spots = [CGPoint(x: content.minX, y: content.minY), CGPoint(x: content.maxX, y: content.minY),
                     CGPoint(x: content.minX, y: content.maxY), CGPoint(x: content.maxX, y: content.maxY),
                     CGPoint(x: content.midX, y: content.midY)]
        let travel = spots.map { spot in
            let was = spot.applying(back)
            return hypot(was.x - spot.x, was.y - spot.y)
        }.max() ?? 0
        // About 2 px on a 1080p frame before it shows; one copy for every 2 px it moved, at most 10.
        let unit = max(output.width, output.height) / 1920 * 2
        let count = min(10, Int(travel / unit) + 1)
        guard count >= 3 else { return nil }
        let weight = 1 / CGFloat(count)
        // The colour matrix works on unpremultiplied colour: scaling alpha alone gives each copy its share.
        let fade: [String: Any] = ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: weight)]
        var sum: CIImage?
        for i in 0..<count {
            let at = before + (time - before) * Double(i) / Double(count - 1)
            let (z, f) = camera(at: at)
            let copy = frame.transformed(by: transform(zoom: z, focus: f)).cropped(to: content).applyingFilter("CIColorMatrix", parameters: fade)
            sum = sum.map { copy.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: $0]) } ?? copy
        }
        return sum?.cropped(to: content)
    }

    /// Source pixels (bottom-left origin) to output pixels for the camera at this zoom and focus.
    private func transform(zoom z: Double, focus: CGPoint) -> CGAffineTransform {
        let z = CGFloat(max(z, 1))
        let window = CGSize(width: source.width / z, height: source.height / z)
        let left = min(max(focus.x - window.width / 2, 0), source.width - window.width)
        let top = min(max(focus.y - window.height / 2, 0), source.height - window.height)
        let bottom = source.height - top - window.height
        let s = k * z
        return CGAffineTransform(translationX: -left, y: -bottom)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: content.minX, y: content.minY))
    }

    private func sample<T>(_ values: [T], at time: Double, mix: (T, T, Double) -> T) -> T {
        let position = max(0, time * fps)
        let index = min(Int(position), values.count - 1)
        let next = min(index + 1, values.count - 1)
        return mix(values[index], values[next], position - Double(index))
    }

    /// Zoom and the point it looks at, in source pixels (top-left origin).
    func camera(at time: Double) -> (Double, CGPoint) {
        let state = lens.state(at: time)
        return (state.scale, CGPoint(x: state.focus.0 * source.width, y: state.focus.1 * source.height))
    }

    private func pointer(at time: Double) -> CGPoint? {
        cursorPath.at(time).map { CGPoint(x: $0.0 * source.width, y: $0.1 * source.height) }
    }

    /// The pointer image at its spot, with a soft shadow, sized with the zoom.
    private func cursor(at time: Double, transform: CGAffineTransform, scale s: CGFloat) -> CIImage? {
        guard !cursors.isEmpty else { return nil }
        let alpha = style.hideIdleCursor ? cursorPath.opacity(time) : 1
        guard alpha > 0.01, let p = pointer(at: time) else { return nil }
        let at = CGPoint(x: p.x, y: source.height - p.y).applying(transform)
        guard content.insetBy(dx: -40, dy: -40).contains(at) else { return nil }
        var index = 0
        if let shape = shapes.last(where: { $0.t <= time }) { index = min(shape.index, cursors.count - 1) }
        let (image, info) = cursors[index]
        // Output pixels per screen point: source pixels per point × output pixels per source pixel.
        // The click bounce scales around the hot spot, so the tip stays on what was clicked.
        let bounce = style.clickBounce ? CGFloat(cursorPath.bounce(time)) : 1
        let width = CGFloat(info.width) * screenScale * s * CGFloat(style.cursorSize) * bounce
        let fit = width / max(image.extent.width, 1)
        let sized = image.transformed(by: CGAffineTransform(scaleX: fit, y: fit))
        let origin = CGPoint(x: at.x - CGFloat(info.hotX) * width / CGFloat(info.width),
                             y: at.y - (CGFloat(info.height) - CGFloat(info.hotY)) * width / CGFloat(info.width))
        var placed = sized.transformed(by: CGAffineTransform(translationX: origin.x - sized.extent.minX, y: origin.y - sized.extent.minY))
        // A fast pointer smears along its path, like a camera would see it.
        if style.motionBlur {
            let before = pointer(at: max(0, time - 1 / fps)) ?? p
            let dx = (p.x - before.x) * s, dy = -(p.y - before.y) * s
            let speed = hypot(dx, dy)
            if speed > 8 * k {
                placed = placed.clampedToExtent()
                    .applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: min(speed * 0.4, 30 * k), kCIInputAngleKey: atan2(dy, dx)])
                    .cropped(to: placed.extent.insetBy(dx: -speed, dy: -speed))
            }
        }
        if alpha < 0.99 {
            placed = placed.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
        }
        let shadow = placed
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                                                          "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                                                          "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                                                          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.35)])
            .applyingGaussianBlur(sigma: Double(max(1, width * 0.06)))
            .transformed(by: CGAffineTransform(translationX: 0, y: -width * 0.04))
        return placed.composited(over: shadow)
    }

    /// A ring that grows and fades where each click landed.
    private func rings(at time: Double, transform: CGAffineTransform, scale s: CGFloat) -> CIImage {
        var result = CIImage.empty()
        let life = 0.5
        for click in clicks where time >= click.t && time - click.t < life {
            let q = (time - click.t) / life
            let eased = 1 - pow(1 - q, 3)
            let at = CGPoint(x: click.x, y: source.height - click.y).applying(transform)
            // Diameter in output pixels: from 10 to 46 points.
            let diameter = CGFloat(10 + 36 * eased) * screenScale * s
            let fit = diameter / ring.extent.width
            let alpha = CGFloat(pow(1 - q, 1.6) * 0.85)
            let placed = ring
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
                .transformed(by: CGAffineTransform(scaleX: fit, y: fit))
                .transformed(by: CGAffineTransform(translationX: at.x - diameter / 2, y: at.y - diameter / 2))
            result = placed.composited(over: result)
        }
        return result
    }

    /// The latest shortcut, as a label at the bottom, for a second and a half.
    private func caption(at time: Double) -> RecCaption? {
        captions.first { time >= $0.start && time < $0.end }
    }

    /// The caption line at the bottom, fading in and out.
    private func captionOverlay(at time: Double) -> CIImage? {
        guard let line = caption(at: time), let image = captionImages[line.id] else { return nil }
        let alpha = min(1, (time - line.start) / 0.12, (line.end - time) / 0.12)
        let at = CGPoint(x: (output.width - image.extent.width) / 2, y: max(content.minY, 0) + output.height * 0.05)
        return image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
            .transformed(by: CGAffineTransform(translationX: at.x, y: at.y))
    }

    private func keyOverlay(at time: Double, raised: Bool) -> CIImage? {
        guard let key = keys.last(where: { $0.t <= time && time - $0.t < 1.5 }), let image = keyImages[key.text] else { return nil }
        let age = time - key.t
        let alpha = min(1, age / 0.12, (1.5 - age) / 0.3)
        let lift = raised ? output.height * 0.13 : content.height * 0.06
        let at = CGPoint(x: content.midX - image.extent.width / 2, y: content.minY + lift + CGFloat(min(age / 0.12, 1) - 1) * 6 * k)
        return image
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
            .transformed(by: CGAffineTransform(translationX: at.x, y: at.y))
    }

    /// The camera in a circle (or a rounded square) in a corner, mirrored like a mirror, with a white rim.
    private func bubble(_ face: CIImage) -> CIImage? {
        let side = (output.height * CGFloat(style.cameraSize)).rounded()
        let edge = min(face.extent.width, face.extent.height)
        let square = face.cropped(to: CGRect(x: face.extent.midX - edge / 2, y: face.extent.midY - edge / 2, width: edge, height: edge))
        let fit = side / edge
        let margin = (output.width * 0.03).rounded()
        // Eight spots: the corners and the middle of each edge.
        let corner = style.cameraCorner
        let x: CGFloat = corner.hasSuffix("Right") || corner == "right" ? output.width - margin - side
            : corner.hasSuffix("Left") || corner == "left" ? margin : (output.width - side) / 2
        let y: CGFloat = corner.hasPrefix("top") ? output.height - margin - side
            : corner.hasPrefix("bottom") ? margin : (output.height - side) / 2
        let origin = CGPoint(x: x, y: y)
        let box = CGRect(origin: origin, size: CGSize(width: side, height: side))
        let mirrored = square
            .transformed(by: CGAffineTransform(translationX: -square.extent.minX, y: -square.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: style.cameraMirror ? -fit : fit, y: fit))
            .transformed(by: CGAffineTransform(translationX: style.cameraMirror ? box.maxX : box.minX, y: box.minY))
        let radius = side * CGFloat(min(max(style.cameraRoundness, 0), 0.5))
        func rounded(_ rect: CGRect, _ r: CGFloat, _ color: CIColor) -> CIImage? {
            let shape = CIFilter.roundedRectangleGenerator()
            shape.extent = rect
            shape.radius = Float(r)
            shape.color = color
            return shape.outputImage
        }
        guard let mask = rounded(box, radius, .white),
              let rim = rounded(box.insetBy(dx: -max(2, side * 0.015), dy: -max(2, side * 0.015)), radius + side * 0.015, .white) else { return nil }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = mirrored
        blend.backgroundImage = CIImage.empty()
        blend.maskImage = mask
        guard let face = blend.outputImage else { return nil }
        let shadow = (rounded(box.offsetBy(dx: 0, dy: -side * 0.03), radius, CIColor(red: 0, green: 0, blue: 0, alpha: 0.45)) ?? .empty())
            .applyingGaussianBlur(sigma: Double(side * 0.06))
        return face.composited(over: rim.composited(over: shadow))
    }

    // MARK: Images

    private static func arrow() -> (CIImage, RecCursor)? {
        let cursor = NSCursor.arrow
        guard let cg = cursor.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return (CIImage(cgImage: cg), RecCursor(file: "", width: cursor.image.size.width, height: cursor.image.size.height,
                                                 hotX: cursor.hotSpot.x, hotY: cursor.hotSpot.y))
    }

    /// White text on a rounded label of `fill`, `height` pixels tall.
    static func pill(_ text: String, height: CGFloat, fill: CGColor) -> CIImage {
        let font = CTFontCreateWithName("SF Pro Rounded Semibold" as CFString, height * 0.5, nil)
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1)] as [CFString: Any]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes as [NSAttributedString.Key: Any]))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let width = Int(bounds.width + height * 1.1), tall = Int(height)
        guard width > 0, tall > 0, let ctx = CGContext(data: nil, width: width, height: tall, bitsPerComponent: 8, bytesPerRow: 0,
                                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .empty() }
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: tall), cornerWidth: height * 0.3, cornerHeight: height * 0.3, transform: nil))
        ctx.setFillColor(fill)
        ctx.fillPath()
        ctx.textPosition = CGPoint(x: (CGFloat(width) - bounds.width) / 2 - bounds.minX, y: (CGFloat(tall) - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, ctx)
        return ctx.makeImage().map(CIImage.init(cgImage:)) ?? .empty()
    }

    /// A note's label (accent, white text) and its arrow, placed in an output-sized frame.
    private static func noteImage(_ note: RecNote, in size: CGSize, on video: CGRect, accent: CGColor) -> CIImage {
        let label = pill(note.text.isEmpty ? " " : note.text, height: size.height * 0.06, fill: accent)
        // Spots are 0…1 of the video (top-left origin), so they stay on what they point at whatever the frame.
        let spot = CGPoint(x: video.minX + note.x * video.width, y: video.minY + (1 - note.y) * video.height)
        var image = label.transformed(by: CGAffineTransform(translationX: spot.x - label.extent.width / 2, y: spot.y - label.extent.height / 2))
        guard note.arrow else { return image }
        let target = CGPoint(x: video.minX + note.toX * video.width, y: video.minY + (1 - note.toY) * video.height)
        // From the label's edge toward the target, tapered, with a soft shadow.
        let dx = target.x - spot.x, dy = target.y - spot.y, length = hypot(dx, dy)
        guard length > 20 else { return image }
        let startGap = min(label.extent.width, label.extent.height) * 0.55
        let from = CGPoint(x: spot.x + dx / length * startGap, y: spot.y + dy / length * startGap)
        let w = size.height * 0.006
        let box = CGRect(from: from, to: target).insetBy(dx: -w * 8, dy: -w * 8).integral
        guard box.width > 0, box.height > 0,
              let ctx = CGContext(data: nil, width: Int(box.width), height: Int(box.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        let a = CGPoint(x: from.x - box.minX, y: from.y - box.minY), b = CGPoint(x: target.x - box.minX, y: target.y - box.minY)
        let u = CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length), n = CGVector(dx: -u.dy, dy: u.dx)
        let head = w * 4.5, base = CGPoint(x: b.x - u.dx * head * 1.6, y: b.y - u.dy * head * 1.6)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: a.x + n.dx * w * 0.3, y: a.y + n.dy * w * 0.3))
        path.addLine(to: CGPoint(x: base.x + n.dx * w, y: base.y + n.dy * w))
        path.addLine(to: CGPoint(x: base.x + n.dx * head, y: base.y + n.dy * head))
        path.addLine(to: b)
        path.addLine(to: CGPoint(x: base.x - n.dx * head, y: base.y - n.dy * head))
        path.addLine(to: CGPoint(x: base.x - n.dx * w, y: base.y - n.dy * w))
        path.addLine(to: CGPoint(x: a.x - n.dx * w * 0.3, y: a.y - n.dy * w * 0.3))
        path.closeSubpath()
        ctx.setShadow(offset: CGSize(width: 0, height: -w), blur: w * 3, color: CGColor(gray: 0, alpha: 0.35))
        ctx.setFillColor(accent)
        ctx.setStrokeColor(accent)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(w * 0.6)
        ctx.addPath(path)
        ctx.drawPath(using: .fillStroke)
        if let arrow = ctx.makeImage() {
            image = image.composited(over: CIImage(cgImage: arrow).transformed(by: CGAffineTransform(translationX: box.minX, y: box.minY)))
        }
        return image
    }

    /// A dark rounded label with the shortcut in white, `height` pixels tall.
    private static func keyImage(_ text: String, height: CGFloat) -> CIImage {
        let font = CTFontCreateWithName("SF Pro Rounded Semibold" as CFString, height * 0.5, nil)
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1)] as [CFString: Any]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes as [NSAttributedString.Key: Any]))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let width = Int(bounds.width + height * 0.9), tall = Int(height)
        guard width > 0, tall > 0, let ctx = CGContext(data: nil, width: width, height: tall, bitsPerComponent: 8, bytesPerRow: 0,
                                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .empty() }
        let box = CGRect(x: 0, y: 0, width: width, height: tall)
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: height * 0.28, cornerHeight: height * 0.28, transform: nil))
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.82))
        ctx.fillPath()
        ctx.textPosition = CGPoint(x: (CGFloat(width) - bounds.width) / 2 - bounds.minX, y: (CGFloat(tall) - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, ctx)
        return ctx.makeImage().map(CIImage.init(cgImage:)) ?? .empty()
    }

    /// A white ring with a dark edge, so it shows on light and dark screens.
    private static func ringImage() -> CIImage {
        let size = 160
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return CIImage.empty() }
        let box = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 10, dy: 10)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.35))
        ctx.setLineWidth(16)
        ctx.strokeEllipse(in: box)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(9)
        ctx.strokeEllipse(in: box)
        return ctx.makeImage().map(CIImage.init(cgImage:)) ?? CIImage.empty()
    }

    // MARK: AVFoundation

    /// The recording put together for playing and exporting: the screen, its sound, the camera (lined up), with the
    /// speed-ups applied to all of them.
    struct Built: @unchecked Sendable {
        let asset: AVMutableComposition
        let screen: CMPersistentTrackID
        let camera: CMPersistentTrackID?
        /// The Mac's sound, the microphone, and the added click/key sounds.
        var sound: CMPersistentTrackID?
        var mic: CMPersistentTrackID?
        var effects: CMPersistentTrackID?

        /// Each track at its level from the style.
        func audioMix(_ style: RecStyle) -> AVAudioMix {
            let mix = AVMutableAudioMix()
            mix.inputParameters = [(sound, style.soundVolume), (mic, style.micVolume), (effects, style.effectsVolume)].compactMap { id, volume in
                guard let id else { return nil }
                let parameters = AVMutableAudioMixInputParameters()
                parameters.trackID = id
                parameters.setVolume(Float(volume), at: .zero)
                return parameters
            }
            return mix
        }
    }

    /// `segments`: speed-ups and cuts (`RecEdit.timeSegments`); `clickSound` adds a click on every click.
    static func build(meta: RecMeta, speeds: [RecSpeed], clickSound: Bool = false, keySound: Bool = false) async -> Built? {
        let source = AVURLAsset(url: RecStore.video(for: meta.id))
        guard let duration = try? await source.load(.duration), let video = try? await source.loadTracks(withMediaType: .video).first else { return nil }
        let composition = AVMutableComposition()
        let all = CMTimeRange(start: .zero, duration: duration)
        guard let screen = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              (try? screen.insertTimeRange(all, of: video, at: .zero)) != nil else { return nil }
        var soundID: CMPersistentTrackID?, micID: CMPersistentTrackID?
        for audio in (try? await source.loadTracks(withMediaType: .audio)) ?? [] {
            guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
                  (try? track.insertTimeRange(all, of: audio, at: .zero)) != nil else { continue }
            // The microphone is written in mono, the Mac's sound in stereo.
            let formats = (try? await audio.load(.formatDescriptions)) ?? []
            let channels = formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame } ?? 2
            if channels == 1 { micID = track.trackID } else { soundID = track.trackID }
        }
        var cameraID: CMPersistentTrackID?
        if let offset = meta.cameraOffset {
            let camera = AVURLAsset(url: RecStore.folder(for: meta.id).appendingPathComponent("camera.mov"))
            if let face = try? await camera.loadTracks(withMediaType: .video).first, let length = try? await camera.load(.duration),
               let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                // The camera started `offset` seconds after the screen (or before, when negative).
                let skip = max(0, -offset), at = max(0, offset)
                let span = min(length.seconds - skip, duration.seconds - at)
                if span > 0 {
                    let range = CMTimeRange(start: CMTime(seconds: skip, preferredTimescale: 600), duration: CMTime(seconds: span, preferredTimescale: 600))
                    if (try? track.insertTimeRange(range, of: face, at: CMTime(seconds: at, preferredTimescale: 600))) != nil { cameraID = track.trackID }
                }
            }
        }
        // Latest first, so earlier times stay where they were. A cut is removed, a speed-up squeezed.
        for speed in speeds.sorted(by: { $0.start > $1.start }) where speed.rate > 1 && speed.end > speed.start {
            let range = CMTimeRange(start: CMTime(seconds: speed.start, preferredTimescale: 6000),
                                    end: CMTime(seconds: min(speed.end, duration.seconds), preferredTimescale: 6000))
            if speed.rate.isInfinite {
                composition.removeTimeRange(range)
            } else {
                composition.scaleTimeRange(range, toDuration: CMTime(seconds: range.duration.seconds / speed.rate, preferredTimescale: 6000))
            }
        }
        // Click and key sounds on a track of their own, added after the speed-ups at the moments they land in the
        // result, so they stay crisp at normal speed even inside a faster part (and drop out with a cut).
        let map = RecTimeMap(speeds, duration: duration.seconds)
        let playedLength = composition.duration.seconds
        var effectsID: CMPersistentTrackID?
        var events: [(Double, URL)] = []
        if clickSound, let click = RecClickSound.url(.click) { events += meta.track.clicks.map { ($0.t, click) } }
        if keySound {
            let kinds: [RecClickSound.Kind] = [.key, .delete, .modifier]
            for (i, t) in meta.track.typing.enumerated() {
                let kind = i < meta.track.typingKinds.count ? kinds[min(max(meta.track.typingKinds[i], 0), 2)] : .key
                if let url = RecClickSound.url(kind) { events.append((t, url)) }
            }
            for key in meta.track.keys {
                if let url = RecClickSound.url(key.text == "↩" || key.text == "⇥" ? .modifier : .key) { events.append((key.t, url)) }
            }
        }
        if !events.isEmpty, let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            // The assets are kept alive until the inserts are done: a track whose asset is gone inserts nothing.
            var sounds: [URL: (AVURLAsset, AVAssetTrack, CMTimeRange)] = [:]
            for url in Set(events.map(\.1)) {
                let asset = AVURLAsset(url: url)
                if let audio = try? await asset.loadTracks(withMediaType: .audio).first, let range = try? await audio.load(.timeRange) {
                    sounds[url] = (asset, audio, range)
                }
            }
            var free = 0.0
            let placed = events.compactMap { time, url -> (Double, URL)? in
                if map.speeds.contains(where: { $0.rate.isInfinite && time >= $0.start && time < $0.end }) { return nil }
                return (map.played(time), url)
            }
            for (time, url) in placed.sorted(by: { $0.0 < $1.0 }) {
                guard let (_, audio, range) = sounds[url], time >= free, time + range.duration.seconds < playedLength else { continue }
                do {
                    try track.insertTimeRange(range, of: audio, at: CMTime(seconds: time, preferredTimescale: 48_000))
                    free = time + range.duration.seconds
                } catch {
                    ShotLog.write("sound insert failed: \(error)")
                }
            }
            withExtendedLifetime(sounds) {}
            effectsID = track.trackID
        }
        return Built(asset: composition, screen: screen.trackID, camera: cameraID, sound: soundID, mic: micID, effects: effectsID)
    }

    /// A video composition that draws every frame through this plan, 60 a second (also while the screen was still).
    func composition(for built: Built) -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.customVideoCompositorClass = RecCompositor.self
        composition.renderSize = output
        composition.frameDuration = CMTime(value: 1, timescale: 60)
        composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
        composition.instructions = [RecInstruction(range: CMTimeRange(start: .zero, duration: built.asset.duration),
                                                   screen: built.screen, camera: built.camera, plan: self)]
        return composition
    }
}

/// Recording time ↔ played time once stretches are sped up.
struct RecTimeMap: Sendable {
    let speeds: [RecSpeed]

    init(_ speeds: [RecSpeed], duration: Double) {
        var kept: [RecSpeed] = []
        for speed in speeds.filter({ $0.rate > 1 && $0.end > $0.start }).sorted(by: { $0.start < $1.start }) {
            var speed = RecSpeed(id: speed.id, start: max(0, speed.start, kept.last?.end ?? 0), end: min(speed.end, duration), rate: speed.rate)
            if speed.end > speed.start { kept.append(speed) } else { speed.end = speed.start }
        }
        self.speeds = kept
    }

    /// Recording seconds → seconds in the result.
    func played(_ t: Double) -> Double {
        var result = t
        for speed in speeds where speed.start < t {
            result -= (min(t, speed.end) - speed.start) * (1 - 1 / speed.rate)
        }
        return result
    }

    /// Seconds in the result → recording seconds.
    func source(_ played: Double) -> Double {
        var saved = 0.0
        for speed in speeds {
            let start = speed.start - saved
            if played < start { return played + saved }
            let end = start + (speed.end - speed.start) / speed.rate
            if played < end { return speed.start + (played - start) * speed.rate }
            saved += (speed.end - speed.start) * (1 - 1 / speed.rate)
        }
        return played + saved
    }
}

/// Tells the compositor which tracks to read and how to draw them.
final class RecInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let screen: CMPersistentTrackID
    let camera: CMPersistentTrackID?
    let plan: RecPlan

    init(range: CMTimeRange, screen: CMPersistentTrackID, camera: CMPersistentTrackID?, plan: RecPlan) {
        timeRange = range
        self.screen = screen
        self.camera = camera
        self.plan = plan
        requiredSourceTrackIDs = ([screen] + (camera.map { [$0] } ?? [])).map { NSNumber(value: $0) }
    }
}

/// Draws each frame with Core Image on the GPU, for the player, the export and the GIF alike.
final class RecCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    /// One Metal-backed context for every frame; the frames stay in GPU memory (IOSurface) from the decoder to the screen.
    private static let context: CIContext = {
        let options: [CIContextOption: Any] = [.cacheIntermediates: false, .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                               .workingFormat: CIFormat.RGBAh, .name: "Nabiz.Rec"]
        if let device = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: device, options: options) }
        return CIContext(options: options)
    }()
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    private static let buffers: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: String](),
        kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    let sourcePixelBufferAttributes: [String: any Sendable]? = RecCompositor.buffers
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = RecCompositor.buffers

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    /// The last screen frame seen: the sound can run a moment past the last video frame, and those moments show it.
    private let lock = NSLock()
    private var lastScreen: CVPixelBuffer?

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? RecInstruction,
              let output = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "Nabiz.Rec", code: 1))
            return
        }
        let screen: CVPixelBuffer
        if let frame = request.sourceFrame(byTrackID: instruction.screen) {
            screen = frame
            lock.withLock { lastScreen = frame }
        } else if let last = lock.withLock({ lastScreen }) {
            screen = last
        } else {
            request.finish(with: NSError(domain: "Nabiz.Rec", code: 2))
            return
        }
        let face = instruction.camera.flatMap { request.sourceFrame(byTrackID: $0) }.map { CIImage(cvPixelBuffer: $0) }
        let plan = instruction.plan
        let image = plan.frame(source: CIImage(cvPixelBuffer: screen), camera: face, time: request.compositionTime.seconds)
        Self.context.render(image, to: output, bounds: CGRect(origin: .zero, size: plan.output), colorSpace: Self.space)
        request.finish(withComposedVideoFrame: output)
    }
}
