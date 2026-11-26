import AVFoundation

/// The sounds a recording can add: a mouse click (press and release) and a soft key tap. Made once from
/// scratch (no sound files shipped) and kept in the caches folder.
enum RecClickSound {
    static var file: URL? { click }

    static let click: URL? = make("click-2.caf", length: 0.11) { t in
        // Press: a bright, sharp transient; release 55 ms later: a softer one.
        transient(t, at: 0, brightness: 3200, decay: 0.006, level: 0.9) + transient(t, at: 0.055, brightness: 2600, decay: 0.005, level: 0.45)
    }

    static let key: URL? = make("key-1.caf", length: 0.07) { t in
        // A low, muffled tap: a laptop key bottoming out.
        transient(t, at: 0, brightness: 1300, decay: 0.008, level: 0.55)
    }

    private static func transient(_ t: Double, at start: Double, brightness: Double, decay: Double, level: Double) -> Double {
        let u = t - start
        guard u >= 0 else { return 0 }
        let envelope = min(u / 0.0003, 1) * exp(-u / decay)
        // A damped tone plus a pinch of noise from a fixed sine mix (no randomness: always the same sound).
        let tone = sin(2 * .pi * brightness * u) * 0.6 + sin(2 * .pi * brightness * 2.7 * u) * 0.25
        let grit = sin(2 * .pi * 9_100 * u + sin(2 * .pi * 430 * u) * 4) * 0.35
        return (tone + grit) * envelope * level
    }

    private static func make(_ name: String, length: Double, _ sample: (Double) -> Double) -> URL? {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Nabiz/\(name)")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rate = 48_000.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * length)) else { return nil }
        buffer.frameLength = buffer.frameCapacity
        for i in 0..<Int(buffer.frameLength) {
            let value = Float(max(-1, min(1, sample(Double(i) / rate))))
            buffer.floatChannelData?[0][i] = value
            buffer.floatChannelData?[1][i] = value
        }
        guard let out = try? AVAudioFile(forWriting: url, settings: format.settings) else { return nil }
        try? out.write(from: buffer)
        return url
    }
}
