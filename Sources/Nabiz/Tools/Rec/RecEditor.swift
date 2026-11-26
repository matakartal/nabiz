import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// The recording editor: the styled video in the middle, its look on the right, a timeline with the zooms and
/// the trim along the bottom, export at the top. Every change shows at once and is saved with the recording.
@MainActor
enum RecEditor {
    private static var open: [UUID: NSWindow] = [:]

    static func show(_ meta: RecMeta) {
        if let window = open[meta.id] { window.makeKeyAndOrderFront(nil); return }
        let model = RecEditorModel(meta: meta)
        let controller = NSHostingController(rootView: RecEditorView(model: model))
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        WindowChrome.apply(window)
        window.title = L("Ekran kaydı", "Screen recording")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 560)
        let screen = (NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900))
        let size = NSSize(width: min(1240, screen.width * 0.9), height: min(820, screen.height * 0.9))
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2))
        open[meta.id] = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
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

    /// The most recent recording, if any.
    static func showLatest() {
        if let latest = RecStore.all().first { show(latest) } else { Monitor.panelActions.flash(L("Henüz kayıt yok", "No recordings yet")) }
    }
}

@MainActor
@Observable
final class RecEditorModel {
    var meta: RecMeta
    var edit: RecEdit {
        didSet {
            guard edit != oldValue else { return }
            if edit.style != oldValue.style { edit.style.save() }
            meta.edit = edit
            RecStore.save(meta)
            scheduleRebuild()
        }
    }
    /// Playhead, in seconds of the recording (not of the sped-up result).
    var time = 0.0
    var playing = false
    var selectedZoom: UUID?
    var selectedSpeed: UUID?
    var selectedCut: UUID?
    var selectedNote: UUID?
    /// Captions being recognised.
    var transcribing = false
    var exportProgress: Double?
    var toast: String?
    var thumbnails: [CGImage] = []
    /// Loudness along the recording, 0…1, for the timeline's waveform.
    var waveform: [Float] = []
    /// The look being shown; its time map turns recording time into played time.
    private(set) var plan: RecPlan

