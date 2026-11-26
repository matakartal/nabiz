// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import CoreImage
import ImageIO

/// Pictures behind a recording: macOS's own wallpapers, your desktop picture, or any image, filled to the frame
/// and optionally blurred. Decoded straight at the size needed and kept, so moving a slider stays quick.
@MainActor
enum RecBackdrop {
    /// macOS's still wallpapers, with your current desktop picture first.
    static let wallpapers: [URL] = {
        var list: [URL] = []
        if let screen = NSScreen.main, let desktop = NSWorkspace.shared.desktopImageURL(for: screen),
           ["heic", "jpg", "jpeg", "png", "tiff"].contains(desktop.pathExtension.lowercased()) { list.append(desktop) }
        let folder = URL(fileURLWithPath: "/System/Library/Desktop Pictures")
        let found = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "heic" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        list.append(contentsOf: found.filter { !list.contains($0) })
        return list
    }()

    private static var thumbnails: [URL: NSImage] = [:]
    private static var images: [String: CGImage] = [:]

    static func thumbnail(_ url: URL) -> NSImage? {
        if let cached = thumbnails[url] { return cached }
        guard let cg = decode(url, longest: 160) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnails[url] = image
        return image
    }

    private static func decode(_ url: URL, longest: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(longest),
        ] as CFDictionary)
    }

    /// The picture filling `size` (cropped to keep its shape), blurred by `blur` 0…1.
    static func image(_ url: URL, size: CGSize, blur: Double) -> CGImage? {
        let key = "\(url.path)|\(Int(size.width))x\(Int(size.height))|\(Int(blur * 100))"
        if let cached = images[key] { return cached }
        guard let cg = decode(url, longest: max(size.width, size.height) * 1.05) else { return nil }
        var image = CIImage(cgImage: cg)
        let fill = max(size.width / image.extent.width, size.height / image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: fill, y: fill))
        image = image.transformed(by: CGAffineTransform(translationX: (size.width - image.extent.width) / 2 - image.extent.minX,
                                                        y: (size.height - image.extent.height) / 2 - image.extent.minY))
        if blur > 0.01 { image = image.clampedToExtent().applyingGaussianBlur(sigma: blur * Double(size.width) * 0.025) }
        let frame = CGRect(origin: .zero, size: size)
        guard let made = CIContext().createCGImage(image.cropped(to: frame), from: frame) else { return nil }
        if images.count > 12 { images.removeAll() }
        images[key] = made
        return made
    }
}

extension CIColor {
    /// "#RRGGBB".
    convenience init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255)
    }
}
