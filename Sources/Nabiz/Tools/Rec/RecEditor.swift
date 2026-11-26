import AppKit
import AVFoundation
import SwiftUI

/// The recording editor: the styled video in the middle, its look on the right, a timeline with the zooms, the
/// speed-ups, the cuts and the notes along the bottom, export at the top. Every change shows at once, is saved
/// with the recording, and can be undone.
@MainActor
enum RecEditor {
    private static var open: [UUID: NSWindow] = [:]
    private static var monitors: [UUID: Any] = [:]

    static func show(_ meta: RecMeta) {
        if let window = open[meta.id] { window.makeKeyAndOrderFront(nil); return }
        let model = RecEditorModel(meta: meta)
        let controller = NSHostingController(rootView: RecEditorView(model: model))
        let window = RecEditorWindow(contentViewController: controller)
        window.model = model
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        WindowChrome.apply(window)
        window.title = L("Ekran kaydı", "Screen recording")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 980, height: 640)
        let screen = (NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900))
        let size = NSSize(width: min(1320, screen.width * 0.92), height: min(880, screen.height * 0.92))
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2))
        open[meta.id] = window
        // Keys go to the editor from anywhere in the window, except while a text field is being typed in.
        let number = window.windowNumber
        monitors[meta.id] = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.windowNumber == number else { return event }
            let code = Int(event.keyCode), flags = event.modifierFlags, characters = event.charactersIgnoringModifiers
            let handled = MainActor.assumeIsolated {
                guard let window = NSApp.window(withWindowNumber: number), !(window.firstResponder is NSText) else { return false }
                return model.handleKey(code: code, flags: flags, characters: characters)
            }
            return handled ? nil : event
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                if let monitor = monitors.removeValue(forKey: meta.id) { NSEvent.removeMonitor(monitor) }
                model.close()
                open[meta.id] = nil
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            NSRunningApplication.current.activate(from: front, options: [])
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the recording's editor (which saves it) and says whether one was open; used before an AI app edits it.
    static func closeIfOpen(_ id: UUID) -> Bool {
        guard let window = open[id] else { return false }
        window.close()
        return true
    }

    /// The most recent recording, if any.
    static func showLatest() {
        if let latest = RecStore.all().first { show(latest) } else { Monitor.panelActions.flash(L("Henüz kayıt yok", "No recordings yet")) }
    }
}

/// The editor's window answers Edit → Undo / Redo (⌘Z, ⇧⌘Z) for the edit, unless a text field takes them first.
final class RecEditorWindow: NSWindow {
    weak var model: RecEditorModel?

    @objc func undo(_ sender: Any?) { MainActor.assumeIsolated { model?.undo() } }
    @objc func redo(_ sender: Any?) { MainActor.assumeIsolated { model?.redo() } }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): MainActor.assumeIsolated { model?.canUndo ?? false }
        case #selector(redo(_:)): MainActor.assumeIsolated { model?.canRedo ?? false }
        default: super.validateMenuItem(item)
        }
    }
}

/// What is picked on the timeline; the inspector shows its settings.
enum RecSelection: Equatable {
    case zoom(UUID), speed(UUID), cut(UUID), note(UUID)
}

/// The inspector's pages.
enum RecTab: String, CaseIterable, Identifiable {
    case frame, pointer, zoom, camera, text, sound
    var id: String { rawValue }

    var title: String {
        switch self {
        case .frame: L("Çerçeve", "Frame")
        case .pointer: L("İmleç", "Pointer")
        case .zoom: L("Yakınlaştırma", "Zoom")
        case .camera: L("Kamera", "Camera")
        case .text: L("Yazı", "Text")
        case .sound: L("Ses", "Sound")
        }
    }

    var symbol: String {
        switch self {
        case .frame: "photo.artframe"
        case .pointer: "cursorarrow.rays"
        case .zoom: "plus.magnifyingglass"
        case .camera: "video"
        case .text: "captions.bubble"
        case .sound: "speaker.wave.2"
        }
    }
}

