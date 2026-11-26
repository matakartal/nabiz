// Builds docs/hero.jpg for the README from the screenshots in docs/: a desktop with Nabız in the menu bar, its panel
// open under it, the AI chat window and the launcher.
//
//   swift scripts/make-hero.swift
//
// Refresh the screenshots first (see README → Build → Development helpers).
import AppKit

let size = NSSize(width: 2560, height: 1440)
let docs = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs")

func image(_ name: String) -> NSImage {
    guard let image = NSImage(contentsOf: docs.appendingPathComponent(name)) else { fatalError("missing docs/\(name)") }
    // Pixels, not points: the screenshots are 2x.
    if let rep = image.representations.first { image.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh) }
    return image
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let full = NSRect(origin: .zero, size: size)

// A dark, wallpaper-like backdrop with two soft glows.
NSGradient(colors: [NSColor(red: 0.07, green: 0.06, blue: 0.13, alpha: 1),
                    NSColor(red: 0.16, green: 0.13, blue: 0.30, alpha: 1),
                    NSColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 1)])!.draw(in: full, angle: -35)
for (center, radius, color) in [(NSPoint(x: 700, y: 300), 900.0, NSColor(red: 0.45, green: 0.35, blue: 0.95, alpha: 0.28)),
                                (NSPoint(x: 2100, y: 1100), 800.0, NSColor(red: 0.15, green: 0.75, blue: 0.45, alpha: 0.16))] {
    NSGradient(colors: [color, color.withAlphaComponent(0)])!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

/// Top-left origin, like the screenshots are laid out.
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x, y: size.height - y - h, width: w, height: h) }

func window(_ name: String, at origin: NSPoint, width: CGFloat, radius: CGFloat = 22) {
    let picture = image(name)
    let height = width * picture.size.height / picture.size.width
    let frame = rect(origin.x, origin.y, width, height)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = 60
    shadow.shadowOffset = NSSize(width: 0, height: -24)
    shadow.set()
    NSColor.black.setFill()
    NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).addClip()
    picture.draw(in: frame)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.12).setStroke()
    let edge = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
    edge.lineWidth = 1.5
    edge.stroke()
}

// The menu bar, with Nabız's item on the right.
let barHeight: CGFloat = 72
NSColor.black.withAlphaComponent(0.35).setFill()
rect(0, 0, size.width, barHeight).fill()
let label = image("menubar.png")
let labelX: CGFloat = 1850
label.draw(in: rect(labelX, 0, label.size.width, label.size.height))
let clock = "Fri 09:41" as NSString
clock.draw(at: NSPoint(x: size.width - 250, y: size.height - 52),
           withAttributes: [.font: NSFont.systemFont(ofSize: 30, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.92)])
NSColor.white.withAlphaComponent(0.18).setFill()
NSBezierPath(roundedRect: rect(labelX - 8, 8, label.size.width + 16, barHeight - 16), xRadius: 12, yRadius: 12).fill()

window("ai-chat.png", at: NSPoint(x: 120, y: 170), width: 1500)
window("launcher.png", at: NSPoint(x: 760, y: 780), width: 860, radius: 26)
window("panel.png", at: NSPoint(x: 1790, y: 92), width: 470, radius: 20)

NSGraphicsContext.current = nil
let out = docs.appendingPathComponent("hero.jpg")
try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88])!.write(to: out)
print("wrote \(out.path)")
