import AppKit
import AVFoundation
import ScreenCaptureKit

/// Writes ScreenCaptureKit's samples into a .mov: HEVC video (fine for 5K and Retina), system sound and the
/// microphone as separate AAC tracks. Lives on its own queue; the main actor only starts and stops it.
final class RecWriter: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "nabiz.rec.writer", qos: .userInteractive)
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let sound: AVAssetWriterInput?
    private let microphone: AVAssetWriterInput?
    private let lock = NSLock()
    private var started = false
    private var first = CMTime.invalid
    private var frames = 0
    /// Called (on the writer's queue) when ScreenCaptureKit stops on its own: display asleep, permission gone.
    var onStop: (@Sendable (Error?) -> Void)?

    init(url: URL, width: Int, height: Int, fps: Int, sound wantsSound: Bool, microphone wantsMicrophone: Bool) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        // Written in pieces, so a crash still leaves a playable file.
        writer.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 600)
        let bitrate = min(Double(width * height * fps) * 0.09, 120_000_000)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps,
                AVVideoAllowFrameReorderingKey: false,
            ] as [String: Any],
        ])
        video.expectsMediaDataInRealTime = true
        writer.add(video)
        func audioInput(channels: Int) -> AVAssetWriterInput {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: channels == 1 ? 96_000 : 160_000,
            ])
            input.expectsMediaDataInRealTime = true
            return input
        }
        sound = wantsSound ? audioInput(channels: 2) : nil
        microphone = wantsMicrophone ? audioInput(channels: 1) : nil
        if let sound { writer.add(sound) }
        if let microphone { writer.add(microphone) }
        super.init()
    }

    /// The first frame's time on the host clock, which the pointer samples are measured against.
    var firstFrameSeconds: Double? {
        lock.lock(); defer { lock.unlock() }
        return first.isValid ? first.seconds : nil
    }

    var frameCount: Int {
        lock.lock(); defer { lock.unlock() }
        return frames
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard buffer.isValid else { return }
        switch type {
        case .screen:
            // Only complete frames carry pixels; idle ones just say "nothing changed".
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
            let time = buffer.presentationTimeStamp
            if !started {
                guard writer.startWriting() else { onStop?(writer.error); return }
                writer.startSession(atSourceTime: time)
                lock.lock(); started = true; first = time; lock.unlock()
            }
            if video.isReadyForMoreMediaData, video.append(buffer) {
                lock.lock(); frames += 1; lock.unlock()
            }
        case .audio:
            if started, let sound, sound.isReadyForMoreMediaData { sound.append(buffer) }
        default:
            if #available(macOS 15.0, *), type == .microphone, started, let microphone, microphone.isReadyForMoreMediaData {
                microphone.append(buffer)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?(error)
    }

    /// Ends the file at `end` (host time), so the last still frame lasts until the moment Stop was pressed.
    func finish(at end: CMTime) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard started else { writer.cancelWriting(); continuation.resume(returning: false); return }
                video.markAsFinished()
                sound?.markAsFinished()
                microphone?.markAsFinished()
                writer.endSession(atSourceTime: CMTimeMaximum(end, first))
                writer.finishWriting { [self] in
                    continuation.resume(returning: self.writer.status == .completed)
                }
            }
        }
    }
}

/// Records the screen (or part of it) with the pointer kept out of the picture: its path, clicks and shape are
/// written down instead, so the editor can draw it smooth and large and zoom where you click.
@MainActor
final class RecRecorder {
    static let shared = RecRecorder()

    private(set) var isRecording = false
    private(set) var startedAt: Date?
    var onChange: () -> Void = {}

    private var stream: SCStream?
    private var writer: RecWriter?
    private var id = UUID()
    private var screen: NSScreen?
    private var area = CGRect.zero
    private var scale: CGFloat = 2
    private var size = CGSize.zero
    private var timer: Timer?
    private var monitors: [Any] = []
    /// Pointer samples and clicks in host-clock seconds, converted when the recording ends.
    private var moves: [RecTrack.Point] = []
    private var clicks: [RecTrack.Point] = []
    private var shapes: [RecTrack.Shape] = []
    private var cursors: [RecCursor] = []
    private var cursorKeys: [String] = []
    private var lastShapeCheck = 0.0
    private var activity: NSObjectProtocol?
    private var camera: RecCamera?
    private var keys: [RecTrack.Key] = []
    private var typing: [Double] = []
    private var typingKinds: [Int] = []