    let player = AVPlayer()
    @ObservationIgnored private let asset: AVURLAsset
    @ObservationIgnored private var built: RecPlan.Built?
    @ObservationIgnored private var builtSpeeds: [RecSpeed] = []
    @ObservationIgnored private var builtClickSound = false
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?

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
            await rebuild(recompose: true)
            seek(edit.trimStart)
            await makeThumbnails()
        }
    }

    var duration: Double { meta.duration }
    var trimEnd: Double { edit.trimEnd > edit.trimStart ? edit.trimEnd : duration }
    /// How long the result plays, trimmed and sped up.
    var playedLength: Double { plan.map.played(trimEnd) - plan.map.played(edit.trimStart) }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        time = plan.map.source(seconds)
        if playing && player.rate == 0 { playing = false }
    }

    func togglePlay() {
        if playing {
            player.pause()
            playing = false
        } else {
            if time >= trimEnd - 0.05 { seek(edit.trimStart) }
            player.play()
            playing = true
        }
    }

    func seek(_ seconds: Double) {
        let t = min(max(seconds, 0), duration)
        time = t
        player.seek(to: CMTime(seconds: plan.map.played(t), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func applyTrim() {
        player.currentItem?.forwardPlaybackEndTime = edit.trimEnd > edit.trimStart
            ? CMTime(seconds: plan.map.played(edit.trimEnd), preferredTimescale: 600) : .invalid
    }

    /// Builds the new look a moment after the last change, then shows it on the paused frame too.
    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }
            await rebuild(recompose: edit.timeSegments != builtSpeeds || edit.style.clickSound != builtClickSound)
        }
    }

    /// A new look; when the speed-ups changed, the whole timeline is put together again (keeping the playhead).
    private func rebuild(recompose: Bool) async {
        let keep = time
        plan = RecPlan(meta: meta, edit: edit, maxWidth: 1600)
        if recompose || built == nil {
            guard let fresh = await RecPlan.build(meta: meta, speeds: RecTimeMap(edit.timeSegments, duration: meta.duration).speeds, clickSound: edit.style.clickSound) else { show(L("Kayıt açılamadı", "Couldn't open the recording")); return }
            built = fresh
            builtSpeeds = edit.timeSegments
            builtClickSound = edit.style.clickSound
            let item = AVPlayerItem(asset: fresh.asset)
            item.audioTimePitchAlgorithm = .spectral
            item.videoComposition = plan.composition(for: fresh)
            player.replaceCurrentItem(with: item)
        } else if let built {
            player.currentItem?.videoComposition = plan.composition(for: built)
        }
        applyTrim()
        if !playing { seek(keep) }
    }

    /// A strip of stills for the timeline.
    private func makeThumbnails() async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 240, height: 240)
        generator.appliesPreferredTrackTransform = true
        var images: [CGImage] = []
        let count = 14
        for i in 0..<count {
            let t = duration * (Double(i) + 0.5) / Double(count)
            if let image = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image { images.append(image) }
        }
        thumbnails = images
        let url = RecStore.video(for: meta.id)
        waveform = await Task.detached(priority: .utility) { RecWaveform.read(url, bins: 360) }.value
    }

    /// A time snapped to the nearest edge (playhead, trim, other parts) within `slop` seconds.
    func snap(_ t: Double, slop: Double, except id: UUID) -> Double {
        var edges = [0, duration, time, edit.trimStart, trimEnd]
        for zoom in edit.zooms where zoom.id != id { edges += [zoom.start, zoom.end] }
        for speed in edit.speeds where speed.id != id { edges += [speed.start, speed.end] }
        for cut in edit.cuts where cut.id != id { edges += [cut.start, cut.end] }
        guard let nearest = edges.min(by: { abs($0 - t) < abs($1 - t) }), abs(nearest - t) <= slop else { return t }
        return nearest
    }

    // MARK: Zooms

    func addZoom() {
        let start = min(time, max(0, duration - 1.5))
        var zoom = RecZoom(start: start, end: min(duration, start + 2.5), scale: edit.style.zoomLevel)
        // Never on top of another one.
        if let next = edit.zooms.filter({ $0.start > start }).map(\.start).min() { zoom.end = min(zoom.end, next) }
        if let prev = edit.zooms.first(where: { $0.start <= start && $0.end > start }) { zoom.start = prev.end }
        guard zoom.end - zoom.start > 0.4 else { return }
        edit.zooms.append(zoom)
        edit.zooms.sort { $0.start < $1.start }
        selectedZoom = zoom.id
    }

    func deleteZoom() {
        guard let selectedZoom else { return }
        edit.zooms.removeAll { $0.id == selectedZoom }
        self.selectedZoom = nil
    }

    func remakeZooms() {
        edit.zooms = RecEdit.autoZooms(meta: meta)
        edit.zoomsMade = true
        selectedZoom = nil
    }

    // MARK: Speed

    func addSpeed() {
        let start = min(time, max(0, duration - 1))
        var speed = RecSpeed(start: start, end: min(duration, start + 3), rate: 2)
        let taken = edit.speeds.map { ($0.start, $0.end) } + edit.cuts.map { ($0.start, $0.end) }
        if let next = taken.map(\.0).filter({ $0 > start }).min() { speed.end = min(speed.end, next) }
        if let inside = taken.first(where: { $0.0 <= start && $0.1 > start }) { speed.start = inside.1 }
        guard speed.end - speed.start > 0.4 else { return }
        edit.speeds.append(speed)
        edit.speeds.sort { $0.start < $1.start }
        selectedSpeed = speed.id
        selectedZoom = nil
    }

    // MARK: Captions and notes

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
        edit.cuts.append(RecCut(start: line.start, end: line.end))
        edit.cuts.sort { $0.start < $1.start }
    }

    func addNote() {
        let note = RecNote(start: min(time, max(0, duration - 1)), end: min(duration, time + 3), text: L("Buraya bak", "Look here"))
        edit.notes.append(note)
        selectedNote = note.id
        selectedZoom = nil; selectedSpeed = nil; selectedCut = nil
    }

    /// Takes 1.5 s out at the playhead (drag its edge to change how much).
    func addCut() {
        let start = min(time, max(0, duration - 0.5))
        var cut = RecCut(start: start, end: min(duration, start + 1.5))
        let taken = edit.speeds.map { ($0.start, $0.end) } + edit.cuts.map { ($0.start, $0.end) }
        if let next = taken.map(\.0).filter({ $0 > start }).min() { cut.end = min(cut.end, next) }
        if let inside = taken.first(where: { $0.0 <= start && $0.1 > start }) { cut.start = inside.1 }
        guard cut.end - cut.start > 0.2 else { return }
        edit.cuts.append(cut)
        edit.cuts.sort { $0.start < $1.start }
        selectedCut = cut.id
        selectedSpeed = nil
        selectedZoom = nil
    }

    func deleteSelection() {
        if selectedNote != nil {
            edit.notes.removeAll { $0.id == selectedNote }
            selectedNote = nil
        } else if selectedCut != nil {
            edit.cuts.removeAll { $0.id == selectedCut }
            selectedCut = nil
        } else if selectedSpeed != nil {
            edit.speeds.removeAll { $0.id == selectedSpeed }
            selectedSpeed = nil
        } else {
            deleteZoom()
        }
    }

    /// Plays every stretch of steady typing three times faster.
    func speedUpTyping() {
        let found = RecEdit.typingSpeeds(meta.track.typing)
        guard !found.isEmpty else { show(L("Bu kayıtta yazma yok", "No typing in this recording")); return }
        edit.speeds = (edit.speeds.filter { speed in !found.contains { $0.start < speed.end && speed.start < $0.end } } + found)
            .sorted { $0.start < $1.start }
        show(L("\(found.count) yazma bölümü hızlandı", "Sped up \(found.count) stretches of typing"))
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

// MARK: - The window

struct RecEditorView: View {
    @Bindable var model: RecEditorModel
    @AppStorage("panelStyle") private var panelStyle = "material"

    var body: some View {
        GeometryReader { geometry in
            let bar = max(geometry.safeAreaInsets.top, 38)
            VStack(spacing: 0) {
                topBar.frame(height: bar)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                HStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        RecPlayerView(player: model.player)
                            .padding(Theme.Spacing.xl)
                            .contentShape(Rectangle())
                            .onTapGesture { model.togglePlay() }
                        if let toast = model.toast {
                            Text(verbatim: toast)
                                .font(Theme.smallStrong).foregroundStyle(Theme.text)
                                .padding(.horizontal, Theme.Spacing.m).padding(.vertical, Theme.Spacing.xs + 2)
                                .background(MenuMaterial(blending: .withinWindow).clipShape(Capsule()))
                                .overlay(Capsule().strokeBorder(Theme.hairline))
                                .padding(.top, Theme.Spacing.m)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(duration: 0.3), value: model.toast)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(panelStyle == "opaque" ? Theme.track : Theme.track.opacity(0.6))
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                    RecInspector(model: model)
                        .frame(width: 270)
                }
                Rectangle().fill(Theme.hairline).frame(height: 1)
                RecTimeline(model: model)
                    .frame(height: 190)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(MenuMaterial().ignoresSafeArea())
        .appearanceRoot(opaqueFill: Theme.surface)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) { model.togglePlay(); return .handled }
        .onKeyPress(.delete) { model.deleteSelection(); return .handled }
    }

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            Color.clear.frame(width: WindowChrome.trafficLights)
            Text(L("Ekran kaydı", "Screen recording")).font(Theme.bodyStrong).foregroundStyle(Theme.text)
            Text(verbatim: "· " + RecTimeline.format(model.playedLength))
                .font(Theme.body).monospacedDigit().foregroundStyle(Theme.textMuted)
            Spacer()
            if let progress = model.exportProgress {
                ProgressView(value: progress).progressViewStyle(.linear).frame(width: 120).controlSize(.small)
                Text(verbatim: "%\(Int(progress * 100))").font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted)
            }
            BarButton(symbol: "folder", help: L("Kayıtlar klasörü", "Recordings folder")) {
                NSWorkspace.shared.activateFileViewerSelecting([RecStore.video(for: model.meta.id)])
            }
            Button { model.export(.hd, copy: true) } label: {
                Text(L("Kopyala", "Copy")).font(Theme.bodyStrong).foregroundStyle(Theme.text)
                    .padding(.horizontal, Theme.Spacing.m).frame(height: 24)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(L("1080p MP4 olarak panoya kopyala (Slack, Mail, Mesajlar'a yapıştır)", "Copy as a 1080p MP4 (paste into Slack, Mail, Messages)"))
            .disabled(model.exportProgress != nil)
            Menu {
                ForEach(RecExport.Kind.allCases) { kind in
                    Button(kind.title) { model.export(kind) }
                }
            } label: {
                Text(L("Dışa aktar", "Export")).font(Theme.bodyStrong).foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.m).frame(height: 24)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(model.exportProgress != nil)
        }
        .padding(.trailing, Theme.Spacing.l)
    }
}

