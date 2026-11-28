// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Turning a styled recording into a file: MP4 at the recording's own size, 4K or 1080p, or a GIF at the frame
/// rate and width picked in the export menu. Cancelling the task stops it and removes the half-written file.
@MainActor
enum RecExport {
    enum Kind: String, CaseIterable, Identifiable {
        case original, uhd, hd, gif
        var id: String { rawValue }

        var title: String {
            switch self {
            case .original: L("MP4 · tam boyut", "MP4 · full size")
            case .uhd: "MP4 · 4K"
            case .hd: "MP4 · 1080p"
            case .gif: "GIF"
            }
        }

        var maxWidth: CGFloat? {
            switch self {
            case .original: nil
            case .uhd: 3840
            case .hd: 1920
            case .gif: CGFloat(GIFOptions.saved.width)
            }
        }
    }

    /// How a GIF is made; remembered for the next one.
    struct GIFOptions: Equatable {
        var fps: Int
        var width: Int

        static let rates = [10, 15, 24]
        static let widths = [640, 960, 1280]
        private static let fpsKey = "rec.gifFPS", widthKey = "rec.gifWidth"

        static var saved: GIFOptions {
            let fps = UserDefaults.standard.integer(forKey: fpsKey), width = UserDefaults.standard.integer(forKey: widthKey)
            return GIFOptions(fps: rates.contains(fps) ? fps : 15, width: widths.contains(width) ? width : 960)
        }

        func save() {
            UserDefaults.standard.set(fps, forKey: Self.fpsKey)
            UserDefaults.standard.set(width, forKey: Self.widthKey)
        }

        /// A rough size: screen recordings compress to about a seventh of a byte per pixel per frame. `width` is
        /// the side of a 16:9 box (as the renderer sizes it), so a tall video comes out narrower.
        func estimate(seconds: Double, aspect: Double) -> UInt64 {
            let aspect = max(aspect, 0.1)
            let outWidth = aspect >= 16.0 / 9 ? Double(width) : Double(width) * aspect / (16.0 / 9)
            return UInt64(max(0, seconds) * Double(fps) * outWidth * (outWidth / aspect) * 0.14)
        }

        /// Past this a GIF is slow to share and an MP4 does the same job in a fraction of the size.
        static let large: UInt64 = 25 * 1_048_576
    }

