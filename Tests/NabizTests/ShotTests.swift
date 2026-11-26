// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Testing
@testable import Nabiz

/// The screenshot editor's geometry, undo, numbering and export.
@MainActor
@Suite("Screenshot editor")
struct ShotTests {
    /// A 200×100 point image at Retina scale (400×200 pixels), half red half blue.
    private func makeDoc() -> ShotDocument {
        let ctx = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 200, y: 0, width: 200, height: 200))
        let doc = ShotDocument(image: ctx.makeImage()!, scale: 2)
        doc.background = ShotBackground()
        return doc
    }

    @Test func boundsInPoints() {
        let doc = makeDoc()
        #expect(doc.bounds == CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(doc.documentRect == doc.bounds)
    }

    @Test func exportKeepsPixelsAndCrop() throws {
        let doc = makeDoc()
        var image = try #require(ShotRenderer.export(doc))
        #expect(image.width == 400 && image.height == 200)
        doc.crop = CGRect(x: 10, y: 10, width: 50, height: 40)
        image = try #require(ShotRenderer.export(doc))
        #expect(image.width == 100 && image.height == 80)
        doc.background.enabled = true
        doc.background.padding = 20
        image = try #require(ShotRenderer.export(doc))
        #expect(image.width == 180 && image.height == 160)
    }

    @Test func undoAndRedo() {
        let doc = makeDoc()
        doc.add(ShotItem(kind: .rect, start: .zero, end: CGPoint(x: 10, y: 10), ink: ShotInk.palette[0], size: .medium))
        doc.add(ShotItem(kind: .line, start: .zero, end: CGPoint(x: 10, y: 10), ink: ShotInk.palette[0], size: .medium))
        #expect(doc.items.count == 2)
        doc.undo()
        #expect(doc.items.count == 1)
        doc.redo()
        #expect(doc.items.count == 2)
        #expect(doc.hasUnsavedChanges)
        doc.savedChanges = doc.changes
        #expect(!doc.hasUnsavedChanges)
    }

    @Test func cancelledAddLeavesNoUndoStep() {
        let doc = makeDoc()
        let item = ShotItem(kind: .arrow, start: .zero, end: .zero, ink: ShotInk.palette[0], size: .medium)
        doc.add(item)
        doc.cancelAdd(item.id)
        #expect(doc.items.isEmpty)
        #expect(!doc.canUndo)
    }

    @Test func countersRenumberAfterDelete() {
        let doc = makeDoc()
        let counters = (0..<3).map { i in
            ShotItem(kind: .counter, start: CGPoint(x: 20 * i, y: 20), end: .zero, ink: ShotInk.palette[0], size: .medium)
        }
        counters.forEach(doc.add)
        #expect(doc.number(of: counters[2]) == 3)
        doc.selection = counters[0].id
        doc.deleteSelection()
        #expect(doc.number(of: counters[2]) == 2)
    }

    @Test func hitTesting() {
        let line = ShotItem(kind: .line, start: .zero, end: CGPoint(x: 100, y: 0), ink: ShotInk.palette[0], size: .medium)
        #expect(ShotRenderer.hit(line, CGPoint(x: 50, y: 3), slop: 2))
        #expect(!ShotRenderer.hit(line, CGPoint(x: 50, y: 20), slop: 2))
        let box = ShotItem(kind: .rect, start: .zero, end: CGPoint(x: 100, y: 100), ink: ShotInk.palette[0], size: .medium)
        #expect(ShotRenderer.hit(box, CGPoint(x: 0, y: 50), slop: 2))
        #expect(!ShotRenderer.hit(box, CGPoint(x: 50, y: 50), slop: 2))
    }

    @Test func shiftConstrains() {
        let p = CGPoint(x: 100, y: 10).constrained(from: .zero, box: false)
        #expect(abs(p.y) < 0.001)
        let square = CGPoint(x: 30, y: -10).constrained(from: .zero, box: true)
        #expect(square == CGPoint(x: 30, y: -30))
    }

    @Test func pixelateHidesTheRegion() throws {
        let doc = makeDoc()
        #expect(doc.hidden(pixelate: true) != nil)
        #expect(doc.hidden(pixelate: false) != nil)
        let image = try #require(ShotRenderer.export(doc))
        #expect(ShotRenderer.encode(image, type: "png", scale: 2) != nil)
        #expect(ShotRenderer.encode(image, type: "jpg", scale: 2) != nil)
    }
}