/// The video alone on a clear layer (AVPlayerView would add black bars and its own buttons): the recording
/// brings its own background, and the timeline is ours.
struct RecPlayerView: NSViewRepresentable {
    let player: AVPlayer

    final class Host: NSView {
        let video = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            video.videoGravity = .resizeAspect
            video.backgroundColor = NSColor.clear.cgColor
            layer?.addSublayer(video)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            video.frame = bounds
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> Host {
        let view = Host()
        view.video.player = player
        return view
    }

    func updateNSView(_ view: Host, context: Context) {
        if view.video.player !== player { view.video.player = player }
    }
}

// MARK: - Look

struct RecInspector: View {
    @Bindable var model: RecEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section(L("Çerçeve", "Frame")) {
                    Picker(L("Oran", "Shape"), selection: $model.edit.style.aspect) {
                        Text(L("Kaydın", "Own")).tag("auto")
                        Text(verbatim: "16:9").tag("16:9")
                        Text(verbatim: "9:16").tag("9:16")
                        Text(verbatim: "1:1").tag("1:1")
                        Text(verbatim: "4:3").tag("4:3")
                    }
                    .pickerStyle(.segmented).labelsHidden().controlSize(.small)
                    Text(L("9:16 Reels, Shorts ve TikTok için; 1:1 gönderiler için.", "9:16 for Reels, Shorts and TikTok; 1:1 for posts."))
                        .font(Theme.small).foregroundStyle(Theme.textMuted)
                }
                section(L("Arka plan", "Background")) {
                    Picker(L("Tür", "Kind"), selection: $model.edit.style.backgroundKind) {
                        Text(L("Gradyan", "Gradient")).tag("gradient")
                        Text(L("Renk", "Colour")).tag("solid")
                        Text(L("Duvar kağıdı", "Wallpaper")).tag("wallpaper")
                        Text(L("Resim", "Image")).tag("image")
                    }
                    .pickerStyle(.segmented).labelsHidden().controlSize(.small)
                    switch model.edit.style.backgroundKind {
                    case "solid":
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 8), alignment: .leading, spacing: 8) {
                            ForEach(["#FFFFFF", "#F2F2F7", "#D1D1D6", "#8E8E93", "#3A3A3C", "#1C1C1E", "#000000", "#0A2540"], id: \.self) { hex in
                                ShotSwatch(fill: AnyShapeStyle(Color(nsColor: NSColor(hexString: hex) ?? .black)),
                                           selected: model.edit.style.solidColor == hex, help: hex) { model.edit.style.solidColor = hex }
                            }
                        }
                        ColorPicker(L("Kendi rengin", "Your own colour"), selection: Binding(
                            get: { Color(nsColor: NSColor(hexString: model.edit.style.solidColor) ?? .black) },
                            set: { color in
                                let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
                                model.edit.style.solidColor = String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
                            }), supportsOpacity: false)
                            .font(Theme.small)
                    case "wallpaper":
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                            ForEach(RecBackdrop.wallpapers, id: \.self) { url in
                                Button { model.edit.style.backgroundImage = url.path } label: {
                                    Group {
                                        if let thumb = RecBackdrop.thumbnail(url) { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill) } else { Theme.field }
                                    }
                                    .frame(height: 44).frame(maxWidth: .infinity).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(model.edit.style.backgroundImage == url.path ? Theme.accent : Theme.hairline,
                                                      lineWidth: model.edit.style.backgroundImage == url.path ? 2 : 1))
                                }
                                .buttonStyle(.plain)
                                .help(url.deletingPathExtension().lastPathComponent)
                            }
                        }
                        slider(L("Bulanıklık", "Blur"), value: $model.edit.style.backgroundBlur, range: 0...1)
                    case "image":
                        HStack {
                            Text(model.edit.style.backgroundImage.isEmpty ? L("Resim seçilmedi", "No image yet")
                                 : URL(fileURLWithPath: model.edit.style.backgroundImage).lastPathComponent)
                                .font(Theme.small).foregroundStyle(Theme.textMuted).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(L("Seç…", "Choose…")) {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.image]
                                if panel.runModal() == .OK, let url = panel.url { model.edit.style.backgroundImage = url.path }
                            }
                            .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.accent))
                        }
                        slider(L("Bulanıklık", "Blur"), value: $model.edit.style.backgroundBlur, range: 0...1)
                    default:
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 8), alignment: .leading, spacing: 8) {
                            ForEach(Array(ShotBackground.presets.enumerated()), id: \.offset) { index, pair in
                                ShotSwatch(fill: AnyShapeStyle(LinearGradient(colors: [Color(nsColor: pair.0.nsColor), Color(nsColor: pair.1.nsColor)],
                                                                              startPoint: .topLeading, endPoint: .bottomTrailing)),
                                           selected: model.edit.style.background == index, help: "") {
                                    model.edit.style.background = index
                                }
                            }
                        }
                    }
                    slider(L("Boşluk", "Padding"), value: $model.edit.style.padding, range: 0...0.2)
                    slider(L("Köşeler", "Corners"), value: $model.edit.style.radius, range: 0...0.04)
                    toggle(L("Gölge", "Shadow"), $model.edit.style.shadow)
                }
                section(L("İmleç", "Pointer")) {
                    slider(L("Boyut", "Size"), value: $model.edit.style.cursorSize, range: 1...3)
                    toggle(L("Pürüzsüz hareket", "Smooth movement"), $model.edit.style.smoothCursor)
                    toggle(L("Tıklayınca zıpla", "Bounce on click"), $model.edit.style.clickBounce)
                    toggle(L("Tıklama sesi", "Click sound"), $model.edit.style.clickSound)
                    toggle(L("Tıklama halkası", "Click rings"), $model.edit.style.clickRings)
                    toggle(L("Dururken gizle", "Hide when still"), $model.edit.style.hideIdleCursor)
                    toggle(L("Hareket bulanıklığı", "Motion blur"), $model.edit.style.motionBlur)
                }
                if model.meta.cameraOffset != nil {
                    section(L("Kamera", "Camera")) {
                        toggle(L("Göster", "Show"), $model.edit.style.camera)
                        slider(L("Boyut", "Size"), value: $model.edit.style.cameraSize, range: 0.12...0.4)
                        HStack(alignment: .top) {
                            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                                ForEach([["topLeft", "top", "topRight"], ["left", "", "right"], ["bottomLeft", "bottom", "bottomRight"]], id: \.self) { row in
                                    GridRow {
                                        ForEach(row, id: \.self) { spot in
                                            if spot.isEmpty {
                                                Color.clear.frame(width: 22, height: 16)
                                            } else {
                                                Button { model.edit.style.cameraCorner = spot } label: {
                                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                        .fill(model.edit.style.cameraCorner == spot ? Theme.accent : Theme.hover)
                                                        .frame(width: 22, height: 16)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(4)
                            .background(Theme.track, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Spacer()
                            VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                                Text(L("Konum", "Position")).font(Theme.small).foregroundStyle(Theme.textMuted)
                            }
                        }
                        slider(L("Yuvarlaklık", "Roundness"), value: $model.edit.style.cameraRoundness, range: 0...0.5)
                        toggle(L("Ayna", "Mirror"), $model.edit.style.cameraMirror)
                    }
                }
                section(L("Kısayol tuşları", "Shortcut keys")) {
                    toggle(L("Ekranda göster", "Show on screen"), $model.edit.style.showKeys)
                    Text(model.meta.track.keys.isEmpty
                         ? L("Bu kayıtta kısayol yok. Nabız'a Erişilebilirlik izni verilince ⌘C gibi kısayollar kaydedilir; yazdığın metin asla.",
                             "No shortcuts in this recording. With Accessibility access, shortcuts like ⌘C are recorded; what you type never is.")
                         : L("⌘C, ⌃⌥R gibi kısayollar altta kısa bir etiketle görünür.", "Shortcuts like ⌘C show as a short label at the bottom."))
                        .font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                section(L("Altyazı", "Captions")) {
                    RecCaptionControls(model: model)
                }
                section(L("Notlar", "Notes")) {
                    if let id = model.selectedNote, let index = model.edit.notes.firstIndex(where: { $0.id == id }) {
                        TextField(L("Not", "Note"), text: $model.edit.notes[index].text).textFieldStyle(.roundedBorder).font(Theme.body)
                        toggle(L("Ok ile göster", "Point with an arrow"), $model.edit.notes[index].arrow)
                        RecNotePicker(model: model, index: index)
                        Button(L("Bu notu sil  ⌫", "Delete this note  ⌫"), role: .destructive) { model.deleteSelection() }
                            .buttonStyle(TextButtonStyle(font: Theme.small))
                    }
                    Button(L("Oynatma çizgisine not ekle", "Add a note at the playhead")) { model.addNote() }
                        .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.accent))
                }
                section(L("Hız", "Speed")) {
                    if let id = model.selectedSpeed, let index = model.edit.speeds.firstIndex(where: { $0.id == id }) {
                        slider(L("Bu bölüm: \(String(format: "%.1f", model.edit.speeds[index].rate))×", "This part: \(String(format: "%.1f", model.edit.speeds[index].rate))×"),
                               value: $model.edit.speeds[index].rate, range: 1.5...8)
                        Button(L("Bu bölümü sil  ⌫", "Delete this part  ⌫"), role: .destructive) { model.deleteSelection() }
                            .buttonStyle(TextButtonStyle(font: Theme.small))
                    }
                    HStack {
                        Button(L("Ekle", "Add")) { model.addSpeed() }.buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.accent))
                        Spacer()
                        Button(L("Yazmayı hızlandır", "Speed up typing")) { model.speedUpTyping() }
                            .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.accent))
                            .disabled(model.meta.track.typing.isEmpty)
                    }
                    Text(L("Uzun yazma ya da bekleme anlarını hızlı geçirir; ses tonu bozulmaz.", "Plays long typing or waiting faster; voices keep their pitch."))
                        .font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                section(L("Yakınlaştırma", "Zoom")) {
                    if let id = model.selectedZoom, let index = model.edit.zooms.firstIndex(where: { $0.id == id }) {
                        slider(L("Bu yakınlaştırma: \(String(format: "%.2f", model.edit.zooms[index].scale))×", "This zoom: \(String(format: "%.2f", model.edit.zooms[index].scale))×"),
                               value: $model.edit.zooms[index].scale, range: 1.1...5)
                        Picker(L("Odak", "Focus"), selection: Binding(get: { model.edit.zooms[index].focusX == nil ? 0 : 1 }, set: { fixed in
                            model.edit.zooms[index].focusX = fixed == 1 ? 0.5 : nil
                            model.edit.zooms[index].focusY = fixed == 1 ? 0.5 : nil
                        })) {
                            Text(L("İmleci takip et", "Follow the pointer")).tag(0)
                            Text(L("Sabit nokta", "Fixed point")).tag(1)
                        }
                        .pickerStyle(.segmented).labelsHidden().controlSize(.small)
                        if model.edit.zooms[index].focusX != nil {
                            RecFocusPicker(model: model, index: index)
                        }
                        Button(L("Bu yakınlaştırmayı sil  ⌫", "Delete this zoom  ⌫"), role: .destructive) { model.deleteZoom() }
                            .buttonStyle(TextButtonStyle(font: Theme.small))
                    } else {
                        slider(L("Seviye", "Level"), value: Binding(get: { model.edit.style.zoomLevel }, set: { level in
                            model.edit.style.zoomLevel = level
                            for i in model.edit.zooms.indices { model.edit.zooms[i].scale = level }
                        }), range: 1.2...3.5)
                    }
                    HStack {
                        Button(L("Ekle", "Add")) { model.addZoom() }.buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.accent))
                        Spacer()
                        Button(L("Tıklamalardan yeniden yap", "Remake from clicks")) { model.remakeZooms() }
                            .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.accent))
                            .disabled(model.meta.track.clicks.isEmpty)
                    }
                    Text(model.meta.track.clicks.isEmpty
                         ? L("Bu kayıtta tıklama yok; oynatma çizgisinde “Ekle” ile yakınlaştır.", "No clicks in this recording; use “Add” at the playhead.")
                         : L("Tıkladığın yerlerde kendiliğinden yakınlaşır ve imleci takip eder.", "Zooms in where you clicked and follows the pointer."))
                        .font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, Theme.Spacing.l)
        }
        .scrollIndicators(.never)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(title).font(Theme.smallStrong).foregroundStyle(Theme.textMuted)
            content()
        }
        .padding(Theme.Spacing.l)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func toggle(_ title: String, _ value: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(Theme.small).foregroundStyle(Theme.text)
            Spacer()
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.small).foregroundStyle(Theme.text)
            Slider(value: value, in: range).controlSize(.small)
        }
    }
}