    enum Failure: LocalizedError {
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: L("Vazgeçildi", "Cancelled")
            case .failed(let reason): reason
            }
        }
    }

    /// "Ekran Kaydı 2026-11-26 18.41.07.mp4" in the screenshots folder.
    static func newFile(_ ext: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = L("Ekran Kaydı", "Screen Recording") + " " + formatter.string(from: Date())
        var url = Capture.folder.appendingPathComponent(name).appendingPathExtension(ext)
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = Capture.folder.appendingPathComponent("\(name) \(index)").appendingPathExtension(ext)
            index += 1
        }
        return url
    }

    /// The file, or nil (the reason goes to the log). For callers that only need to know whether it worked.
    static func run(_ meta: RecMeta, edit: RecEdit, kind: Kind, to url: URL? = nil, progress: @escaping @MainActor (Double) -> Void) async -> URL? {
        do {
            return try await export(meta, edit: edit, kind: kind, to: url, progress: progress)
        } catch {
            ShotLog.write("export failed: \(error)")
            return nil
        }
    }

    /// Exports, or throws why not. A cancelled task stops the export and leaves no partial file behind.
    static func export(_ meta: RecMeta, edit: RecEdit, kind: Kind, to url: URL? = nil, gif: GIFOptions = .saved,
                       progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        guard let built = await RecPlan.build(meta: meta, speeds: RecTimeMap(edit.timeSegments, duration: meta.duration).speeds,
                                              clickSound: edit.style.clickSound, keySound: edit.style.keySound) else {
            throw Failure.failed(L("Kaydın dosyası okunamadı", "Couldn't read the recording's file"))
        }
        try Task.checkCancellation()
        let plan = RecPlan(meta: meta, edit: edit, maxWidth: kind == .gif ? CGFloat(gif.width) : kind.maxWidth)
        // The kept part, moved onto the sped-up timeline.
        let start = plan.map.played(max(0, edit.trimStart))
        let end = plan.map.played(edit.trimEnd > edit.trimStart ? edit.trimEnd : meta.duration)
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        let output = url ?? newFile(kind == .gif ? "gif" : "mp4")
        do {
            if kind == .gif {
                try await Self.gif(built: built, plan: plan, range: range, fps: Double(gif.fps), to: output, progress: progress)
            } else {
                try await mp4(built: built, plan: plan, style: edit.style, range: range, to: output, progress: progress)
            }
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            if Task.isCancelled || error is CancellationError { throw Failure.cancelled }
            throw error
        }
    }

    private static func mp4(built: RecPlan.Built, plan: RecPlan, style: RecStyle, range: CMTimeRange, to output: URL,
                            progress: @escaping @MainActor (Double) -> Void) async throws {
        guard let session = AVAssetExportSession(asset: built.asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw Failure.failed(L("Video dışa aktarılamıyor", "This video can't be exported"))
        }
        session.videoComposition = plan.composition(for: built)
        session.audioTimePitchAlgorithm = .spectral
        session.audioMix = built.audioMix(style)
        session.outputURL = output
        session.outputFileType = .mp4
        session.timeRange = range
        session.shouldOptimizeForNetworkUse = true
        let box = SessionBox(session)
        let poll = Timer(timeInterval: 0.2, repeats: true) { _ in
            MainActor.assumeIsolated { progress(Double(box.session.progress)) }
        }
        RunLoop.main.add(poll, forMode: .common)
        defer { poll.invalidate() }
        let status: AVAssetExportSession.Status = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.session.exportAsynchronously { continuation.resume(returning: box.session.status) }
            }
        } onCancel: {
            box.session.cancelExport()
        }
        switch status {
        case .completed: return
        case .cancelled: throw Failure.cancelled
        default: throw Failure.failed(box.session.error?.localizedDescription ?? L("Dışa aktarılamadı", "Export failed"))
        }
    }

    /// Looping, made off the main thread. A frame that can't be drawn repeats the one before, so the GIF still
    /// has every frame it promised and can be finished.
    private nonisolated static func gif(built: RecPlan.Built, plan: RecPlan, range: CMTimeRange, fps: Double, to url: URL,
                                        progress: @escaping @MainActor (Double) -> Void) async throws {
        let generator = AVAssetImageGenerator(asset: built.asset)
        generator.videoComposition = plan.composition(for: built)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let start = range.start.seconds, end = range.end.seconds
        let count = max(1, Int((end - start) * fps))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw Failure.failed(L("GIF dosyası oluşturulamadı", "Couldn't create the GIF file"))
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        var previous: CGImage?
        var missing = 0
        var lastError: Error?
        for i in 0..<count {
            try Task.checkCancellation()
            let time = CMTime(seconds: start + Double(i) / fps, preferredTimescale: 600)
            do {
                let image = try await generator.image(at: time).image
                // Frames that failed before the first good one are filled in with it.
                for _ in 0..<missing { CGImageDestinationAddImage(destination, image, frame) }
                missing = 0
                CGImageDestinationAddImage(destination, image, frame)
                previous = image
            } catch {
                lastError = error
                if let previous { CGImageDestinationAddImage(destination, previous, frame) } else { missing += 1 }
            }
            let done = Double(i + 1) / Double(count)
            await MainActor.run { progress(done) }
        }
        guard previous != nil else {
            throw Failure.failed(lastError?.localizedDescription ?? L("Hiç kare çizilemedi", "No frame could be drawn"))
        }
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.failed(L("GIF yazılamadı", "Couldn't write the GIF"))
        }
    }
}

/// AVAssetExportSession isn't Sendable; it is only touched from the main actor and its own completion.
private final class SessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}
