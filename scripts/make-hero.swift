// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
// Builds docs/hero.jpg for the README: the Mac's own wallpaper with Nabız as it really looks — the menu bar item, the
// frosted panel under it, the AI chat window and the launcher, each on blurred glass over the wallpaper.
//
//   swift scripts/make-hero.swift <wallpaper.png> <panel.png> <chat.png> <launcher.png> <menubar.png> [out.jpg]
//
// Make the window pictures with `--clear` so they carry no material of their own (the glass is drawn here):
//   Nabiz --snapshot panel.png --dark --clear
//   Nabiz --snapshot chat.png --dark --clear --ai-window "…" --engine onDevice --seed --chrome --width 1000 --height 680
//   Nabiz --snapshot launcher.png --dark --clear --launcher "sa"
// The wallpaper: `screencapture -x -o -l <wallpaper window id>`.
import AppKit
import CoreImage

let args = CommandLine.arguments
guard args.count >= 6 else { print("usage: make-hero.swift wallpaper panel chat launcher menubar [out]"); exit(1) }
let out = URL(fileURLWithPath: args.count > 6 ? args[6] : "docs/hero.jpg")
let size = CGSize(width: 2560, height: 1440)
let context = CIContext()

func load(_ path: String) -> CIImage {
    guard let image = CIImage(contentsOf: URL(fileURLWithPath: path)) else { fatalError("missing \(path)") }
    return image
}

// The wallpaper, filling the frame.
let wallpaperSource = load(args[1])
let fill = max(size.width / wallpaperSource.extent.width, size.height / wallpaperSource.extent.height)
let scaled = wallpaperSource.transformed(by: CGAffineTransform(scaleX: fill, y: fill))
let wallpaper = scaled.transformed(by: CGAffineTransform(translationX: -(scaled.extent.width - size.width) / 2,
                                                         y: -(scaled.extent.height - size.height) / 2))
    .cropped(to: CGRect(origin: .zero, size: size))

/// The menu material over the wallpaper: heavily blurred, a little more saturated, darkened like dark mode.
let glass: CIImage = {
    let blurred = wallpaper.clampedToExtent().applyingGaussianBlur(sigma: 38).cropped(to: wallpaper.extent)
    let saturated = blurred.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.7, kCIInputBrightnessKey: -0.02])
    let tint = CIImage(color: CIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 0.62)).cropped(to: wallpaper.extent)
    return tint.composited(over: saturated)
}()

guard let base = context.createCGImage(wallpaper, from: wallpaper.extent),
      let glassImage = context.createCGImage(glass, from: glass.extent) else { fatalError("render failed") }

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let cg = NSGraphicsContext.current!.cgContext
cg.draw(base, in: CGRect(origin: .zero, size: size))

/// Top-left origin, like the screenshots.
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: size.height - y - h, width: w, height: h) }

/// Glass in the shape of `frame`, with the window's shadow and its thin light rim.
func pane(_ frame: CGRect, radius: CGFloat) {
    let path = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -26), blur: 70, color: NSColor.black.withAlphaComponent(0.55).cgColor)
    cg.addPath(path)
    cg.setFillColor(NSColor.black.cgColor)
    cg.fillPath()
    cg.restoreGState()
    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    cg.draw(glassImage, in: CGRect(origin: .zero, size: size))
    cg.restoreGState()
}

func rim(_ frame: CGRect, radius: CGFloat) {
    cg.saveGState()
    cg.addPath(CGPath(roundedRect: frame.insetBy(dx: 1, dy: 1), cornerWidth: radius - 1, cornerHeight: radius - 1, transform: nil))
    cg.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
    cg.setLineWidth(2)
    cg.strokePath()
    cg.restoreGState()
}

func window(_ path: String, at origin: CGPoint, width: CGFloat, radius: CGFloat) {
    guard let picture = NSImage(contentsOfFile: path), let pixels = picture.representations.first else { fatalError("missing \(path)") }
    let height = width * CGFloat(pixels.pixelsHigh) / CGFloat(pixels.pixelsWide)
    let frame = rect(origin.x, origin.y, width, height)
    pane(frame, radius: radius)
    cg.saveGState()
    cg.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
    cg.clip()
    picture.draw(in: frame)
    cg.restoreGState()
    rim(frame, radius: radius)
}

// The menu bar: the same glass, lighter, with Nabız's item lit like an open menu.
let barHeight: CGFloat = 72
cg.saveGState()
cg.clip(to: rect(0, 0, size.width, barHeight))
cg.draw(glassImage, in: CGRect(origin: .zero, size: size))
cg.setFillColor(NSColor.white.withAlphaComponent(0.04).cgColor)
cg.fill(rect(0, 0, size.width, barHeight))
cg.restoreGState()
let label = NSImage(contentsOfFile: args[5])!
let labelPixels = label.representations.first!
let labelSize = CGSize(width: labelPixels.pixelsWide, height: labelPixels.pixelsHigh)
let labelX: CGFloat = 1850
cg.setFillColor(NSColor.white.withAlphaComponent(0.16).cgColor)
cg.addPath(CGPath(roundedRect: rect(labelX - 10, 7, labelSize.width + 20, barHeight - 14), cornerWidth: 12, cornerHeight: 12, transform: nil))
cg.fillPath()
// The captured label carries the real menu bar behind it; keep only its bright text by screening it on.
cg.saveGState()
cg.setBlendMode(.screen)
label.draw(in: rect(labelX, (barHeight - labelSize.height) / 2, labelSize.width, labelSize.height))
cg.restoreGState()
("Fri 9:41" as NSString).draw(at: CGPoint(x: size.width - 250, y: size.height - 52),
                              withAttributes: [.font: NSFont.systemFont(ofSize: 30, weight: .medium), .foregroundColor: NSColor.white])

window(args[3], at: CGPoint(x: 110, y: 160), width: 1500, radius: 24)
window(args[4], at: CGPoint(x: 760, y: 790), width: 860, radius: 26)
window(args[2], at: CGPoint(x: 1790, y: 88), width: 470, radius: 20)

NSGraphicsContext.current = nil
try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88])!.write(to: out)
print("wrote \(out.path)")
