// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
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
        track.keys = [RecTrack.Key(t: 1.0, text: "⌘⇧4"), RecTrack.Key(t: 3.0, text: "⌘C")]
        var edit = RecEdit()
        edit.style = RecStyle()
        edit.style.aspect = "16:9"
        edit.zooms = [RecZoom(start: 1.8, end: 4.2, scale: 1.8)]
        edit.captions = [RecCaption(start: 0, end: 2.5, text: "Önce görünüm ayarlarını açıyoruz"), RecCaption(start: 2.5, end: 6, text: "Sonra rengi seçiyoruz")]
        edit.notes = [RecNote(start: 0, end: 6, text: "Yeni", x: 0.25, y: 0.25, arrow: true, toX: 0.45, toY: 0.45)]
        edit.style.backgroundKind = "wallpaper"
        edit.style.backgroundImage = RecBackdrop.wallpapers.first?.path ?? ""
        var meta = RecMeta(id: UUID(), created: Date(), duration: 6, width: width, height: height, scale: 2, track: track, edit: edit)
        meta.cameraOffset = 0
        return meta
    }

    static func frames(picture: URL, times: [Double]) -> CGImage? {
        guard let image = CIImage(contentsOf: picture) else { return nil }
        let meta = meta(width: Int(image.extent.width), height: Int(image.extent.height))
        let plan = RecPlan(meta: meta, edit: meta.edit, maxWidth: 900)
        let context = CIContext()
        // A stand-in for the camera: a warm gradient.
        let face = CIFilter(name: "CIRadialGradient", parameters: ["inputCenter": CIVector(x: 640, y: 360), "inputRadius0": 40, "inputRadius1": 500,
                                                                   "inputColor0": CIColor(red: 1, green: 0.8, blue: 0.6), "inputColor1": CIColor(red: 0.3, green: 0.2, blue: 0.5)])?
            .outputImage?.cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))
        let rendered = times.compactMap { context.createCGImage(plan.frame(source: image, camera: face, time: $0), from: CGRect(origin: .zero, size: plan.output)) }
        let width = Int(plan.output.width), height = Int(plan.output.height)
        guard let sheet = CGContext(data: nil, width: width * rendered.count, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for (i, frame) in rendered.enumerated() { sheet.draw(frame, in: CGRect(x: i * width, y: 0, width: width, height: height)) }
        return sheet.makeImage()
    }
}
