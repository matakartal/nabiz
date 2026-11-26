import AVFoundation

/// A short, soft mouse click, made once (no sound file shipped): a tiny bright transient with a quick decay.
enum RecClickSound {
    static let file: URL? = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Nabiz/click.caf")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rate = 48_000.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * 0.06)) else { return nil }
        buffer.frameLength = buffer.frameCapacity
        var seed: UInt32 = 7
        var low = 0.0
        for i in 0..<Int(buffer.frameLength) {
            let t = Double(i) / rate
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed >> 8) / Double(1 << 24) * 2 - 1
            low += (noise - low) * 0.35
            // A sharp attack, a 9 ms decay, and a faint body at 2.4 kHz.
            let envelope = min(t / 0.0004, 1) * exp(-t / 0.009)
            let body = sin(2 * .pi * 2400 * t) * exp(-t / 0.006) * 0.35
            let sample = Float((noise - low) * 0.55 * envelope + body * envelope) * 0.6
            buffer.floatChannelData?[0][i] = sample
            buffer.floatChannelData?[1][i] = sample
        }
        guard let out = try? AVAudioFile(forWriting: url, settings: format.settings) else { return nil }
        try? out.write(from: buffer)
        return url
    }()
}