@MainActor
@Observable
final class RecEditorModel {
    var meta: RecMeta
    var edit: RecEdit {
        didSet {
            guard edit != oldValue else { return }
            if !restoring {
                // A burst of changes (a slider drag) is one undo step.
                if Date() > burstEnds {
                    history.append(oldValue)
                    if history.count > 150 { history.removeFirst() }
                    future.removeAll()
                }
                burstEnds = Date().addingTimeInterval(0.6)
            }
            canUndo = !history.isEmpty
            canRedo = !future.isEmpty
            if edit.style != oldValue.style { edit.style.save() }
            meta.edit = edit
            RecStore.save(meta)
            scheduleRebuild()
        }
    }
    /// Playhead, in seconds of the recording (not of the sped-up result).
    var time = 0.0
    var playing = false
    var selection: RecSelection?
    var tab: RecTab = .frame
    /// Captions being recognised.
    var transcribing = false
    var exportProgress: Double?
    var toast: String?
    var thumbnails: [CGImage] = []
    /// Loudness along the recording, 0…1, for the timeline's waveform.
    var waveform: [Float] = []
    private(set) var canUndo = false
    private(set) var canRedo = false
    /// The look being shown; its time map turns recording time into played time.
    private(set) var plan: RecPlan

    let player = AVPlayer()
    @ObservationIgnored private let asset: AVURLAsset
    @ObservationIgnored private var built: RecPlan.Built?
    @ObservationIgnored private var builtKey = ""
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var history: [RecEdit] = []
    @ObservationIgnored private var future: [RecEdit] = []
    @ObservationIgnored private var restoring = false
    @ObservationIgnored private var burstEnds = Date.distantPast

    init(meta: RecMeta) {
        self.meta = meta
        edit = meta.edit
        asset = AVURLAsset(url: RecStore.video(for: meta.id))
        plan = RecPlan(meta: meta, edit: meta.edit, maxWidth: 1600)
        player.actionAtItemEnd = .pause
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        Task {
            await rebuild()
            seek(edit.trimStart)
            await makeThumbnails()
        }
    }

    var duration: Double { meta.duration }
    var trimEnd: Double { edit.trimEnd > edit.trimStart ? edit.trimEnd : duration }
    /// How long the result plays, trimmed, cut and sped up.
    var playedLength: Double { plan.map.played(trimEnd) - plan.map.played(edit.trimStart) }
    var hasCamera: Bool { meta.cameraOffset != nil }

    // MARK: Undo

    func undo() {
        guard let previous = history.popLast() else { return }
        future.append(edit)
        restoring = true
        edit = previous
        restoring = false
        burstEnds = .distantPast
        dropStaleSelection()
    }

    func redo() {
        guard let next = future.popLast() else { return }
        history.append(edit)
        restoring = true
        edit = next
        restoring = false
        burstEnds = .distantPast
        dropStaleSelection()
    }

    private func dropStaleSelection() {
        guard let selection else { return }
        let exists = switch selection {
        case let .zoom(id): edit.zooms.contains { $0.id == id }
        case let .speed(id): edit.speeds.contains { $0.id == id }
        case let .cut(id): edit.cuts.contains { $0.id == id }
        case let .note(id): edit.notes.contains { $0.id == id }
        }
        if !exists { self.selection = nil }
    }

    // MARK: Playback

