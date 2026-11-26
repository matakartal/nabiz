// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import CoreImage
import Testing
@testable import Nabiz

/// Screen recording: zooms made from clicks, the frame's size and the camera.
@MainActor
@Suite("Screen recording")
struct RecTests {
    private func click(_ t: Double, _ x: Double, _ y: Double) -> RecTrack.Point { RecTrack.Point(t: t, x: x, y: y) }

    @Test func clicksBecomeShots() {
        let size = CGSize(width: 1000, height: 1000)
        // Two clicks close in time and space share a shot; a far later one gets its own.
        let zooms = RecZoomPlanner.plan(clicks: [click(5, 500, 500), click(6, 520, 510), click(14, 200, 200)], size: size, duration: 30)
        #expect(zooms.count == 2)
        #expect(zooms[0].start < 5 && zooms[0].end > 6)
        #expect(zooms.allSatisfy { $0.end - $0.start >= 1.8 && $0.scale <= 1.8 })
    }

    @Test func openingAndStopClickStayWide() {
        let size = CGSize(width: 1000, height: 1000)
        #expect(RecZoomPlanner.plan(clicks: [click(9.5, 500, 500)], size: size, duration: 10).isEmpty)
        let early = RecZoomPlanner.plan(clicks: [click(1, 500, 500)], size: size, duration: 20)
        #expect(early.allSatisfy { $0.start >= 2.5 })
    }

    @Test func pointerLandsOnTheClick() {
        var track = RecTrack()
        for i in 0...120 { track.moves.append(RecTrack.Point(t: Double(i) / 60, x: Double(i) * 8, y: 400)) }
        track.clicks = [RecTrack.Point(t: 1, x: 480, y: 400)]
        let path = RecCursorPath(track: track, size: CGSize(width: 1000, height: 800), smoothing: 0.3)
        let at = path.at(1)!
        #expect(abs(at.0 - 0.48) < 0.001 && abs(at.1 - 0.5) < 0.001)
        #expect(path.bounce(1.05) < 1 && path.bounce(1.2) > 1 && path.bounce(2) == 1)
    }

