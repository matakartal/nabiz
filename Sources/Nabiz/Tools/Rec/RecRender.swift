import AppKit
import AVFoundation
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
    private let zoom: [Double]
    private let focus: [CGPoint]
    private let pointer: [CGPoint]
    private let clicks: [RecTrack.Point]
    private let shapes: [RecTrack.Shape]
    private let cursors: [(image: CIImage, info: RecCursor)]
    private let base: CIImage
    private let mask: CIImage?
    private let ring: CIImage

    /// `maxWidth` caps the output width (preview, 1080p, 4K); nil keeps the recording's full size.
    init(meta: RecMeta, edit: RecEdit, maxWidth: CGFloat?) {
        let style = edit.style
        self.style = style
        source = CGSize(width: meta.width, height: meta.height)
        screenScale = CGFloat(meta.scale)
        let pad = (CGFloat(style.padding) * source.width).rounded()
        let canvas = CGSize(width: source.width + pad * 2, height: source.height + pad * 2)
        let fit = maxWidth.map { min(1, $0 / canvas.width) } ?? 1
        // Even pixel sizes for the encoder.
        output = CGSize(width: (canvas.width * fit / 2).rounded() * 2, height: (canvas.height * fit / 2).rounded() * 2)
        k = output.width / canvas.width
        content = CGRect(x: pad * k, y: pad * k, width: source.width * k, height: source.height * k)

        let steps = max(2, Int(meta.duration * fps) + 2)
        let (zoom, focus) = Self.camera(edit: edit, track: meta.track, source: source, steps: steps, fps: fps)
        self.zoom = zoom
        self.focus = focus
        pointer = Self.pointer(track: meta.track, smooth: style.smoothCursor, steps: steps, fps: fps)
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
        if pad > 0 {
            let (from, to) = ShotBackground.presets[min(max(style.background, 0), ShotBackground.presets.count - 1)]
            let gradient = CIFilter.linearGradient()
            gradient.point0 = CGPoint(x: 0, y: output.height)
            gradient.point1 = CGPoint(x: output.width, y: 0)
            gradient.color0 = CIColor(cgColor: from.cgColor)
            gradient.color1 = CIColor(cgColor: to.cgColor)
            var background = gradient.outputImage?.cropped(to: extent) ?? CIImage(color: .black).cropped(to: extent)
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

    func frame(source frame: CIImage, time: Double) -> CIImage {
        let (z, f) = camera(at: time)
        let transform = self.transform(zoom: z, focus: f)
        let video = frame.transformed(by: transform).cropped(to: content)
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
        return image.cropped(to: CGRect(origin: .zero, size: output))
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

    func camera(at time: Double) -> (Double, CGPoint) {
        let z = sample(zoom, at: time) { $0 + ($1 - $0) * $2 }
        let f = sample(focus, at: time) { a, b, u in CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u) }
        return (z, f)
    }

    /// The pointer image at its spot, with a soft shadow, sized with the zoom.
    private func cursor(at time: Double, transform: CGAffineTransform, scale s: CGFloat) -> CIImage? {
        guard !cursors.isEmpty else { return nil }
        let p = sample(pointer, at: time) { a, b, u in CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u) }
        let at = CGPoint(x: p.x, y: source.height - p.y).applying(transform)
        guard content.insetBy(dx: -40, dy: -40).contains(at) else { return nil }
        var index = 0
        if let shape = shapes.last(where: { $0.t <= time }) { index = min(shape.index, cursors.count - 1) }
        let (image, info) = cursors[index]
        // Output pixels per screen point: source pixels per point × output pixels per source pixel.
        let width = CGFloat(info.width) * screenScale * s * CGFloat(style.cursorSize)
        let fit = width / max(image.extent.width, 1)
        let sized = image.transformed(by: CGAffineTransform(scaleX: fit, y: fit))
        let origin = CGPoint(x: at.x - CGFloat(info.hotX) * width / CGFloat(info.width),
                             y: at.y - (CGFloat(info.height) - CGFloat(info.hotY)) * width / CGFloat(info.width))
        let placed = sized.transformed(by: CGAffineTransform(translationX: origin.x - sized.extent.minX, y: origin.y - sized.extent.minY))
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

    // MARK: Motion

    /// Zoom and camera centre at each step: critically damped springs (no wobble), slower for panning than for
    /// zooming, chasing the zoom segments and the smoothed pointer.
    private static func camera(edit: RecEdit, track: RecTrack, source: CGSize, steps: Int, fps: Double) -> ([Double], [CGPoint]) {
        let dt = 1 / fps
        let centre = CGPoint(x: source.width / 2, y: source.height / 2)
        let raw = pointer(track: track, smooth: true, steps: steps, fps: fps)
        var zooms = [Double](repeating: 1, count: steps)
        var focuses = [CGPoint](repeating: centre, count: steps)
        var z = 1.0, zv = 0.0
        var f = centre, fv = CGVector.zero
        // Zoom: ~0.45 s to settle, no overshoot. Pan: softer, and only when the pointer leaves the middle of the view
        // (a box 50% × 70% of what's visible), so the picture doesn't drift with every small move.
        let zoomOmega = 8.0, panOmega = 4.0
        var aim = centre
        // Start already aimed at the first zoom's pointer so it doesn't sweep in from the middle.
        if let first = edit.zooms.first { f = raw[min(Int(first.start * fps), steps - 1)]; aim = f }
        for i in 0..<steps {
            let t = Double(i) * dt
            // Look slightly ahead so the zoom is under way when the click happens.
            let segment = edit.zooms.first { t + 0.15 >= $0.start && t < $0.end }
            let target = segment?.scale ?? 1
            let a = zoomOmega * zoomOmega * (target - z) - 2 * zoomOmega * zv
            zv += a * dt
            z += zv * dt
            if segment != nil {
                let visible = CGSize(width: source.width / max(z, 1), height: source.height / max(z, 1))
                let p = raw[i]
                if aim == centre || abs(p.x - aim.x) > visible.width * 0.25 || abs(p.y - aim.y) > visible.height * 0.35 { aim = p }
            } else if z < 1.02 {
                aim = centre
            }
            let ax = panOmega * panOmega * (aim.x - f.x) - 2 * panOmega * fv.dx
            let ay = panOmega * panOmega * (aim.y - f.y) - 2 * panOmega * fv.dy
            fv.dx += ax * dt
            fv.dy += ay * dt
            f.x += fv.dx * dt
            f.y += fv.dy * dt
            zooms[i] = max(1, z)
            focuses[i] = f
        }
        return (zooms, focuses)
    }

    /// The pointer at each step: the recorded path, or the same followed by a stiff critically damped spring, which
    /// takes out the jitter and the jumps without lagging noticeably.
    private static func pointer(track: RecTrack, smooth: Bool, steps: Int, fps: Double) -> [CGPoint] {
        let moves = track.moves
        guard let first = moves.first else { return [CGPoint](repeating: .zero, count: steps) }
        var result = [CGPoint](repeating: .zero, count: steps)
        var j = 0
        let dt = 1 / fps
        var p = CGPoint(x: first.x, y: first.y), v = CGVector.zero
        let omega = 22.0
        // A critically damped spring trails by about 2/ω; reading the path that far ahead cancels it.
        let lead = smooth ? 1.6 / omega : 0
        let clicks = track.clicks.map(\.t).sorted()
        var c = 0
        for i in 0..<steps {
            let t = Double(i) * dt + lead
            while j + 1 < moves.count && moves[j + 1].t <= t { j += 1 }
            let a = moves[j]
            var raw = CGPoint(x: a.x, y: a.y)
            if j + 1 < moves.count {
                let b = moves[j + 1]
                let u = b.t > a.t ? min(max((t - a.t) / (b.t - a.t), 0), 1) : 0
                raw = CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
            }
            while c + 1 < clicks.count && clicks[c] < t - lead - 0.3 { c += 1 }
            // Around a click the pointer is exactly where it clicked: the spring stiffens there.
            let nearClick = c < clicks.count && abs(clicks[c] - (t - lead)) < 0.18
            if smooth && nearClick {
                let w = omega * 2.2
                let ax = w * w * (raw.x - p.x) - 2 * w * v.dx
                let ay = w * w * (raw.y - p.y) - 2 * w * v.dy
                v.dx += ax * dt
                v.dy += ay * dt
                p.x += v.dx * dt
                p.y += v.dy * dt
            } else if smooth {
                let ax = omega * omega * (raw.x - p.x) - 2 * omega * v.dx
                let ay = omega * omega * (raw.y - p.y) - 2 * omega * v.dy
                v.dx += ax * dt
                v.dy += ay * dt
                p.x += v.dx * dt
                p.y += v.dy * dt
            } else {
                p = raw
            }
            result[i] = p
        }
        return result
    }

    // MARK: Images

    private static func arrow() -> (CIImage, RecCursor)? {
        let cursor = NSCursor.arrow
        guard let cg = cursor.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return (CIImage(cgImage: cg), RecCursor(file: "", width: cursor.image.size.width, height: cursor.image.size.height,
                                                 hotX: cursor.hotSpot.x, hotY: cursor.hotSpot.y))
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

    /// A video composition that draws every frame through this plan.
    func composition(for asset: AVAsset) -> AVMutableVideoComposition {
        let plan = self
        let composition = AVMutableVideoComposition(asset: asset) { request in
            request.finish(with: plan.frame(source: request.sourceImage, time: request.compositionTime.seconds), context: nil)
        }
        composition.renderSize = output
        composition.frameDuration = CMTime(value: 1, timescale: 60)
        // ScreenCaptureKit sends no frames while the screen is still; without this the zoom and the pointer
        // would freeze until the next change. Frames now come at a steady 60 a second.
        composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
        return composition
    }
}