    /// Plays the kept part over and over.
    var looping = false

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        time = plan.map.source(seconds)
        guard playing, player.rate == 0 else { return }
        // At the end: start over when looping, else stop there.
        if looping, time >= trimEnd - 0.1 {
            seek(edit.trimStart)
            player.play()
        } else {
            playing = false
        }
    }

    /// Space: play or pause; at the end it starts over from the beginning.
    func togglePlay() {
        if playing {
            player.pause()
            playing = false
        } else {
            if time >= trimEnd - 0.1 || time < edit.trimStart { seek(edit.trimStart) }
            player.play()
            playing = true
        }
    }

    /// ↩: from the beginning of the kept part.
    func playFromStart() {
        seek(edit.trimStart)
        player.play()
        playing = true
    }

    func jump(toEnd: Bool) {
        if playing { togglePlay() }
        seek(toEnd ? trimEnd : edit.trimStart)
    }

    /// The editor's keys, wherever the focus is in the window (except while typing in a field).
    func handleKey(code: Int, flags: NSEvent.ModifierFlags, characters: String?) -> Bool {
        guard flags.intersection([.command, .control, .option]).isEmpty else { return false }
        let shift = flags.contains(.shift)
        switch code {
        case 49: togglePlay()
        case 36, 76: playFromStart()
        case 123: step(shift ? -1 : -1.0 / 30)
        case 124: step(shift ? 1 : 1.0 / 30)
        case 115, 126: jump(toEnd: false)
        case 119, 125: jump(toEnd: true)
        case 51, 117: deleteSelection()
        case 53: selection = nil
        default:
            switch characters?.lowercased() {
            case "z": addZoom()
            case "s": addSpeed()
            case "x": addCut()
            case "n": addNote()
            case "l": looping.toggle(); show(looping ? L("Döngü açık", "Loop on") : L("Döngü kapalı", "Loop off"))
            case "k": if playing { togglePlay() }
            default: return false
            }
        }
        return true
    }

    func seek(_ seconds: Double) {
        let t = min(max(seconds, 0), duration)
        time = t
        player.seek(to: CMTime(seconds: plan.map.played(t), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// One frame (or a second with ⇧) back or forward.
    func step(_ seconds: Double) {
        if playing { togglePlay() }
        seek(time + seconds)
    }

    private func applyTrim() {
        player.currentItem?.forwardPlaybackEndTime = edit.trimEnd > edit.trimStart
            ? CMTime(seconds: plan.map.played(edit.trimEnd), preferredTimescale: 600) : .invalid
    }

    /// What decides the assembled timeline (cuts, speed-ups, added sounds): when it changes, it's put together again.
    private var compositionKey: String {
        "\(edit.timeSegments.map { "\($0.start)-\($0.end)-\($0.rate)" })|\(edit.style.clickSound)|\(edit.style.keySound)"
    }

    /// Builds the new look a moment after the last change, then shows it on the paused frame too.
    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(110))
            guard let self, !Task.isCancelled else { return }
            await rebuild()
        }
    }

    private func rebuild() async {
        let keep = time
        plan = RecPlan(meta: meta, edit: edit, maxWidth: 1600)
        if compositionKey != builtKey || built == nil {
            let key = compositionKey
            guard let fresh = await RecPlan.build(meta: meta, speeds: RecTimeMap(edit.timeSegments, duration: meta.duration).speeds,
                                                  clickSound: edit.style.clickSound, keySound: edit.style.keySound) else {
                show(L("Kayıt açılamadı", "Couldn't open the recording"))
                return
            }
            built = fresh
            builtKey = key
            let item = AVPlayerItem(asset: fresh.asset)
            item.audioTimePitchAlgorithm = .spectral
            item.videoComposition = plan.composition(for: fresh)
            item.audioMix = fresh.audioMix(edit.style)
            let wasPlaying = playing
            player.replaceCurrentItem(with: item)
            if wasPlaying { player.play() }
        } else if let built {
            player.currentItem?.videoComposition = plan.composition(for: built)
            player.currentItem?.audioMix = built.audioMix(edit.style)
        }
        applyTrim()
        if !playing { seek(keep) }
    }

    /// A strip of stills and the loudness, for the timeline.
    private func makeThumbnails() async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 240, height: 240)
        generator.appliesPreferredTrackTransform = true
        var images: [CGImage] = []
        let count = 16
        for i in 0..<count {
            let t = duration * (Double(i) + 0.5) / Double(count)
            if let image = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image { images.append(image) }
        }
        thumbnails = images
        let url = RecStore.video(for: meta.id)
        waveform = await Task.detached(priority: .utility) { RecWaveform.read(url, bins: 480) }.value
    }

    /// The still nearest a time, for the focus and note pickers.
    func still(at t: Double) -> CGImage? {
        guard !thumbnails.isEmpty else { return nil }
        return thumbnails[min(thumbnails.count - 1, max(0, Int(t / max(duration, 0.01) * Double(thumbnails.count))))]
    }

    // MARK: Timeline parts

    /// A time snapped to the nearest edge (playhead, trim, other parts) within `slop` seconds.
    func snap(_ t: Double, slop: Double, except id: UUID?) -> Double {
        var edges = [0, duration, time, edit.trimStart, trimEnd]
        for zoom in edit.zooms where zoom.id != id { edges += [zoom.start, zoom.end] }
        for speed in edit.speeds where speed.id != id { edges += [speed.start, speed.end] }
        for cut in edit.cuts where cut.id != id { edges += [cut.start, cut.end] }
        for note in edit.notes where note.id != id { edges += [note.start, note.end] }
        guard let nearest = edges.min(by: { abs($0 - t) < abs($1 - t) }), abs(nearest - t) <= slop else { return t }
        return nearest
    }

    /// The free room around `t` on a lane: from the end of the part before to the start of the part after.
    private func room(at t: Double, among parts: [(UUID, Double, Double)], except id: UUID?) -> (Double, Double) {
        let others = parts.filter { $0.0 != id }
        let before = others.filter { $0.2 <= t }.map(\.2).max() ?? 0
        let after = others.filter { $0.1 >= t }.map(\.1).min() ?? duration
        return (before, after)
    }

    private var timeParts: [(UUID, Double, Double)] { edit.speeds.map { ($0.id, $0.start, $0.end) } + edit.cuts.map { ($0.id, $0.start, $0.end) } }
    private var zoomParts: [(UUID, Double, Double)] { edit.zooms.map { ($0.id, $0.start, $0.end) } }

    /// Moves or stretches a part, kept inside the recording and clear of its neighbours on the same lane.
    func setRange(_ selection: RecSelection, start: Double, end: Double) {
        func fit(_ id: UUID, _ parts: [(UUID, Double, Double)], _ minimum: Double, _ original: (Double, Double)) -> (Double, Double) {
            let (low, high) = room(at: (original.0 + original.1) / 2, among: parts, except: id)
            let length = end - start
            var s = start, e = end
            // Moving: keep the length and slide against the neighbours.
            if abs(length - (original.1 - original.0)) < 0.0001 {
                s = min(max(s, low), high - length)
                e = s + length
            } else {
                s = max(s, low)
                e = min(e, high)
                if e - s < minimum { if start != original.0 { s = e - minimum } else { e = s + minimum } }
            }
            return (max(low, s), min(high, e))
        }
        switch selection {
        case let .zoom(id):
            guard let i = edit.zooms.firstIndex(where: { $0.id == id }) else { return }
            let (s, e) = fit(id, zoomParts, 0.4, (edit.zooms[i].start, edit.zooms[i].end))
            edit.zooms[i].start = s; edit.zooms[i].end = e
        case let .speed(id):
            guard let i = edit.speeds.firstIndex(where: { $0.id == id }) else { return }
            let (s, e) = fit(id, timeParts, 0.3, (edit.speeds[i].start, edit.speeds[i].end))
            edit.speeds[i].start = s; edit.speeds[i].end = e
        case let .cut(id):
            guard let i = edit.cuts.firstIndex(where: { $0.id == id }) else { return }
            let (s, e) = fit(id, timeParts, 0.1, (edit.cuts[i].start, edit.cuts[i].end))
            edit.cuts[i].start = s; edit.cuts[i].end = e
        case let .note(id):
            guard let i = edit.notes.firstIndex(where: { $0.id == id }) else { return }
            let length = end - start
            edit.notes[i].start = min(max(0, start), duration - min(length, duration))
            edit.notes[i].end = min(duration, max(end, edit.notes[i].start + 0.3))
        }
    }

    /// A free span of up to `length` seconds starting at `t` on a lane, or nil when there is no room.
    private func span(at t: Double, length: Double, among parts: [(UUID, Double, Double)], minimum: Double) -> (Double, Double)? {
        let t = min(max(t, 0), duration)
        if parts.contains(where: { $0.1 <= t && $0.2 > t }) { return nil }
        let (_, high) = room(at: t, among: parts, except: nil)
        let end = min(t + length, high)
        return end - t >= minimum ? (t, end) : nil
    }

    func addZoom(at t: Double? = nil) {
        guard let (s, e) = span(at: t ?? time, length: 2.5, among: zoomParts, minimum: 0.4) else { show(L("Burada yer yok", "No room here")); return }
        let zoom = RecZoom(start: s, end: e, scale: edit.style.zoomLevel)
        edit.zooms.append(zoom)
        edit.zooms.sort { $0.start < $1.start }
        selection = .zoom(zoom.id)
    }

    func addSpeed(at t: Double? = nil) {
        guard let (s, e) = span(at: t ?? time, length: 3, among: timeParts, minimum: 0.3) else { show(L("Burada yer yok", "No room here")); return }
        let speed = RecSpeed(start: s, end: e, rate: 2)
        edit.speeds.append(speed)
        edit.speeds.sort { $0.start < $1.start }
        selection = .speed(speed.id)
    }

    func addCut(at t: Double? = nil) {
        guard let (s, e) = span(at: t ?? time, length: 1.5, among: timeParts, minimum: 0.1) else { show(L("Burada yer yok", "No room here")); return }
        let cut = RecCut(start: s, end: e)
        edit.cuts.append(cut)
        edit.cuts.sort { $0.start < $1.start }
        selection = .cut(cut.id)
    }

    func addNote(at t: Double? = nil) {
        let start = min(max(t ?? time, 0), max(0, duration - 0.5))
        let note = RecNote(start: start, end: min(duration, start + 3), text: L("Buraya bak", "Look here"))
        edit.notes.append(note)
        selection = .note(note.id)
    }

    func deleteSelection() {
        guard let selection else { return }
        switch selection {
        case let .zoom(id): edit.zooms.removeAll { $0.id == id }
        case let .speed(id): edit.speeds.removeAll { $0.id == id }
        case let .cut(id): edit.cuts.removeAll { $0.id == id }
        case let .note(id): edit.notes.removeAll { $0.id == id }
        }
        self.selection = nil
    }

    func remakeZooms() {
        edit.zooms = RecEdit.autoZooms(meta: meta)
        edit.zoomsMade = true
        selection = nil
        show(edit.zooms.isEmpty ? L("Yakınlaştırılacak tıklama yok", "No clicks to zoom on") : L("\(edit.zooms.count) yakınlaştırma", "\(edit.zooms.count) zooms"))
    }

    /// Plays every stretch of steady typing three times faster.
    func speedUpTyping() {
        let found = RecEdit.typingSpeeds(meta.track.typing)
        guard !found.isEmpty else { show(L("Bu kayıtta yazma yok", "No typing in this recording")); return }
        edit.speeds = (edit.speeds.filter { speed in !found.contains { $0.start < speed.end && speed.start < $0.end } } + found)
            .filter { speed in !edit.cuts.contains { $0.start < speed.end && speed.start < $0.end } }
            .sorted { $0.start < $1.start }
        show(L("\(found.count) yazma bölümü hızlandı", "Sped up \(found.count) stretches of typing"))
    }

    // MARK: Captions

    func transcribe(language: String) {
        guard !transcribing else { return }
        transcribing = true
        let meta = meta
        Task {
            defer { transcribing = false }
            do {
                let lines = try await RecCaptions.transcribe(meta, locale: Locale(identifier: language))
                edit.captions = lines
                show(lines.isEmpty ? L("Konuşma bulunamadı", "No speech found") : L("\(lines.count) satır altyazı", "\(lines.count) caption lines"))
            } catch RecCaptions.Failure.notAllowed {
                show(L("Konuşma tanıma izni yok", "No speech recognition access"))
            } catch RecCaptions.Failure.noAudio {
                show(L("Bu kayıtta ses yok", "This recording has no sound"))
            } catch {
                show(L("Altyazı çıkarılamadı", "Couldn't make captions"))
            }
        }
    }

    /// Leaves out what a caption line says (and the line).
    func cutCaption(_ id: UUID) {
        guard let line = edit.captions.first(where: { $0.id == id }) else { return }
        edit.captions.removeAll { $0.id == id }
        edit.speeds.removeAll { $0.start < line.end && line.start < $0.end }
        edit.cuts.removeAll { $0.start < line.end && line.start < $0.end }
        edit.cuts.append(RecCut(start: line.start, end: line.end))
        edit.cuts.sort { $0.start < $1.start }
    }

    // MARK: Out

    func export(_ kind: RecExport.Kind, copy: Bool = false) {
        guard exportProgress == nil else { return }
        player.pause()
        playing = false
        exportProgress = 0
        let meta = meta, edit = edit
        Task {
            let url = await RecExport.run(meta, edit: edit, kind: kind) { value in self.exportProgress = value }
            exportProgress = nil
            guard let url else { show(L("Dışa aktarılamadı", "Export failed")); return }
            if copy {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
                show(L("Kopyalandı, yapıştırmaya hazır", "Copied, ready to paste"))
            } else {
                show(L("Kaydedildi: \(url.lastPathComponent)", "Saved: \(url.lastPathComponent)"))
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    func show(_ text: String) {
        toast = text
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            if self?.toast == text { self?.toast = nil }
        }
    }

    func close() {
        player.pause()
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
        player.replaceCurrentItem(with: nil)
    }
}
