import AVFoundation
import Speech

/// Captions from what was said, recognised on this Mac (nothing is uploaded when macOS can do it on device):
/// the microphone if there is one, else the Mac's sound; split into short lines at pauses and sentence ends.
enum RecCaptions {
    enum Failure: Error { case noAudio, notAllowed, unavailable }

    static func transcribe(_ meta: RecMeta, locale: Locale) async throws -> [RecCaption] {
        guard await allowed() else { throw Failure.notAllowed }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { throw Failure.unavailable }
        let audio = try await extractAudio(meta)
        defer { try? FileManager.default.removeItem(at: audio) }
        let request = SFSpeechURLRecognitionRequest(url: audio)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        let segments: [(String, Double, Double)] = try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.segments.map { ($0.substring, $0.timestamp, $0.duration) })
                } else if let error {
                    finished = true
                    continuation.resume(throwing: error)
                }
            }
        }
        return lines(segments)
    }

    private static func allowed() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    /// The voice track alone, as an m4a in the caches folder.
    private static func extractAudio(_ meta: RecMeta) async throws -> URL {
        let source = AVURLAsset(url: RecStore.video(for: meta.id))
        let tracks = try await source.loadTracks(withMediaType: .audio)
        // The microphone is written after the Mac's sound.
        guard let voice = tracks.last else { throw Failure.noAudio }
        let duration = try await source.load(.duration)
        let composition = AVMutableComposition()
        let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        try track?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: voice, at: .zero)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nabiz-voice-\(UUID().uuidString).m4a")
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else { throw Failure.noAudio }
        session.outputURL = url
        session.outputFileType = .m4a
        let box = UncheckedBox(session)
        await withCheckedContinuation { continuation in box.value.exportAsynchronously { continuation.resume() } }
        guard box.value.status == .completed else { throw Failure.noAudio }
        return url
    }

    /// Words into caption lines: at most ~42 characters and 4 s, broken at pauses over 0.6 s and after . ? !
    static func lines(_ words: [(String, Double, Double)]) -> [RecCaption] {
        var result: [RecCaption] = []
        var text = "", start = 0.0, end = 0.0
        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { result.append(RecCaption(start: start, end: end + 0.25, text: trimmed)) }
            text = ""
        }
        for (word, at, length) in words {
            if !text.isEmpty && (at - end > 0.6 || text.count + word.count > 42 || at + length - start > 4) { flush() }
            if text.isEmpty { start = at }
            text += (text.isEmpty ? "" : " ") + word
            end = at + length
            if let last = word.last, ".?!".contains(last) { flush() }
        }
        flush()
        // No overlaps once padded.
        for i in result.indices.dropLast() where result[i].end > result[i + 1].start { result[i].end = result[i + 1].start }
        return result
    }
}

final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