// MARK: - Timeline

struct RecTimeline: View {
    @Bindable var model: RecEditorModel
    @State private var dragStart: (Double, Double)?

    static func format(_ seconds: Double) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                Button { model.togglePlay() } label: {
                    Image(systemName: model.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13)).foregroundStyle(Theme.text).frame(width: 28, height: 24)
                        .background(Theme.hover, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(L("Oynat / durdur  Boşluk", "Play / pause  Space"))
                Text(verbatim: "\(Self.format(model.time)) / \(Self.format(model.duration))")
                    .font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted)
                Spacer()
                Button { model.addZoom() } label: {
                    Label(L("Yakınlaştırma ekle", "Add zoom"), systemImage: "plus.magnifyingglass").font(Theme.small)
                }
                .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.accent))
                Button { model.addSpeed() } label: {
                    Label(L("Hızlandır", "Speed up"), systemImage: "forward").font(Theme.small)
                }
                .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.accent))
                Button { model.addCut() } label: {
                    Label(L("Kes", "Cut"), systemImage: "scissors").font(Theme.small)
                }
                .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.accent))
                .help(L("Oynatma çizgisinden itibaren bir parçayı çıkar", "Take a part out from the playhead"))
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                let x = { (t: Double) in CGFloat(t / max(model.duration, 0.01)) * width }
                ZStack(alignment: .topLeading) {
                    // Stills, dimmed outside the kept part.
                    HStack(spacing: 0) {
                        ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, image in
                            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: width / CGFloat(max(model.thumbnails.count, 1)), height: 44).clipped()
                        }
                    }
                    .frame(width: width, height: 44, alignment: .leading)
                    .background(Theme.field)
                    .overlay(alignment: .bottom) { RecWaveformView(levels: model.waveform).frame(height: 18).allowsHitTesting(false) }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Rectangle().fill(.black.opacity(0.5)).frame(width: x(model.edit.trimStart), height: 44)
                    Rectangle().fill(.black.opacity(0.5)).frame(width: max(0, width - x(model.trimEnd)), height: 44)
                        .offset(x: x(model.trimEnd))
                    trimHandle(at: x(model.edit.trimStart), width: width, leading: true)
                    trimHandle(at: x(model.trimEnd), width: width, leading: false)
                    // Zooms.
                    ForEach(model.edit.speeds) { speed in
                        speedCapsule(speed, x: x, width: width)
                    }
                    ForEach(model.edit.cuts) { cut in
                        cutCapsule(cut, x: x, width: width)
                    }
                    ForEach(model.edit.notes) { note in
                        noteCapsule(note, x: x, width: width)
                    }
                    // Caption lines as thin marks under everything.
                    ForEach(model.edit.captions) { line in
                        Capsule().fill(Theme.textMuted.opacity(0.6))
                            .frame(width: max(3, x(line.end) - x(line.start)), height: 4)
                            .offset(x: x(line.start), y: 124)
                            .allowsHitTesting(false)
                    }
                    ForEach(model.edit.zooms) { zoom in
                        zoomCapsule(zoom, x: x, width: width)
                    }
                    // Playhead.
                    Rectangle().fill(Theme.text).frame(width: 2, height: 134).offset(x: x(model.time) - 1, y: -4)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    model.seek(Double(drag.location.x / width) * model.duration)
                })
            }
            .frame(height: 130)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
    }

    private func trimHandle(at position: CGFloat, width: CGFloat, leading: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Theme.accent)
            .frame(width: 8, height: 44)
            .overlay(Capsule().fill(.white.opacity(0.85)).frame(width: 2, height: 16))
            .offset(x: leading ? position : position - 8)
            .gesture(DragGesture(minimumDistance: 1).onChanged { drag in
                let t = Double(min(max(drag.location.x, 0), width) / width) * model.duration
                if leading { model.edit.trimStart = min(t, model.trimEnd - 0.5) } else { model.edit.trimEnd = max(t, model.edit.trimStart + 0.5) }
                model.seek(t)
            })
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .help(L("Baştan ya da sondan kırp", "Trim the start or the end"))
    }

    private func noteCapsule(_ note: RecNote, x: (Double) -> CGFloat, width: CGFloat) -> some View {
        let selected = model.selectedNote == note.id
        let seconds = { (dx: CGFloat) in Double(dx / width) * model.duration }
        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Theme.accent.opacity(selected ? 0.9 : 0.45))
            .overlay(alignment: .leading) {
                Label(note.text, systemImage: note.arrow ? "arrow.up.right" : "text.bubble")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).labelStyle(.titleAndIcon)
                    .padding(.leading, 7).lineLimit(1)
            }
            .overlay(alignment: .trailing) {
                Color.clear.frame(width: 8).contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1).onChanged { drag in
                        guard let index = model.edit.notes.firstIndex(where: { $0.id == note.id }) else { return }
                        model.edit.notes[index].end = min(max(model.snap(note.end + seconds(drag.translation.width), slop: seconds(6), except: note.id), note.start + 0.4), model.duration)
                    })
            }
            .frame(width: max(14, x(note.end) - x(note.start)), height: 18)
            .offset(x: x(note.start), y: 102)
            .onTapGesture { model.selectedNote = selected ? nil : note.id; model.selectedZoom = nil; model.selectedSpeed = nil; model.selectedCut = nil }
            .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                guard let index = model.edit.notes.firstIndex(where: { $0.id == note.id }) else { return }
                let length = note.end - note.start
                let start = min(max(model.snap(note.start + seconds(drag.translation.width), slop: seconds(6), except: note.id), 0), model.duration - length)
                model.edit.notes[index].start = start
                model.edit.notes[index].end = start + length
                model.selectedNote = note.id
            })
    }

    private func cutCapsule(_ cut: RecCut, x: (Double) -> CGFloat, width: CGFloat) -> some View {
        let selected = model.selectedCut == cut.id
        let seconds = { (dx: CGFloat) in Double(dx / width) * model.duration }
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.text.opacity(selected ? 0.85 : 0.6))
            .overlay(alignment: .leading) {
                Label(L("Kesildi", "Cut"), systemImage: "scissors")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.surface).labelStyle(.titleAndIcon)
                    .padding(.leading, 8).lineLimit(1)
            }
            .overlay(alignment: .trailing) {
                Color.clear.frame(width: 8).contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1).onChanged { drag in
                        guard let index = model.edit.cuts.firstIndex(where: { $0.id == cut.id }) else { return }
                        model.edit.cuts[index].end = min(max(model.snap(cut.end + seconds(drag.translation.width), slop: seconds(6), except: cut.id), cut.start + 0.2), model.duration)
                    })
            }
            .frame(width: max(14, x(cut.end) - x(cut.start)), height: 22)
            .offset(x: x(cut.start), y: 76)
            .onTapGesture { model.selectedCut = selected ? nil : cut.id; model.selectedZoom = nil; model.selectedSpeed = nil }
            .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                guard let index = model.edit.cuts.firstIndex(where: { $0.id == cut.id }) else { return }
                let length = cut.end - cut.start
                let start = min(max(model.snap(cut.start + seconds(drag.translation.width), slop: seconds(6), except: cut.id), 0), model.duration - length)
                model.edit.cuts[index].start = start
                model.edit.cuts[index].end = start + length
                model.selectedCut = cut.id
            })
            .help(L("Bu parça çıkarılır · ⌫ geri alır", "This part is left out · ⌫ puts it back"))
    }

    private func speedCapsule(_ speed: RecSpeed, x: (Double) -> CGFloat, width: CGFloat) -> some View {
        let selected = model.selectedSpeed == speed.id
        let seconds = { (dx: CGFloat) in Double(dx / width) * model.duration }
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(selected ? Theme.text.opacity(0.75) : Theme.textMuted.opacity(0.55))
            .overlay(alignment: .leading) {
                Label(String(format: "%.1f×", speed.rate), systemImage: "forward.fill")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.surface).labelStyle(.titleAndIcon)
                    .padding(.leading, 8).lineLimit(1)
            }
            .overlay(alignment: .trailing) {
                Color.clear.frame(width: 8).contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1).onChanged { drag in
                        guard let index = model.edit.speeds.firstIndex(where: { $0.id == speed.id }) else { return }
                        let limit = model.edit.speeds.filter { $0.start > speed.start }.map(\.start).min() ?? model.duration
                        model.edit.speeds[index].end = min(max(model.snap(speed.end + seconds(drag.translation.width), slop: seconds(6), except: speed.id), speed.start + 0.5), limit)
                    })
            }
            .frame(width: max(14, x(speed.end) - x(speed.start)), height: 22)
            .offset(x: x(speed.start), y: 76)
            .onTapGesture { model.selectedSpeed = selected ? nil : speed.id; model.selectedZoom = nil; model.selectedCut = nil }
            .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                guard let index = model.edit.speeds.firstIndex(where: { $0.id == speed.id }) else { return }
                let length = speed.end - speed.start
                let previous = model.edit.speeds.filter { $0.end <= speed.start }.map(\.end).max() ?? 0
                let next = model.edit.speeds.filter { $0.start >= speed.end }.map(\.start).min() ?? model.duration
                let start = min(max(model.snap(speed.start + seconds(drag.translation.width), slop: seconds(6), except: speed.id), previous), next - length)
                model.edit.speeds[index].start = start
                model.edit.speeds[index].end = start + length
                model.selectedSpeed = speed.id
            })
            .help(L("Hızlı bölüm · Sürükle: taşı · Sağ kenar: uzat", "Faster part · Drag to move · Right edge to stretch"))
    }

    private func zoomCapsule(_ zoom: RecZoom, x: (Double) -> CGFloat, width: CGFloat) -> some View {
        let selected = model.selectedZoom == zoom.id
        let seconds = { (dx: CGFloat) in Double(dx / width) * model.duration }
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(selected ? Theme.accent : Theme.accent.opacity(0.55))
            .overlay(alignment: .leading) {
                Label(String(format: "%.1f×", zoom.scale), systemImage: "plus.magnifyingglass")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).labelStyle(.titleAndIcon)
                    .padding(.leading, 8).lineLimit(1)
            }
            .overlay(alignment: .trailing) {
                Color.clear.frame(width: 8).contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1).onChanged { drag in
                        guard let index = model.edit.zooms.firstIndex(where: { $0.id == zoom.id }) else { return }
                        let limit = model.edit.zooms.filter { $0.start > zoom.start }.map(\.start).min() ?? model.duration
                        model.edit.zooms[index].end = min(max(model.snap(zoom.end + seconds(drag.translation.width), slop: seconds(6), except: zoom.id), zoom.start + 0.5), limit)
                    })
            }
            .frame(width: max(14, x(zoom.end) - x(zoom.start)), height: 22)
            .offset(x: x(zoom.start), y: 50)
            .onTapGesture { model.selectedZoom = selected ? nil : zoom.id; model.selectedSpeed = nil; model.selectedCut = nil; model.selectedNote = nil }
            .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                guard let index = model.edit.zooms.firstIndex(where: { $0.id == zoom.id }) else { return }
                let length = zoom.end - zoom.start
                let previous = model.edit.zooms.filter { $0.end <= zoom.start }.map(\.end).max() ?? 0
                let next = model.edit.zooms.filter { $0.start >= zoom.end }.map(\.start).min() ?? model.duration
                let start = min(max(model.snap(zoom.start + seconds(drag.translation.width), slop: seconds(6), except: zoom.id), previous), next - length)
                model.edit.zooms[index].start = start
                model.edit.zooms[index].end = start + length
                model.selectedZoom = zoom.id
            })
            .help(L("Sürükle: taşı · Sağ kenar: uzat · Tıkla: seç", "Drag to move · Right edge to stretch · Click to select"))
    }
}