    private static var hostNow: Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    /// Starts recording `rect` (points, top-left origin, on `screen`); nil records the whole screen.
    /// With `window`, only that window is recorded (even when something covers it); `rect` is then its frame.
    func start(screen: NSScreen, rect: CGRect?, window windowID: CGWindowID? = nil, sound: Bool, microphone: Bool,
               camera wantsCamera: Bool = false) async throws {
        guard !isRecording else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == number }) else { throw RecError.noDisplay }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let picked = windowID.flatMap { id in content.windows.first { $0.windowID == id } }
        let filter = picked.map { SCContentFilter(desktopIndependentWindow: $0) }
            ?? SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])

        let full = CGRect(origin: .zero, size: screen.frame.size)
        // A window keeps its whole size, even where it runs off the screen.
        let area = picked != nil ? (rect ?? full).integral : (rect ?? full).intersection(full).integral
        let scale = screen.backingScaleFactor
        // Even sizes: HEVC wants them.
        let width = Int(area.width * scale) / 2 * 2, height = Int(area.height * scale) / 2 * 2
        guard width > 16, height > 16 else { throw RecError.tooSmall }

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        if picked != nil {
            config.ignoreShadowsSingleWindow = true
            config.scalesToFit = true
        } else if area != full {
            config.sourceRect = area
        }
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        config.queueDepth = 8
        config.capturesAudio = sound
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        if #available(macOS 15.0, *) { config.captureMicrophone = microphone }

        let id = UUID()
        try FileManager.default.createDirectory(at: RecStore.folder(for: id), withIntermediateDirectories: true)
        let micOn: Bool = if #available(macOS 15.0, *) { microphone } else { false }
        let writer = try RecWriter(url: RecStore.video(for: id), width: width, height: height, fps: 60, sound: sound, microphone: micOn)
        // macOS's own "Stop sharing", a sleeping display or a lost permission ends it like the stop button.
        writer.onStop = { _ in Task { @MainActor in RecControl.stop() } }
        let stream = SCStream(filter: filter, configuration: config, delegate: writer)
        try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
        if sound { try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: writer.queue) }
        if #available(macOS 15.0, *), micOn { try stream.addStreamOutput(writer, type: .microphone, sampleHandlerQueue: writer.queue) }

        self.id = id
        self.screen = screen
        self.area = area
        self.scale = scale
        self.size = CGSize(width: width, height: height)
        moves = []; clicks = []; shapes = []; cursors = []; cursorKeys = []; keys = []; typing = []; typingKinds = []
        try await stream.startCapture()
        if wantsCamera {
            let camera = RecCamera()
            do {
                try camera.start(to: RecStore.folder(for: id).appendingPathComponent("camera.mov"))
                self.camera = camera
            } catch {
                ShotLog.write("camera failed: \(error)")
            }
        }
        self.stream = stream
        self.writer = writer
        isRecording = true
        startedAt = Date()
        startTracking()
        activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled],
                                                         reason: "Screen recording")
        onChange()
    }

    /// Stops and saves; returns the recording, or nil if nothing was captured.
    func stop() async -> RecMeta? {
        guard isRecording, let stream, let writer else { return nil }
        isRecording = false
        stopTracking()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        let end = CMClockGetTime(CMClockGetHostTimeClock())
        try? await stream.stopCapture()
        self.stream = nil
        self.writer = nil
        let cameraStart = await camera?.stop()
        camera = nil
        let ok = await writer.finish(at: end)
        onChange()
        guard ok, let first = writer.firstFrameSeconds, writer.frameCount > 0 else {
            RecStore.delete(id)
            return nil
        }
        let shift = { (point: RecTrack.Point) in RecTrack.Point(t: max(0, point.t - first), x: point.x, y: point.y) }
        var track = RecTrack(moves: moves.map(shift), clicks: clicks.map(shift).filter { $0.t >= 0 })
        track.shapes = shapes.map { RecTrack.Shape(t: max(0, $0.t - first), index: $0.index) }
        track.keys = keys.map { RecTrack.Key(t: $0.t - first, text: $0.text) }.filter { $0.t >= 0 }
        let typed = zip(typing, typingKinds).map { ($0 - first, $1) }.filter { $0.0 >= 0 }
        track.typing = typed.map(\.0)
        track.typingKinds = typed.map(\.1)
        let duration = max(0.1, end.seconds - first)
        var edit = RecEdit()
        if edit.style.autoZoom {
            edit.zooms = RecZoomPlanner.plan(clicks: track.clicks, size: size, duration: duration)
            edit.zoomsMade = true
        }
        var meta = RecMeta(id: id, created: startedAt ?? Date(), duration: duration, width: Int(size.width), height: Int(size.height),
                           scale: scale, track: track, edit: edit, cursors: cursors)
        meta.cameraOffset = cameraStart.map { $0 - first }
        RecStore.save(meta)
        return meta
    }

    // MARK: Pointer

    private func startTracking() {
        lastShapeCheck = 0
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated { RecRecorder.shared.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        let click: (NSEvent) -> Void = { _ in MainActor.assumeIsolated { RecRecorder.shared.click() } }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: click) { monitors.append(global) }
        // Keys reach a global monitor only with Accessibility access (Nabız asks for it for pasting).
        let key: (NSEvent) -> Void = { event in
            let code = Int(event.keyCode), flags = event.modifierFlags, characters = event.charactersIgnoringModifiers, repeated = event.isARepeat
            MainActor.assumeIsolated { RecRecorder.shared.key(code, flags, characters, repeated: repeated) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: key) { monitors.append(global) }
        sample()
    }

    private func stopTracking() {
        timer?.invalidate()
        timer = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    /// The pointer in the recorded area's pixels, top-left origin.
    private func pointer() -> (Double, Double)? {
        guard let screen else { return nil }
        let global = NSEvent.mouseLocation
        let x = (global.x - screen.frame.minX - area.minX) * scale
        let y = (screen.frame.maxY - global.y - area.minY) * scale
        return (Double(x), Double(y))
    }

    private func sample() {
        guard isRecording, let (x, y) = pointer() else { return }
        let now = Self.hostNow
        if let last = moves.last, abs(last.x - x) < 0.25, abs(last.y - y) < 0.25 {
            // Still: no new sample, but keep checking the shape now and then.
        } else {
            moves.append(RecTrack.Point(t: now, x: x, y: y))
        }
        if now - lastShapeCheck > 0.1 {
            lastShapeCheck = now
            recordShape(at: now)
        }
    }

    /// Shortcuts are written down as they look (⌘⇧4); ordinary typing only as a moment, never as letters.
    private func key(_ code: Int, _ flags: NSEvent.ModifierFlags, _ characters: String?, repeated: Bool) {
        guard isRecording, !repeated else { return }
        let now = Self.hostNow
        let held = flags.intersection([.command, .control, .option])
        let special: [Int: String] = [36: "↩", 76: "↩", 53: "⎋", 48: "⇥", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        if !held.isEmpty {
            let (_, symbols) = HotKey.modifiers(flags)
            keys.append(RecTrack.Key(t: now, text: symbols + HotKey.keyName(code, characters)))
        } else if let name = special[code] {
            keys.append(RecTrack.Key(t: now, text: name))
        } else {
            typing.append(now)
            typingKinds.append(RecClickSound.kind(forKeyCode: code))
        }
    }

    private static func sharp(_ image: NSImage) -> NSBitmapImageRep? {
        let width = Int(image.size.width * 4), height = Int(image.size.height * 4)
        guard width > 0, height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func click() {
        guard isRecording, let (x, y) = pointer() else { return }
        clicks.append(RecTrack.Point(t: Self.hostNow, x: x, y: y))
    }

    /// The pointer's look (arrow, I-beam, hand…), saved once per kind and noted when it changes.
    private func recordShape(at time: Double) {
        guard let cursor = NSCursor.currentSystem else { return }
        let image = cursor.image
        guard let tiff = image.tiffRepresentation else { return }
        let key = "\(image.size.width)x\(image.size.height)@\(cursor.hotSpot.x),\(cursor.hotSpot.y)#\(tiff.hashValue)"
        let index: Int
        if let found = cursorKeys.firstIndex(of: key) {
            index = found
        } else {
            index = cursors.count
            let file = "cursor-\(index).png"
            // Drawn at 4× from the cursor's best representation, so it stays sharp when shown large and zoomed.
            if let png = Self.sharp(image)?.representation(using: .png, properties: [:]) {
                try? png.write(to: RecStore.folder(for: id).appendingPathComponent(file))
            }
            cursorKeys.append(key)
            cursors.append(RecCursor(file: file, width: image.size.width, height: image.size.height,
                                     hotX: cursor.hotSpot.x, hotY: cursor.hotSpot.y))
        }
        if shapes.last?.index != index { shapes.append(RecTrack.Shape(t: time, index: index)) }
    }
}

enum RecError: LocalizedError {
    case noDisplay, tooSmall, noCamera

    var errorDescription: String? {
        switch self {
        case .noDisplay: L("Ekran bulunamadı", "Couldn't find the display")
        case .tooSmall: L("Alan çok küçük", "The area is too small")
        case .noCamera: L("Kamera bulunamadı", "No camera found")
        }
    }
}
