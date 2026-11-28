// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import AVFoundation

/// Screen recordings for an AI app: record while it drives the Mac, read what happened (clicks, typing, shortcuts),
/// shape the video (zooms, captions, notes, speed-ups, cuts, look), check single frames and export the file.
@MainActor
extension MCPTools {
    static var recording: [MCPTool] {
        [
            MCPTool(name: "recording_start", title: "Start a screen recording",
                    description: """
                    Starts recording at once (no countdown), with Nabız's red indicator in the menu bar. Record the whole screen, one app's \
                    front window (target "window" + app), or an area (target "area" + x, y, width, height in points from the top-left of the \
                    main screen). Nabız tracks the pointer, clicks, typing and the text cursor, and later zooms on them by itself. For a \
                    launch video: record a window or an area of about 16:9, move the pointer calmly, pause ~1 s after each step, and \
                    stop with recording_stop.
                    """,
                    group: .commands, readOnly: false,
                    properties: [
                        "target": ["type": "string", "enum": ["screen", "window", "area"], "description": "Default: screen"],
                        "app": ["type": "string", "description": "For target window: the app whose front window is recorded"],
                        "x": ["type": "number"], "y": ["type": "number"], "width": ["type": "number"], "height": ["type": "number"],
                        "display": ["type": "integer", "description": "Which display for screen/area, 0 = main"],
                        "system_audio": ["type": "boolean", "description": "Record the Mac's sound (default true)"],
                        "microphone": ["type": "boolean", "description": "Default false"],
                        "camera": ["type": "boolean", "description": "Webcam bubble (default false)"],
                    ]) { args in
                try await startRecording(args)
            },
            MCPTool(name: "recording_stop", title: "Stop the screen recording",
                    description: "Stops the running recording and saves it. Returns its id, length, size and how many zooms were planned. open_editor shows Nabız's editor to the user.",
                    group: .commands, readOnly: false,
                    properties: ["open_editor": ["type": "boolean", "description": "Default false"]]) { args in
                guard RecRecorder.shared.isRecording else { throw MCPToolError("Nothing is being recorded.") }
                guard let meta = await RecControl.stopNow(openEditor: args["open_editor"] as? Bool ?? false) else {
                    throw MCPToolError("The recording came out empty.")
                }
                return json(summary(meta))
            },
            MCPTool(name: "recording_list", title: "List screen recordings",
                    description: "Nabız's screen recordings, newest first: id, date, length and size.",
                    group: .commands,
                    properties: ["limit": ["type": "integer", "minimum": 1, "maximum": 50]]) { args in
                json(RecStore.all().prefix(min(max(int(args["limit"]) ?? 10, 1), 50)).map(summary))
            },
            MCPTool(name: "recording_info", title: "Read a screen recording",
                    description: """
                    Everything about one recording, to plan the edit: its clicks (seconds, and x/y from 0 to 1 from the top-left), \
                    typing bursts, shortcuts pressed, and the current edit as JSON (style, zooms, speeds, cuts, captions, notes, trim). \
                    Times are seconds of the original recording, before speed-ups.
                    """,
                    group: .commands,
                    properties: ["id": ["type": "string", "description": "Default: the newest"]]) { args in
                let meta = try recording(args["id"])
                var info = summary(meta)
                let w = Double(max(meta.width, 1)), h = Double(max(meta.height, 1))
                info["clicks"] = meta.track.clicks.map { ["t": round($0.t, 2), "x": round($0.x / w, 3), "y": round($0.y / h, 3)] }
                info["shortcuts"] = meta.track.keys.map { ["t": round($0.t, 2), "keys": $0.text] }
                info["typing"] = bursts(meta.track.typing).map { ["start": round($0.0, 2), "end": round($0.1, 2), "keys": $0.2] }
                info["edit"] = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(meta.edit))) ?? [:]
                return json(info)
            },
            MCPTool(name: "recording_edit", title: "Edit a screen recording",
                    description: """
                    Changes a recording; leave out what should stay. style: any of the style keys recording_info shows (e.g. \
                    backgroundKind "gradient"/"solid"/"image"/"wallpaper", background 0-9, padding 0-0.2, radius, shadow, aspect \
                    "auto"/"16:9"/"9:16"/"1:1"/"4:3", cursorSize 1-5, smoothCursor, clickBounce, clickRings, clickSound, keySound, \
                    motionBlur, hideIdleCursor, showKeys, showCaptions, zoomLevel, camera, cameraCorner). zooms, speeds, cuts, captions, \
                    notes: each replaces that whole list. zoom {start, end, scale 1.2-3, focusX?, focusY? (0-1, leave out to follow the \
                    pointer and the text cursor)}; speed {start, end, rate 1.5-8}; cut {start, end}; caption {start, end, text}; note \
                    {start, end, text, x, y, arrow?, toX?, toY?} (a label on the video, 0-1 from the top-left). trim_start/trim_end in \
                    seconds (trim_end 0 = the end). auto_zooms: plan zooms again from the clicks and typing. speed_up_typing: add \
                    speed-ups over long typing. Times are seconds of the original recording. Check the result with recording_frame.
                    """,
                    group: .commands, readOnly: false, destructive: true,
                    properties: [
                        "id": ["type": "string", "description": "Default: the newest"],
                        "style": ["type": "object"],
                        "zooms": ["type": "array", "items": ["type": "object"]],
                        "speeds": ["type": "array", "items": ["type": "object"]],
                        "cuts": ["type": "array", "items": ["type": "object"]],
                        "captions": ["type": "array", "items": ["type": "object"]],
                        "notes": ["type": "array", "items": ["type": "object"]],
                        "trim_start": ["type": "number"], "trim_end": ["type": "number"],
                        "auto_zooms": ["type": "boolean"], "speed_up_typing": ["type": "boolean"],
                    ]) { args in
                try editRecording(args)
            },
            MCPTool(name: "recording_frame", title: "See a frame of a recording",
                    description: "Draws the finished video (with its style, zooms, pointer, captions and notes) at one moment: returns the picture itself and the path of the PNG it was saved as. time: seconds of the original recording.",
                    group: .commands,
                    properties: ["id": ["type": "string"], "time": ["type": "number"], "width": ["type": "integer", "description": "Default 1600"]],
                    required: ["time"], content: { args in
                let (url, png) = try await frame(args)
                return [.image(png, mimeType: "image/png"), .text(url.path)]
            }),
            MCPTool(name: "recording_export", title: "Export a screen recording",
                    description: "Makes the finished file: MP4 at full size, 4K or 1080p, or a GIF. Saved in the screenshots folder unless path is given. Returns the file's path.",
                    group: .commands, readOnly: false,
                    properties: [
                        "id": ["type": "string", "description": "Default: the newest"],
                        "format": ["type": "string", "enum": ["original", "4k", "1080p", "gif"], "description": "Default 1080p"],
                        "path": ["type": "string", "description": "Where to save, ending in .mp4 or .gif"],
                    ]) { args in
                try await export(args)
            },
            MCPTool(name: "recording_open", title: "Open a recording in the editor",
                    description: "Shows Nabız's recording editor to the user, on this recording.",
                    group: .commands, readOnly: false,
                    properties: ["id": ["type": "string", "description": "Default: the newest"]]) { args in
                let meta = try recording(args["id"])
                RecEditor.show(meta)
                return "Opened."
            },
        ]
    }

    // MARK: Recording

    private static func startRecording(_ args: [String: Any]) async throws -> String {
        guard !RecRecorder.shared.isRecording else { throw MCPToolError("A recording is already running; stop it first.") }
        guard ScreenAccess.granted else {
            ScreenAccess.ask(for: .area)
            throw MCPToolError("Nabız needs Screen Recording permission; the user was shown how to allow it.")
        }
        let target = args["target"] as? String ?? "screen"
        let sound = args["system_audio"] as? Bool ?? true
        let microphone = args["microphone"] as? Bool ?? false
        var camera = args["camera"] as? Bool ?? false
        if camera, !(await RecCamera.allowed()) { camera = false }
        let displays = NSScreen.screens
        guard !displays.isEmpty else { throw MCPToolError("No display.") }
        let display = displays[min(max(int(args["display"]) ?? 0, 0), displays.count - 1)]
        var screen = display, rect: CGRect?, window: CGWindowID?
        switch target {
        case "window":
            let app = try string(args["app"], "app")
            guard let found = frontWindow(of: app) else { throw MCPToolError("No window of \(app) on screen. Open it first (open_app).") }
            (screen, rect, window) = found
        case "area":
            guard let x = double(args["x"]), let y = double(args["y"]), let w = double(args["width"]), let h = double(args["height"]), w > 16, h > 16 else {
                throw MCPToolError("An area needs x, y, width and height in points.")
            }
            rect = CGRect(x: x, y: y, width: w, height: h).intersection(CGRect(origin: .zero, size: screen.frame.size))
        case "screen":
            break
        default:
            throw MCPToolError("target is screen, window or area.")
        }
        do {
            try await RecControl.recordNow(screen: screen, rect: rect, window: window, sound: sound, microphone: microphone, camera: camera)
        } catch {
            throw MCPToolError("Recording didn't start: \(error.localizedDescription)")
        }
        let area = rect ?? CGRect(origin: .zero, size: screen.frame.size)
        return "Recording \(target == "window" ? "the window" : target == "area" ? "the area" : "the screen") (\(Int(area.width))×\(Int(area.height)) pt). Call recording_stop when done."
    }

    /// The front window of an app, as the screen it is on and its frame there (points, top-left origin).
    static func frontWindow(of app: String) -> (NSScreen, CGRect, CGWindowID)? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let wanted = app.lowercased()
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        for info in list {
            guard let owner = (info[kCGWindowOwnerName as String] as? String)?.lowercased(), owner == wanted || owner.contains(wanted),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsInfo = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary), bounds.width > 120, bounds.height > 80
            else { continue }
            // Global top-left to the screen it is mostly on.
            let center = NSPoint(x: bounds.midX, y: mainHeight - bounds.midY)
            let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.screens[0]
            let top = mainHeight - screen.frame.maxY
            return (screen, CGRect(x: bounds.minX - screen.frame.minX, y: bounds.minY - top, width: bounds.width, height: bounds.height), number)
        }
        return nil
    }

    // MARK: Reading

    private static func recording(_ value: Any?) throws -> RecMeta {
        if let text = value as? String, !text.isEmpty {
            guard let id = UUID(uuidString: text), let meta = RecStore.load(id) else { throw MCPToolError("No recording \(text). Call recording_list.") }
            return meta
        }
        guard let latest = RecStore.all().first else { throw MCPToolError("There are no recordings yet.") }
        return latest
    }

    private static func summary(_ meta: RecMeta) -> [String: Any] {
        [
            "id": meta.id.uuidString,
            "created": meta.created.formatted(.iso8601),
            "seconds": round(meta.duration, 2),
            "width": meta.width, "height": meta.height,
            "clicks": meta.track.clicks.count,
            "zooms": meta.edit.zooms.count,
        ]
    }

    /// Runs of typing: keys less than 1.2 s apart.
    private static func bursts(_ typing: [Double]) -> [(Double, Double, Int)] {
        var result: [(Double, Double, Int)] = []
        for t in typing.sorted() {
            if let last = result.last, t - last.1 < 1.2 {
                result[result.count - 1] = (last.0, t, last.2 + 1)
            } else {
                result.append((t, t, 1))
            }
        }
        return result
    }

    /// Written to JSON as it reads ("0.42", not "0.41999999999999998").
    private static func round(_ value: Double, _ digits: Int) -> NSDecimalNumber {
        NSDecimalNumber(string: String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), value))
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    // MARK: Editing

    private static func editRecording(_ args: [String: Any]) throws -> String {
        var meta = try recording(args["id"])
        let reopen = RecEditor.closeIfOpen(meta.id)
        // The editor saves as it closes; start from that.
        meta = RecStore.load(meta.id) ?? meta
        var edit = meta.edit
        do {
            if var style = args["style"] as? [String: Any] {
                // A picture behind the recording only from Settings: over MCP it would read any image on disk.
                style.removeValue(forKey: "backgroundImage")
                if style["backgroundKind"] as? String == "image" { style.removeValue(forKey: "backgroundKind") }
                edit.style = try merged(edit.style, style)
            }
            if let items = args["zooms"] as? [[String: Any]] {
                edit.zooms = try items.map { try merged(RecZoom(start: 0, end: 0, scale: edit.style.zoomLevel), $0) }
                edit.zoomsMade = true
            }
            if let items = args["speeds"] as? [[String: Any]] { edit.speeds = try items.map { try merged(RecSpeed(start: 0, end: 0, rate: 2), $0) } }
            if let items = args["cuts"] as? [[String: Any]] { edit.cuts = try items.map { try merged(RecCut(start: 0, end: 0), $0) } }
            if let items = args["captions"] as? [[String: Any]] { edit.captions = try items.map { try merged(RecCaption(start: 0, end: 0, text: ""), $0) } }
            if let items = args["notes"] as? [[String: Any]] { edit.notes = try items.map { try merged(RecNote(start: 0, end: 0, text: ""), $0) } }
        } catch {
            if reopen { RecEditor.show(meta) }
            throw MCPToolError("Couldn't read the changes: \(error.localizedDescription). Call recording_info for the shapes.")
        }
        if let start = double(args["trim_start"]) { edit.trimStart = min(max(start, 0), meta.duration) }
        if let end = double(args["trim_end"]) { edit.trimEnd = min(max(end, 0), meta.duration) }
        if args["auto_zooms"] as? Bool == true {
            edit.zooms = RecEdit.autoZooms(meta: meta)
            edit.zoomsMade = true
        }
        if args["speed_up_typing"] as? Bool == true { edit.speeds += RecEdit.typingSpeeds(meta.track.typing) }
        // Keep every part inside the recording and in order.
        let fit = { (start: Double, end: Double) in (min(max(start, 0), meta.duration), min(max(end, 0), meta.duration)) }
        edit.zooms = edit.zooms.compactMap { var z = $0; (z.start, z.end) = fit(z.start, z.end); z.scale = min(max(z.scale, 1), 5); return z.end > z.start ? z : nil }
            .sorted { $0.start < $1.start }
        edit.speeds = edit.speeds.compactMap { var s = $0; (s.start, s.end) = fit(s.start, s.end); s.rate = min(max(s.rate, 1), 16); return s.end > s.start ? s : nil }
            .sorted { $0.start < $1.start }
        edit.cuts = edit.cuts.compactMap { var c = $0; (c.start, c.end) = fit(c.start, c.end); return c.end > c.start ? c : nil }
        edit.captions = edit.captions.filter { $0.end > $0.start }
        edit.notes = edit.notes.filter { $0.end > $0.start }
        meta.edit = edit
        RecStore.save(meta)
        if reopen { RecEditor.show(meta) }
        return "Saved: \(edit.zooms.count) zooms, \(edit.speeds.count) speed-ups, \(edit.cuts.count) cuts, \(edit.captions.count) captions, \(edit.notes.count) notes."
    }

    /// `value` with the given keys replaced (and fresh defaults for the rest).
    private static func merged<T: Codable>(_ value: T, _ changes: [String: Any]) throws -> T {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] ?? [:]
        for (key, change) in changes where key != "id" { object[key] = change }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    // MARK: Frames and files

    private static func frame(_ args: [String: Any]) async throws -> (URL, Data) {
        let meta = try recording(args["id"])
        guard let time = double(args["time"]) else { throw MCPToolError("time is required") }
        let width = CGFloat(min(max(int(args["width"]) ?? 1600, 320), 3840))
        guard let built = await RecPlan.build(meta: meta, speeds: RecTimeMap(meta.edit.timeSegments, duration: meta.duration).speeds) else {
            throw MCPToolError("Couldn't open the recording's video.")
        }
        let plan = RecPlan(meta: meta, edit: meta.edit, maxWidth: width)
        let generator = AVAssetImageGenerator(asset: built.asset)
        generator.videoComposition = plan.composition(for: built)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let played = plan.map.played(min(max(time, 0), meta.duration - 0.02))
        let image: CGImage
        do {
            image = try await generator.image(at: CMTime(seconds: played, preferredTimescale: 600)).image
        } catch {
            throw MCPToolError("Couldn't draw that moment: \(error.localizedDescription)")
        }
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Nabiz/frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(meta.id.uuidString.prefix(8))-\(String(format: "%.2f", time)).png")
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil else {
            throw MCPToolError("Couldn't save the frame.")
        }
        return (url, png)
    }

    private static func export(_ args: [String: Any]) async throws -> String {
        let meta = try recording(args["id"])
        let kind: RecExport.Kind = switch args["format"] as? String ?? "1080p" {
        case "original": .original
        case "4k": .uhd
        case "gif": .gif
        default: .hd
        }
        var target: URL?
        if let path = args["path"] as? String, !path.isEmpty {
            let ext = kind == .gif ? "gif" : "mp4"
            var url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath()
            guard url.pathExtension.lowercased() == ext else { throw MCPToolError("The path must end in .\(ext).") }
            // Only into the user's own Desktop, Movies, Downloads or Documents (or the screenshots folder), and never over a file.
            let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
            let allowed = ["Desktop", "Movies", "Downloads", "Documents"].map { home + "/" + $0 + "/" } + [Capture.folder.resolvingSymlinksInPath().path + "/"]
            guard allowed.contains(where: { url.path.hasPrefix($0) }) else {
                throw MCPToolError("Exports can go to Desktop, Movies, Downloads or Documents only.")
            }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let base = url.deletingPathExtension().lastPathComponent
            var number = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = url.deletingLastPathComponent().appendingPathComponent("\(base) \(number).\(ext)")
                number += 1
            }
            target = url
        }
        guard let url = await RecExport.run(meta, edit: meta.edit, kind: kind, to: target, progress: { _ in }) else {
            throw MCPToolError("The export failed.")
        }
        return url.path
    }
}