/// Where a fixed zoom looks: a still of the recording with a dot to drag.
struct RecFocusPicker: View {
    @Bindable var model: RecEditorModel
    let index: Int

    var body: some View {
        let zoom = model.edit.zooms[index]
        let still = model.thumbnails.isEmpty ? nil
            : model.thumbnails[min(model.thumbnails.count - 1, Int(zoom.start / max(model.duration, 0.01) * Double(model.thumbnails.count)))]
        let aspect = CGFloat(model.meta.width) / CGFloat(max(model.meta.height, 1))
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                if let still {
                    Image(decorative: still, scale: 1).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height).clipped()
                } else {
                    Theme.field
                }
                // The part the zoom will show.
                let box = CGSize(width: size.width / zoom.scale, height: size.height / zoom.scale)
                let x = min(max(CGFloat(zoom.focusX ?? 0.5) * size.width - box.width / 2, 0), size.width - box.width)
                let y = min(max(CGFloat(zoom.focusY ?? 0.5) * size.height - box.height / 2, 0), size.height - box.height)
                RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white, lineWidth: 1.5)
                    .background(Theme.accent.opacity(0.18))
                    .frame(width: box.width, height: box.height)
                    .offset(x: x, y: y)
                    .shadow(color: .black.opacity(0.4), radius: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                model.edit.zooms[index].focusX = Double(min(max(drag.location.x / size.width, 0), 1))
                model.edit.zooms[index].focusY = Double(min(max(drag.location.y / size.height, 0), 1))
            })
        }
        .aspectRatio(aspect, contentMode: .fit)
        .help(L("Yakınlaşmanın göstereceği yeri sürükle", "Drag to where the zoom should look"))
    }
}

