import AppKit
import UniformTypeIdentifiers

/// Draws a screenshot and its marks. The canvas and the export use the same code, so what you see is what you get.
/// Every function draws into a y-down context measured in image points.
@MainActor
enum ShotRenderer {
    /// The whole document: frame, image, hidden regions, spotlight, then the marks in the order they were made.
    /// `device` is device pixels per image point (for shadow sizes, which ignore the transform).
    static func draw(_ doc: ShotDocument, in ctx: CGContext, device: CGFloat) {
        let content = doc.tool == .crop ? doc.bounds : doc.contentRect
        let framed = doc.background.enabled && doc.tool != .crop
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        defer { NSGraphicsContext.current = previous }

        ctx.saveGState()
        if framed {
            drawFrame(doc.background, document: doc.documentRect, content: content, in: ctx, device: device)
            ctx.addPath(CGPath(roundedRect: content, cornerWidth: radius(doc.background, content),
                               cornerHeight: radius(doc.background, content), transform: nil))
            ctx.clip()
        } else {
            ctx.clip(to: content)
        }
        drawImage(doc.image, bounds: doc.bounds, in: ctx)
        for item in doc.items where item.kind == .blur {
            if let hidden = doc.hidden(pixelate: item.style == 1) {
                ctx.saveGState()
                ctx.clip(to: item.rect)
                drawImage(hidden, bounds: doc.bounds, in: ctx)
                ctx.restoreGState()
            }
        }
        let spots = doc.items.filter { $0.kind == .spotlight && $0.rect.width > 1 && $0.rect.height > 1 }
        if !spots.isEmpty {
            let path = CGMutablePath()
            path.addRect(content)
            for spot in spots {
                let r = min(10, min(spot.rect.width, spot.rect.height) / 4)
                path.addRoundedRect(in: spot.rect, cornerWidth: r, cornerHeight: r)
            }
            ctx.addPath(path)
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.55))
            ctx.fillPath(using: .evenOdd)
        }
        ctx.restoreGState()

        ctx.saveGState()
        ctx.clip(to: doc.documentRect)
        for item in doc.items where item.kind != .blur && item.kind != .spotlight && item.id != doc.editingText {
            drawItem(item, number: item.kind == .counter ? doc.number(of: item) : 0, in: ctx, device: device)
        }
        ctx.restoreGState()
    }

    private static func radius(_ background: ShotBackground, _ content: CGRect) -> CGFloat {
        min(background.radius, min(content.width, content.height) / 2)
    }

    /// A CGImage in a y-down context: flipped around its own bounds.
    static func drawImage(_ image: CGImage, bounds: CGRect, in ctx: CGContext) {
        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: bounds.size))
        ctx.restoreGState()
    }

    private static func drawFrame(_ background: ShotBackground, document: CGRect, content: CGRect, in ctx: CGContext, device: CGFloat) {
        let (from, to) = ShotBackground.presets[background.preset]
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [from.cgColor, to.cgColor] as CFArray,
                                     locations: [0, 1]) {
            ctx.saveGState()
            ctx.clip(to: document)
            ctx.drawLinearGradient(gradient, start: document.origin, end: CGPoint(x: document.maxX, y: document.maxY), options: [])
            ctx.restoreGState()
        }
        guard background.shadow else { return }
        let r = radius(background, content)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * device), blur: 36 * device, color: CGColor(gray: 0, alpha: 0.38))
        ctx.addPath(CGPath(roundedRect: content, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // MARK: Marks

    static func drawItem(_ item: ShotItem, number: Int, in ctx: CGContext, device: CGFloat) {
        let w = item.size.stroke
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(item.ink.cgColor)
        ctx.setFillColor(item.ink.cgColor)
        // A soft shadow keeps marks readable on busy screenshots, light or dark.
        let shadow = { ctx.setShadow(offset: CGSize(width: 0, height: -1 * device), blur: 3 * device, color: CGColor(gray: 0, alpha: 0.35)) }

        switch item.kind {
        case .arrow:
            shadow()
            ctx.addPath(arrowPath(item))
            ctx.fillPath()
            if item.style != 0 {
                ctx.setLineWidth(w)
                ctx.addPath(arrowShaft(item))
                ctx.strokePath()
            }
        case .line:
            shadow()
            ctx.setLineWidth(w)
            ctx.move(to: item.start)
            ctx.addLine(to: item.end)
            ctx.strokePath()
        case .rect, .ellipse:
            shadow()
            let rect = item.rect
            let path = item.kind == .rect
                ? CGPath(roundedRect: rect, cornerWidth: min(w * 1.2, rect.width / 2), cornerHeight: min(w * 1.2, rect.height / 2), transform: nil)
                : CGPath(ellipseIn: rect, transform: nil)
            ctx.addPath(path)
            if item.style == 1 { ctx.fillPath() } else { ctx.setLineWidth(w); ctx.strokePath() }
        case .pen:
            shadow()
            ctx.setLineWidth(w)
            ctx.addPath(penPath(item.points))
            ctx.strokePath()
        case .highlight:
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(item.ink.cgColor.copy(alpha: 0.4) ?? item.ink.cgColor)
            ctx.fill(item.rect)
        case .text:
            drawText(item)
        case .counter:
            shadow()
            let r = item.size.counterRadius
            let circle = CGRect(x: item.start.x - r, y: item.start.y - r, width: r * 2, height: r * 2)
            ctx.fillEllipse(in: circle)
            ctx.setShadow(offset: .zero, blur: 0)
            ctx.setStrokeColor(item.ink.luminance > 0.85 ? CGColor(gray: 0.15, alpha: 1) : CGColor(gray: 1, alpha: 1))
            ctx.setLineWidth(max(1.5, r * 0.14))
            ctx.strokeEllipse(in: circle.insetBy(dx: r * 0.07, dy: r * 0.07))
            let font = rounded(size: r * (number > 9 ? 0.95 : 1.15), weight: .bold)
            let label = NSAttributedString(string: "\(number)", attributes: [.font: font, .foregroundColor: item.ink.contrast.nsColor])
            let size = label.size()
            label.draw(at: CGPoint(x: item.start.x - size.width / 2, y: item.start.y - size.height / 2))
        case .blur, .spotlight:
            break
        }
    }

    /// The tapered arrow is one filled shape: thin at the tail, wider into a swept-back head. The line style is a
    /// filled head with the shaft stroked separately (`arrowShaft`). Both shrink for short arrows.
    static func arrowPath(_ item: ShotItem) -> CGPath {
        let path = CGMutablePath()
        let p0 = item.start, p1 = item.end
        let length = p0.distance(to: p1)
        guard length > 0.5 else { return path }
        let w = item.size.stroke
        let u = CGVector(dx: (p1.x - p0.x) / length, dy: (p1.y - p0.y) / length)
        let n = CGVector(dx: -u.dy, dy: u.dx)
        func at(_ base: CGPoint, along: CGFloat, side: CGFloat) -> CGPoint {
            CGPoint(x: base.x + u.dx * along + n.dx * side, y: base.y + u.dy * along + n.dy * side)
        }
        var headHalf = max(w * 2.3, 7)
        var headLength = headHalf * 1.75
        var shaftHalf = w * 0.72
        let limit = length * (item.style == 2 ? 0.4 : 0.5)
        if headLength > limit {
            let k = limit / headLength
            headHalf *= k; headLength *= k; shaftHalf *= max(k, 0.5)
        }
        if item.style == 0 {
            let tailHalf = max(w * 0.18, 0.6)
            let base = at(p1, along: -headLength, side: 0)
            path.move(to: at(p0, along: 0, side: tailHalf))
            path.addLine(to: at(base, along: headLength * 0.12, side: shaftHalf))
            path.addLine(to: at(base, along: -headLength * 0.1, side: headHalf))
            path.addQuadCurve(to: p1, control: at(base, along: headLength * 0.55, side: headHalf * 0.55))
            path.addQuadCurve(to: at(base, along: -headLength * 0.1, side: -headHalf), control: at(base, along: headLength * 0.55, side: -headHalf * 0.55))
            path.addLine(to: at(base, along: headLength * 0.12, side: -shaftHalf))
            path.addLine(to: at(p0, along: 0, side: -tailHalf))
            path.addArc(center: p0, radius: tailHalf, startAngle: atan2(-n.dy, -n.dx), endAngle: atan2(n.dy, n.dx), clockwise: false)
            path.closeSubpath()
            return path
        }
        func head(tip: CGPoint, back: CGVector) {
            let base = CGPoint(x: tip.x + back.dx * headLength, y: tip.y + back.dy * headLength)
            let side = CGVector(dx: -back.dy, dy: back.dx)
            path.move(to: tip)
            path.addLine(to: CGPoint(x: base.x + side.dx * headHalf, y: base.y + side.dy * headHalf))
            path.addQuadCurve(to: CGPoint(x: base.x - side.dx * headHalf, y: base.y - side.dy * headHalf),
                              control: CGPoint(x: tip.x + back.dx * headLength * 0.7, y: tip.y + back.dy * headLength * 0.7))
            path.closeSubpath()
        }
        head(tip: p1, back: CGVector(dx: -u.dx, dy: -u.dy))
        if item.style == 2 { head(tip: p0, back: u) }
        return path
    }

    /// The stroked line of a line-style arrow, stopping inside the head so the round cap never pokes through.
    static func arrowShaft(_ item: ShotItem) -> CGPath {
        let path = CGMutablePath()
        let p0 = item.start, p1 = item.end
        let length = p0.distance(to: p1)
        guard length > 0.5 else { return path }
        let inset = min(max(item.size.stroke * 2.3, 7) * 1.75 * 0.6, length * 0.3)
        let u = CGVector(dx: (p1.x - p0.x) / length, dy: (p1.y - p0.y) / length)
        path.move(to: item.style == 2 ? p0.moved(CGVector(dx: u.dx * inset, dy: u.dy * inset)) : p0)
        path.addLine(to: p1.moved(CGVector(dx: -u.dx * inset, dy: -u.dy * inset)))
        return path
    }

    /// A freehand line smoothed through the midpoints of what was drawn.
    static func penPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 { path.addLine(to: first); return path }
        if points.count == 2 { path.addLine(to: points[1]); return path }
        for i in 1..<points.count - 1 {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    // MARK: Text

    static func rounded(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
    }

    static func textFont(_ item: ShotItem) -> NSFont { rounded(size: item.size.fontSize, weight: .bold) }

    /// Room around a label's text.
    static func labelPadding(_ item: ShotItem) -> CGSize {
        item.style == 1 ? CGSize(width: item.size.fontSize * 0.45, height: item.size.fontSize * 0.22) : CGSize(width: 2, height: 1)
    }

    /// Where a text mark's box sits, from its top-left corner.
    static func textFrame(_ item: ShotItem) -> CGRect {
        let text = item.text.isEmpty ? " " : item.text
        let size = NSAttributedString(string: text, attributes: [.font: textFont(item)])
            .boundingRect(with: CGSize(width: 4000, height: 4000), options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        let pad = labelPadding(item)
        return CGRect(x: item.start.x, y: item.start.y, width: ceil(size.width) + pad.width * 2, height: ceil(size.height) + pad.height * 2)
    }

    private static func drawText(_ item: ShotItem) {
        guard !item.text.isEmpty else { return }
        let frame = textFrame(item)
        let pad = labelPadding(item)
        let font = textFont(item)
        let origin = CGRect(x: frame.minX + pad.width, y: frame.minY + pad.height,
                            width: frame.width - pad.width * 2, height: frame.height - pad.height * 2)
        if item.style == 1 {
            let label = NSBezierPath(roundedRect: frame, xRadius: frame.height * 0.28, yRadius: frame.height * 0.28)
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            item.ink.nsColor.setFill()
            label.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSAttributedString(string: item.text, attributes: [.font: font, .foregroundColor: item.ink.contrast.nsColor])
                .draw(with: origin, options: [.usesLineFragmentOrigin, .usesFontLeading])
            return
        }
        // Outlined: a thick stroke in the contrasting colour under the filled text, readable on anything.
        NSAttributedString(string: item.text, attributes: [.font: font, .strokeColor: item.ink.contrast.nsColor.withAlphaComponent(0.9),
                                                           .strokeWidth: 16])
            .draw(with: origin, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSAttributedString(string: item.text, attributes: [.font: font, .foregroundColor: item.ink.nsColor])
            .draw(with: origin, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    // MARK: Hit testing

    /// The box a mark covers, for selection outlines.
    static func frame(_ item: ShotItem) -> CGRect {
        switch item.kind {
        case .text: return textFrame(item)
        case .counter:
            let r = item.size.counterRadius
            return CGRect(x: item.start.x - r, y: item.start.y - r, width: r * 2, height: r * 2)
        case .pen:
            guard let first = item.points.first else { return .zero }
            var box = CGRect(origin: first, size: .zero)
            for point in item.points { box = box.union(CGRect(origin: point, size: .zero)) }
            return box.insetBy(dx: -item.size.stroke / 2, dy: -item.size.stroke / 2)
        default:
            return item.rect
        }
    }

    /// Whether a click at `point` lands on the mark; `slop` is how far off it may be, in image points.
    static func hit(_ item: ShotItem, _ point: CGPoint, slop: CGFloat) -> Bool {
        let reach = slop + item.size.stroke / 2
        switch item.kind {
        case .arrow:
            return arrowPath(item).contains(point) || distance(point, item.start, item.end) <= reach
        case .line:
            return distance(point, item.start, item.end) <= reach
        case .rect, .ellipse:
            let rect = item.rect
            if item.style == 1 || rect.width < reach * 4 || rect.height < reach * 4 { return rect.insetBy(dx: -reach, dy: -reach).contains(point) }
            let path = item.kind == .rect ? CGPath(rect: rect, transform: nil) : CGPath(ellipseIn: rect, transform: nil)
            return path.copy(strokingWithWidth: reach * 2, lineCap: .round, lineJoin: .round, miterLimit: 1).contains(point)
        case .pen:
            guard item.points.count > 1 else { return item.points.first.map { $0.distance(to: point) <= reach } ?? false }
            return zip(item.points, item.points.dropFirst()).contains { distance(point, $0, $1) <= reach }
        case .highlight, .blur, .spotlight, .text:
            return frame(item).insetBy(dx: -slop, dy: -slop).contains(point)
        case .counter:
            return point.distance(to: item.start) <= item.size.counterRadius + slop
        }
    }

    /// Distance from a point to a line segment.
    static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return p.distance(to: a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return p.distance(to: CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    // MARK: Export

    /// The finished image at full resolution: crop, frame and every mark flattened in.
    static func export(_ doc: ShotDocument) -> CGImage? {
        let wasCropping = doc.tool == .crop
        if wasCropping { doc.tool = .select }
        let rect = doc.documentRect
        let width = Int((rect.width * doc.scale).rounded()), height = Int((rect.height * doc.scale).rounded())
        guard width > 0, height > 0 else { return nil }
        let space = doc.image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.scaleBy(x: doc.scale, y: doc.scale)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        let selection = doc.selection
        doc.selection = nil
        draw(doc, in: ctx, device: doc.scale)
        doc.selection = selection
        return ctx.makeImage()
    }

    /// The export as an NSImage sized in points, so it pastes at its real size.
    static func exportImage(_ doc: ShotDocument) -> NSImage? {
        guard let cg = export(doc) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / doc.scale, height: CGFloat(cg.height) / doc.scale))
    }

    /// Encoded as png, jpg, heic or tiff, with the Retina density recorded so it opens at its real size.
    static func encode(_ image: CGImage, type: String, scale: CGFloat) -> Data? {
        let uti: UTType = switch type {
        case "jpg", "jpeg": .jpeg
        case "heic": .heic
        case "tiff": .tiff
        default: .png
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, uti.identifier as CFString, 1, nil) else { return nil }
        var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale]
        if uti != .png { properties[kCGImageDestinationLossyCompressionQuality] = 0.92 }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
