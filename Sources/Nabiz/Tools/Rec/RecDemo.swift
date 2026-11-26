import AppKit
import CoreImage

/// For `--snapshot out.png --rec-frames picture.png`: a made-up recording over a picture (the pointer circles,
/// clicks twice), drawn at a few moments side by side, to check the zoom, pointer and frame without recording.
@MainActor
enum RecDemo {
    static func meta(width: Int, height: Int) -> RecMeta {
        var track = RecTrack()
        for i in 0...360 {
            let t = Double(i) / 60
            let angle = t * 1.4
            track.moves.append(RecTrack.Point(t: t, x: Double(width) * (0.5 + 0.3 * cos(angle)), y: Double(height) * (0.5 + 0.25 * sin(angle))))
        }
        func at(_ t: Double) -> RecTrack.Point {
            let angle = t * 1.4
            return RecTrack.Point(t: t, x: Double(width) * (0.5 + 0.3 * cos(angle)), y: Double(height) * (0.5 + 0.25 * sin(angle)))
        }
        track.clicks = [at(2.0), at(2.6)]
        var edit = RecEdit()
        edit.style = RecStyle()
        edit.zooms = RecEdit.autoZooms(from: track.clicks, duration: 6, scale: edit.style.zoomLevel)
        return RecMeta(id: UUID(), created: Date(), duration: 6, width: width, height: height, scale: 2, track: track, edit: edit)
    }

    static func frames(picture: URL, times: [Double]) -> CGImage? {
        guard let image = CIImage(contentsOf: picture) else { return nil }
        let meta = meta(width: Int(image.extent.width), height: Int(image.extent.height))
        let plan = RecPlan(meta: meta, edit: meta.edit, maxWidth: 900)
        let context = CIContext()
        let rendered = times.compactMap { context.createCGImage(plan.frame(source: image, time: $0), from: CGRect(origin: .zero, size: plan.output)) }
        let width = Int(plan.output.width), height = Int(plan.output.height)
        guard let sheet = CGContext(data: nil, width: width * rendered.count, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for (i, frame) in rendered.enumerated() { sheet.draw(frame, in: CGRect(x: i * width, y: 0, width: width, height: height)) }
        return sheet.makeImage()
    }
}