/// The recording's loudness, read once off the main thread.
enum RecWaveform {
    nonisolated static func read(_ url: URL, bins: Int) -> [Float] {
        let asset = AVURLAsset(url: url)
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var track: AVAssetTrack?
        Task.detached {
            track = try? await asset.loadTracks(withMediaType: .audio).first
            semaphore.signal()
        }
        semaphore.wait()
        guard let track, let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: 8_000,
        ])
        reader.add(output)
        guard reader.startReading() else { return [] }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var data = [Int16](repeating: 0, count: length / 2)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &data)
            samples.append(contentsOf: data.map { abs(Float($0)) / 32768 })
        }
        guard !samples.isEmpty else { return [] }
        let per = max(1, samples.count / bins)
        var levels: [Float] = []
        var i = 0
        while i < samples.count {
            let slice = samples[i..<min(i + per, samples.count)]
            levels.append((slice.reduce(0) { $0 + $1 * $1 } / Float(slice.count)).squareRoot())
            i += per
        }
        let peak = max(levels.max() ?? 1, 0.02)
        return levels.map { min(1, $0 / peak) }
    }
}

/// Bars along the bottom of the timeline's stills.
struct RecWaveformView: View {
    let levels: [Float]

    var body: some View {
        Canvas { context, size in
            guard !levels.isEmpty else { return }
            let step = size.width / CGFloat(levels.count)
            var path = Path()
            for (i, level) in levels.enumerated() {
                let h = max(1, CGFloat(level) * size.height)
                path.addRect(CGRect(x: CGFloat(i) * step, y: size.height - h, width: max(1, step - 0.5), height: h))
            }
            context.fill(path, with: .color(.white.opacity(0.75)))
        }
        .background(LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
    }
}

/// Making, showing and editing captions.
struct RecCaptionControls: View {
    @Bindable var model: RecEditorModel
    @AppStorage("rec.captionLanguage") private var language = Prefs.isTurkish ? "tr-TR" : "en-US"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Picker(L("Dil", "Language"), selection: $language) {
                    Text(verbatim: "Türkçe").tag("tr-TR")
                    Text(verbatim: "English").tag("en-US")
                }
                .labelsHidden().controlSize(.small).fixedSize()
                Spacer()
                if model.transcribing { ProgressView().controlSize(.small) }
                Button(model.edit.captions.isEmpty ? L("Konuşmadan oluştur", "Make from speech") : L("Yeniden oluştur", "Make again")) {
                    model.transcribe(language: language)
                }
                .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.accent))
                .disabled(model.transcribing)
            }
            if !model.edit.captions.isEmpty {
                HStack {
                    Text(L("Göster", "Show")).font(Theme.small).foregroundStyle(Theme.text)
                    Spacer()
                    Toggle("", isOn: $model.edit.style.showCaptions).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach($model.edit.captions) { $line in
                            HStack(spacing: 6) {
                                Button(RecTimeline.format(line.start)) { model.seek(line.start) }
                                    .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.textMuted)).monospacedDigit()
                                TextField("", text: $line.text).textFieldStyle(.plain).font(Theme.small)
                                Button { model.cutCaption(line.id) } label: { Image(systemName: "scissors").font(.system(size: 10)) }
                                    .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.textMuted))
                                    .help(L("Bu sözü videodan çıkar", "Leave these words out of the video"))
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            Text(L("Konuşman bu Mac'te yazıya dökülür; bir satırı düzeltebilir ya da makasla o sözleri videodan çıkarabilirsin.",
                   "Your speech is transcribed on this Mac; fix a line, or use the scissors to leave those words out of the video."))
                .font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Where a note sits (and where its arrow points), dragged on a still of the recording.
