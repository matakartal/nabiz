import AppKit
import UniformTypeIdentifiers
import Vision

/// Images you attach to a chat: kept as a small copy in Nabız's folder (so the chat can show and resend them),
/// seen directly by the AIs that can (Claude, Codex), read as text by the ones that can't.
enum AIImages {
    static let folder: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nabiz").appendingPathComponent("ai-images")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Long side at most this many pixels: plenty to read, and well under the CLIs' size limits.
    static let maxSide: CGFloat = 2000

    static func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// Saves a JPEG copy, shrunk if needed; returns its file name.
    static func store(_ source: URL) -> String? {
        guard let image = NSImage(contentsOf: source) else { return nil }
        return store(image)
    }

    static func store(_ image: NSImage) -> String? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, maxSide / CGFloat(max(cg.width, cg.height)))
        let width = max(1, Int(CGFloat(cg.width) * scale)), height = max(1, Int(CGFloat(cg.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        // Transparent parts become white, as they'd look on a page.
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: url(name), options: [.atomic, .completeFileProtection])
            return name
        } catch {
            return nil
        }
    }

    /// A copy under a new name (for a branched chat).
    static func copy(_ name: String) -> String? {
        let new = UUID().uuidString + ".jpg"
        return (try? FileManager.default.copyItem(at: url(name), to: url(new))) != nil ? new : nil
    }

    static func remove(_ names: [String]) {
        for name in names where !name.isEmpty && !name.contains("/") { try? FileManager.default.removeItem(at: url(name)) }
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// The text written in an image (on this Mac, with Vision), for the AIs that can't see images.
    static func text(in name: String) async -> String {
        let file = url(name)
        return await Task.detached(priority: .userInitiated) {
            guard let image = NSImage(contentsOf: file), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try? VNImageRequestHandler(cgImage: cg).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }

    /// What an AI that can't see the image reads instead.
    static func describe(_ text: String) -> String {
        text.isEmpty ? "(An image; no readable text in it.)" : "(An image. The text in it:)\n\(text)"
    }

    /// Claude's stdin when images go along: one stream-json user message with the images and the prompt.
    static func claudeMessage(prompt: String, images: [URL]) -> String {
        var content: [[String: Any]] = images.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()]]
        }
        content.append(["type": "text", "text": prompt])
        let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": content]]
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return prompt }
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
