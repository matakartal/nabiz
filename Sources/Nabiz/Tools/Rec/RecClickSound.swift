import AVFoundation

/// The sounds a recording can add for clicks and keys. When this Mac has an iOS simulator (Xcode), they are the
/// iPhone's own: the keyboard tick, the delete key, space and return, and the "Tock" for a click, read from the
/// simulator at run time and never shipped with Nabız. Without one, a close stand-in is made from scratch.
/// Either way they are converted once to 48 kHz stereo and kept in the caches folder.
enum RecClickSound {
    enum Kind: String, CaseIterable {
        case click, key, delete, modifier

        /// The iPhone's file for it.
        var iPhoneName: String {
            switch self {
            case .click: "Tock.caf"
            case .key: "key_press_click.caf"
            case .delete: "key_press_delete.caf"
            case .modifier: "key_press_modifier.caf"
            }
        }
    }

    /// What kind of key a typed key was (never which key): letters, delete, or space / return / tab.
    static func kind(forKeyCode code: Int) -> Int {
        switch code {
        case 51, 117: 1
        case 49, 36, 76, 48: 2
        default: 0
        }
    }

    static var click: URL? { url(.click) }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Kind: URL] = [:]

    static func url(_ kind: Kind) -> URL? {
        if let known = lock.withLock({ cache[kind] }) { return known }
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Nabiz/sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let iPhone = folder.appendingPathComponent("iphone-\(kind.rawValue)-1.caf")
        var found: URL?
        if FileManager.default.fileExists(atPath: iPhone.path) {
            found = iPhone
        } else if let source = iPhoneSounds()?.appendingPathComponent(kind.iPhoneName), convert(source, to: iPhone) {
            found = iPhone
        } else {
            let made = folder.appendingPathComponent("made-\(kind.rawValue)-1.caf")
            if FileManager.default.fileExists(atPath: made.path) || synthesize(kind, to: made) { found = made }
        }
        if let found { lock.withLock { cache[kind] = found } }
        return found
    }

    // MARK: The iPhone's own

    /// The newest iOS simulator's UISounds folder on this Mac, if Xcode has one.
    private static func iPhoneSounds() -> URL? {
        let manager = FileManager.default
        let inside = "Library/Developer/CoreSimulator/Profiles/Runtimes"
        var roots: [URL] = []
        for base in ["/Library/Developer/CoreSimulator/Volumes", "/private/var/run/com.apple.security.cryptexd/mnt"] {
            let entries = (try? manager.contentsOfDirectory(atPath: base)) ?? []
            roots += entries.map { URL(fileURLWithPath: base).appendingPathComponent($0).appendingPathComponent(inside) }
        }
        roots.append(URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Profiles/Runtimes"))
        var folders: [URL] = []
        for root in roots {
            for runtime in (try? manager.contentsOfDirectory(atPath: root.path)) ?? [] where runtime.hasPrefix("iOS") && runtime.hasSuffix(".simruntime") {
                let folder = root.appendingPathComponent(runtime).appendingPathComponent("Contents/Resources/RuntimeRoot/System/Library/Audio/UISounds")
                if manager.fileExists(atPath: folder.appendingPathComponent("key_press_click.caf").path) { folders.append(folder) }
            }
        }
        // "iOS 27.2.simruntime" before "iOS 18.2.simruntime".
        return folders.sorted { $0.path.compare($1.path, options: .numeric) == .orderedDescending }.first
    }

    /// Any sound file into 48 kHz stereo float, so every added sound shares one format.
    private static func convert(_ source: URL, to target: URL) -> Bool {
        guard let input = try? AVAudioFile(forReading: source),
              let output = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2),
              let converter = AVAudioConverter(from: input.processingFormat, to: output),
              let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length)) else { return false }
        guard (try? input.read(into: buffer)) != nil else { return false }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 48_000 / input.processingFormat.sampleRate) + 1024
        guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return false }
        var fed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, converted.frameLength > 0, let file = try? AVAudioFile(forWriting: target, settings: output.settings) else { return false }
        return (try? file.write(from: converted)) != nil
    }

    // MARK: Stand-ins

    private static func synthesize(_ kind: Kind, to url: URL) -> Bool {
        let rate = 48_000.0
        let length = kind == .click ? 0.03 : 0.02
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * length)) else { return false }
        buffer.frameLength = buffer.frameCapacity
        // A dry, woody tick like the iPhone's: a fast attack, a few milliseconds of a damped body and a bright edge.
        let (body, edge, decay): (Double, Double, Double) = switch kind {
        case .click: (1_150, 4_600, 0.0045)
        case .key: (1_900, 6_200, 0.0016)
        case .delete: (1_350, 5_000, 0.0028)
        case .modifier: (1_050, 4_200, 0.0034)
        }
        for i in 0..<Int(buffer.frameLength) {
            let t = Double(i) / rate
            let envelope = min(t / 0.00015, 1) * exp(-t / decay)
            let value = (sin(2 * .pi * body * t) * 0.7 + sin(2 * .pi * edge * t) * 0.3) * envelope * 0.8
            buffer.floatChannelData?[0][i] = Float(value)
            buffer.floatChannelData?[1][i] = Float(value)
        }
        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return false }
        return (try? file.write(from: buffer)) != nil
    }
}
