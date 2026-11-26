import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Turning a styled recording into a file: MP4 at the recording's own size, 4K or 1080p, or a GIF.
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
            case .gif: 960
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

    static func run(_ meta: RecMeta, edit: RecEdit, kind: Kind, to url: URL? = nil, progress: @escaping @MainActor (Double) -> Void) async -> URL? {
        guard let built = await RecPlan.build(meta: meta, speeds: RecTimeMap(edit.timeSegments, duration: meta.duration).speeds, clickSound: edit.style.clickSound) else { return nil }
        let plan = RecPlan(meta: meta, edit: edit, maxWidth: kind.maxWidth)
        // The kept part, moved onto the sped-up timeline.
        let start = plan.map.played(max(0, edit.trimStart))
        let end = plan.map.played(edit.trimEnd > edit.trimStart ? edit.trimEnd : meta.duration)
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        if kind == .gif {
            return await gif(built: built, plan: plan, range: range, to: url ?? newFile("gif"), progress: progress)
        }
        let output = url ?? newFile("mp4")
        guard let session = AVAssetExportSession(asset: built.asset, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        session.videoComposition = plan.composition(for: built)
        session.audioTimePitchAlgorithm = .spectral
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
        let ok: Bool = await withCheckedContinuation { continuation in
            box.session.exportAsynchronously {
                continuation.resume(returning: box.session.status == .completed)
            }
        }
        if !ok { ShotLog.write("export failed: \(String(describing: box.session.error))") }
        return ok ? output : nil
    }

    /// 15 frames a second, looping, at most 960 px wide; made off the main thread.
    private nonisolated static func gif(built: RecPlan.Built, plan: RecPlan, range: CMTimeRange, to url: URL,
                                        progress: @escaping @MainActor (Double) -> Void) async -> URL? {
        let generator = AVAssetImageGenerator(asset: built.asset)
        generator.videoComposition = plan.composition(for: built)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let fps = 15.0
        let start = range.start.seconds, end = range.end.seconds
        let count = max(1, Int((end - start) * fps))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil) else { return nil }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        for i in 0..<count {
            let time = CMTime(seconds: start + Double(i) / fps, preferredTimescale: 600)
            guard let image = try? await generator.image(at: time).image else { continue }
            CGImageDestinationAddImage(destination, image, frame)
            let done = Double(i + 1) / Double(count)
            await MainActor.run { progress(done) }
        }
        return CGImageDestinationFinalize(destination) ? url : nil
    }
}

/// AVAssetExportSession isn't Sendable; it is only touched from the main actor and its own completion.
private final class SessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}