    @Test func planSizesAreEvenAndPadded() {
        var edit = RecEdit()
        edit.style = RecStyle()
        let meta = RecMeta(id: UUID(), created: Date(), duration: 4, width: 1280, height: 800, scale: 2, track: RecTrack(), edit: edit)
        let full = RecPlan(meta: meta, edit: edit, maxWidth: nil)
        #expect(Int(full.output.width) % 2 == 0 && Int(full.output.height) % 2 == 0)
        #expect(full.output.width > 1280)
        let hd = RecPlan(meta: meta, edit: edit, maxWidth: 1000)
        #expect(hd.output.width <= 1000)
        let frame = hd.frame(source: CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 800)), time: 1)
        #expect(frame.extent == CGRect(origin: .zero, size: hd.output))
    }

    @Test func cameraZoomsInAndBack() {
        var edit = RecEdit()
        edit.style = RecStyle()
        edit.zooms = [RecZoom(start: 1.5, end: 3, scale: 2)]
        let meta = RecMeta(id: UUID(), created: Date(), duration: 6, width: 1280, height: 800, scale: 2, track: RecTrack(), edit: edit)
        let plan = RecPlan(meta: meta, edit: edit, maxWidth: 640)
        #expect(plan.camera(at: 0.3).0 < 1.05)
        #expect(plan.camera(at: 2.5).0 > 1.99)
        #expect(plan.camera(at: 5.9).0 < 1.05)
    }

    @Test func speedMapGoesBothWays() {
        let map = RecTimeMap([RecSpeed(start: 2, end: 6, rate: 2)], duration: 10)
        #expect(abs(map.played(10) - 8) < 0.0001)
        #expect(abs(map.played(4) - 3) < 0.0001)
        for t in stride(from: 0.0, through: 10, by: 0.37) {
            #expect(abs(map.source(map.played(t)) - t) < 0.0001)
        }
    }

    @Test func steadyTypingIsFound() {
        let typing = stride(from: 5.0, through: 9, by: 0.3).map { $0 } + [20]
        let speeds = RecEdit.typingSpeeds(typing)
        #expect(speeds.count == 1)
        #expect(speeds[0].start == 5 && speeds[0].rate == 3)
    }

    @Test func aspectWidensTheFrame() {
        var edit = RecEdit()
        edit.style = RecStyle()
        edit.style.aspect = "9:16"
        let meta = RecMeta(id: UUID(), created: Date(), duration: 2, width: 1280, height: 800, scale: 2, track: RecTrack(), edit: edit)
        let plan = RecPlan(meta: meta, edit: edit, maxWidth: nil)
        #expect(abs(plan.output.width / plan.output.height - 9.0 / 16) < 0.01)
        #expect(plan.content.minX >= 0 && plan.content.maxX <= plan.output.width)
    }

    @Test func oldRecordingsStillLoad() throws {
        let json = #"{"background":2,"padding":0.05,"radius":0.01,"shadow":true,"cursorSize":1.5,"smoothCursor":true,"clickRings":true,"autoZoom":true,"zoomLevel":1.8}"#
        let style = try JSONDecoder().decode(RecStyle.self, from: Data(json.utf8))
        #expect(style.background == 2 && style.aspect == "auto" && style.hideIdleCursor)
    }
    @Test func typingGetsAShot() {
        let carets = stride(from: 10.0, through: 13, by: 0.3).map { click($0, 600 + ($0 - 10) * 20, 400) }
        let zooms = RecZoomPlanner.plan(clicks: [], carets: carets, size: CGSize(width: 1280, height: 800), duration: 30)
        #expect(zooms.count == 1)
        #expect(zooms.first.map { $0.start < 10 && $0.end > 13 } == true)
    }

    @Test func cameraFollowsTheTextCursor() {
        var edit = RecEdit()
        edit.style = RecStyle()
        edit.zooms = [RecZoom(start: 1, end: 7, scale: 2)]
        var track = RecTrack()
        track.moves = [RecTrack.Point(t: 0, x: 100, y: 400)]
        track.typing = stride(from: 3.0, through: 5, by: 0.15).map { $0 }
        track.carets = stride(from: 3.0, through: 5, by: 0.15).map { click($0, 1100, 400) }
        let meta = RecMeta(id: UUID(), created: Date(), duration: 8, width: 1280, height: 800, scale: 2, track: track, edit: edit)
        let plan = RecPlan(meta: meta, edit: edit, maxWidth: 640)
        #expect(plan.camera(at: 5.5).1.x > plan.camera(at: 2.5).1.x + 300)
    }

    @Test func pointerStepsAsideWhileTyping() {
        var track = RecTrack()
        for i in 0...120 { track.moves.append(RecTrack.Point(t: Double(i) / 60, x: Double(i) * 4, y: 300)) }
        track.typing = [3, 3.2, 3.4, 3.6]
        let path = RecCursorPath(track: track, size: CGSize(width: 1000, height: 800), smoothing: 0.3)
        #expect(path.opacity(2.9) > 0.99)
        #expect(path.opacity(3.3) < 0.05)
    }

    @Test func fastCameraIsBlurred() {
        var edit = RecEdit()
        edit.style = RecStyle()
        edit.zooms = [RecZoom(start: 1.5, end: 4, scale: 2.5)]
        let meta = RecMeta(id: UUID(), created: Date(), duration: 6, width: 1280, height: 800, scale: 2, track: RecTrack(), edit: edit)
        let sharp: RecPlan = { var e = edit; e.style.motionBlur = false; return RecPlan(meta: meta, edit: e, maxWidth: 640) }()
        let blurred = RecPlan(meta: meta, edit: edit, maxWidth: 640)
        // The moment the zoom changes fastest.
        let times = stride(from: 0.5, through: 3, by: 1.0 / 60).map { $0 }
        let fastest = times.max { abs(sharp.camera(at: $0 + 0.01).0 - sharp.camera(at: $0).0) < abs(sharp.camera(at: $1 + 0.01).0 - sharp.camera(at: $1).0) }!
        let stripes = CIFilter(name: "CIStripesGenerator", parameters: ["inputWidth": 6])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 800))
        let context = CIContext()
        func pixels(_ plan: RecPlan, _ t: Double) -> [UInt8] {
            let image = plan.frame(source: stripes, time: t)
            var data = [UInt8](repeating: 0, count: Int(plan.output.width * plan.output.height) * 4)
            context.render(image, toBitmap: &data, rowBytes: Int(plan.output.width) * 4, bounds: image.extent, format: .RGBA8, colorSpace: nil)
            return data
        }
        let a = pixels(sharp, fastest), b = pixels(blurred, fastest)
        #expect(zip(a, b).contains { abs(Int($0) - Int($1)) > 30 })
        // A still camera looks the same either way.
        #expect(pixels(sharp, 0.2) == pixels(blurred, 0.2))
    }
    @Test func recordingToolsAreListed() {
        let tools = MCPTools.all
        let names = tools.map(\.name)
        #expect(Set(names).count == names.count)
        for name in ["recording_start", "recording_stop", "recording_info", "recording_edit", "recording_frame", "recording_export"] {
            #expect(names.contains(name))
        }
        #expect(tools.allSatisfy { JSONSerialization.isValidJSONObject($0.descriptor) })
    }
}