struct RecNotePicker: View {
    @Bindable var model: RecEditorModel
    let index: Int
    @State private var movingTarget = false

    var body: some View {
        let note = model.edit.notes[index]
        let still = model.thumbnails.isEmpty ? nil
            : model.thumbnails[min(model.thumbnails.count - 1, Int(note.start / max(model.duration, 0.01) * Double(model.thumbnails.count)))]
        let aspect = CGFloat(model.meta.width) / CGFloat(max(model.meta.height, 1))
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                if let still { Image(decorative: still, scale: 1).resizable().aspectRatio(contentMode: .fill).frame(width: size.width, height: size.height).clipped() } else { Theme.field }
                if note.arrow {
                    Path { path in
                        path.move(to: CGPoint(x: note.x * size.width, y: note.y * size.height))
                        path.addLine(to: CGPoint(x: note.toX * size.width, y: note.toY * size.height))
                    }
                    .stroke(Theme.accent, lineWidth: 2)
                    Circle().fill(.white).frame(width: 9, height: 9).overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2))
                        .position(x: note.toX * size.width, y: note.toY * size.height)
                }
                Text(note.text).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 4))
                    .position(x: note.x * size.width, y: note.y * size.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let p = CGPoint(x: min(max(drag.location.x / size.width, 0), 1), y: min(max(drag.location.y / size.height, 0), 1))
                    if drag.translation == .zero {
                        // Grab whichever end is nearer.
                        let label = hypot(p.x - note.x, p.y - note.y), tip = hypot(p.x - note.toX, p.y - note.toY)
                        movingTarget = note.arrow && tip < label
                    }
                    if movingTarget { model.edit.notes[index].toX = p.x; model.edit.notes[index].toY = p.y } else { model.edit.notes[index].x = p.x; model.edit.notes[index].y = p.y }
                })
        }
        .aspectRatio(aspect, contentMode: .fit)
        .help(L("Etiketi ya da ok ucunu sürükle", "Drag the label or the arrow's tip"))
    }
}
