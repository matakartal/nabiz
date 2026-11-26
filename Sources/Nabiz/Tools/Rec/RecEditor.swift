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
    var exportProgress: Double?
    var toast: String?
    var thumbnails: [CGImage] = []
    /// The look being shown; its time map turns recording time into played time.
    private(set) var plan: RecPlan

    let player = AVPlayer()
    @ObservationIgnored private let asset: AVURLAsset
    @ObservationIgnored private var built: RecPlan.Built?
    @ObservationIgnored private var builtSpeeds: [RecSpeed] = []
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
            await rebuild(recompose: edit.speeds != builtSpeeds)
        }
    }

    /// A new look; when the speed-ups changed, the whole timeline is put together again (keeping the playhead).
    private func rebuild(recompose: Bool) async {
        let keep = time
        plan = RecPlan(meta: meta, edit: edit, maxWidth: 1600)
        if recompose || built == nil {
            guard let fresh = await RecPlan.build(meta: meta, speeds: edit.speeds) else { show(L("Kayıt açılamadı", "Couldn't open the recording")); return }
            built = fresh
            builtSpeeds = edit.speeds
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
        edit.zooms = RecEdit.autoZooms(from: meta.track.clicks, duration: duration, scale: edit.style.zoomLevel)
        edit.zoomsMade = true
        selectedZoom = nil
    }

    // MARK: Speed

    func addSpeed() {
        let start = min(time, max(0, duration - 1))
        var speed = RecSpeed(start: start, end: min(duration, start + 3), rate: 2)
        if let next = edit.speeds.filter({ $0.start > start }).map(\.start).min() { speed.end = min(speed.end, next) }
        if let inside = edit.speeds.first(where: { $0.start <= start && $0.end > start }) { speed.start = inside.end }
        guard speed.end - speed.start > 0.4 else { return }
        edit.speeds.append(speed)
        edit.speeds.sort { $0.start < $1.start }
        selectedSpeed = speed.id
        selectedZoom = nil
    }

    func deleteSelection() {
        if selectedSpeed != nil {
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
                    .frame(height: 158)
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
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 8), alignment: .leading, spacing: 8) {
                        ForEach(Array(ShotBackground.presets.enumerated()), id: \.offset) { index, pair in
                            ShotSwatch(fill: AnyShapeStyle(LinearGradient(colors: [Color(nsColor: pair.0.nsColor), Color(nsColor: pair.1.nsColor)],
                                                                          startPoint: .topLeading, endPoint: .bottomTrailing)),
                                       selected: model.edit.style.background == index, help: "") {
                                model.edit.style.background = index
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
                    toggle(L("Tıklama halkası", "Click rings"), $model.edit.style.clickRings)
                    toggle(L("Dururken gizle", "Hide when still"), $model.edit.style.hideIdleCursor)
                    toggle(L("Hareket bulanıklığı", "Motion blur"), $model.edit.style.motionBlur)
                }
                if model.meta.cameraOffset != nil {
                    section(L("Kamera", "Camera")) {
                        toggle(L("Göster", "Show"), $model.edit.style.camera)
                        slider(L("Boyut", "Size"), value: $model.edit.style.cameraSize, range: 0.12...0.4)
                        HStack(spacing: Theme.Spacing.s) {
                            ForEach([("topLeft", "arrow.up.left"), ("topRight", "arrow.up.right"), ("bottomLeft", "arrow.down.left"),
                                     ("bottomRight", "arrow.down.right")], id: \.0) { corner, symbol in
                                ShotToolButton(symbol: symbol, help: L("Köşe", "Corner"), active: model.edit.style.cameraCorner == corner) {
                                    model.edit.style.cameraCorner = corner
                                }
                            }
                            Spacer()
                            ShotToolButton(symbol: model.edit.style.cameraCircle ? "circle" : "app", help: L("Daire ya da kare", "Circle or square"),
                                           active: false) { model.edit.style.cameraCircle.toggle() }
                        }
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
                        slider(L("Bu yakınlaştırma", "This zoom"), value: $model.edit.zooms[index].scale, range: 1.2...3.5)
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
                    ForEach(model.edit.zooms) { zoom in
                        zoomCapsule(zoom, x: x, width: width)
                    }
                    // Playhead.
                    Rectangle().fill(Theme.text).frame(width: 2, height: 104).offset(x: x(model.time) - 1, y: -4)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    model.seek(Double(drag.location.x / width) * model.duration)
                })
            }
            .frame(height: 100)
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
                        model.edit.speeds[index].end = min(max(speed.end + seconds(drag.translation.width), speed.start + 0.5), limit)
                    })
            }
            .frame(width: max(14, x(speed.end) - x(speed.start)), height: 22)
            .offset(x: x(speed.start), y: 76)
            .onTapGesture { model.selectedSpeed = selected ? nil : speed.id; model.selectedZoom = nil }
            .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                guard let index = model.edit.speeds.firstIndex(where: { $0.id == speed.id }) else { return }
                let length = speed.end - speed.start
                let previous = model.edit.speeds.filter { $0.end <= speed.start }.map(\.end).max() ?? 0
                let next = model.edit.speeds.filter { $0.start >= speed.end }.map(\.start).min() ?? model.duration
                let start = min(max(speed.start + seconds(drag.translation.width), previous), next - length)
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
                        model.edit.zooms[index].end = min(max(zoom.end + seconds(drag.translation.width), zoom.start + 0.5), limit)
                    })
            }
            .frame(width: max(14, x(zoom.end) - x(zoom.start)), height: 22)
            .offset(x: x(zoom.start), y: 50)
            .onTapGesture { model.selectedZoom = selected ? nil : zoom.id; model.selectedSpeed = nil }
            .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                guard let index = model.edit.zooms.firstIndex(where: { $0.id == zoom.id }) else { return }
                let length = zoom.end - zoom.start
                let previous = model.edit.zooms.filter { $0.end <= zoom.start }.map(\.end).max() ?? 0
                let next = model.edit.zooms.filter { $0.start >= zoom.end }.map(\.start).min() ?? model.duration
                let start = min(max(zoom.start + seconds(drag.translation.width), previous), next - length)
                model.edit.zooms[index].start = start
                model.edit.zooms[index].end = start + length
                model.selectedZoom = zoom.id
            })
            .help(L("Sürükle: taşı · Sağ kenar: uzat · Tıkla: seç", "Drag to move · Right edge to stretch · Click to select"))
    }
}
