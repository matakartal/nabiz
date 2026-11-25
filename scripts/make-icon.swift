// Draws Nabız's app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (run from the repository root)
//
// The icon: a green squircle on the macOS icon grid with a single white heartbeat line. Nothing else.
import AppKit

let canvas: CGFloat = 1024
// macOS icon grid: the shape is 824 pt inside a 1024 canvas, corner radius ~185.
let inset: CGFloat = 100
let shapeRect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let accent = NSColor(srgbRed: 0x1D / 255, green: 0xB9 / 255, blue: 0x54 / 255, alpha: 1)

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(size) / canvas
    context.scaleBy(x: scale, y: scale)

    // Drop shadow under the squircle, like system icons.
    let shape = CGPath(roundedRect: shapeRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    context.addPath(shape)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    // Background: the accent green, a touch lighter at the top.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: [NSColor(srgbRed: 0x34 / 255, green: 0xD3 / 255, blue: 0x6B / 255, alpha: 1).cgColor,
                                         NSColor(srgbRed: 0x14 / 255, green: 0xA8 / 255, blue: 0x4A / 255, alpha: 1).cgColor] as CFArray,
                                locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 0, y: shapeRect.maxY), end: CGPoint(x: 0, y: shapeRect.minY), options: [])

    // One white heartbeat line, nothing else.
    let points: [CGPoint] = [
        CGPoint(x: 230, y: 500), CGPoint(x: 395, y: 500), CGPoint(x: 455, y: 650),
        CGPoint(x: 545, y: 330), CGPoint(x: 615, y: 560), CGPoint(x: 650, y: 500), CGPoint(x: 794, y: 500),
    ]
    let line = CGMutablePath()
    line.addLines(between: points)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: NSColor(srgbRed: 0, green: 0.3, blue: 0.1, alpha: 0.35).cgColor)
    context.addPath(line)
    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineWidth(58)
    context.strokePath()
    context.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
try! render(size: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
