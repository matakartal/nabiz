// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import AVFoundation
import SwiftUI

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
                    preview
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                    RecInspector(model: model).frame(width: 300)
                }
                Rectangle().fill(Theme.hairline).frame(height: 1)
                RecTimeline(model: model).frame(height: 236)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(MenuMaterial().ignoresSafeArea())
        .appearanceRoot(opaqueFill: Theme.surface)
    }

    private var preview: some View {
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
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    .padding(.top, Theme.Spacing.m)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.toast)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelStyle == "opaque" ? Theme.track : Theme.track.opacity(0.6))
    }

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            Color.clear.frame(width: WindowChrome.trafficLights)
            Text(L("Ekran kaydı", "Screen recording")).font(Theme.bodyStrong).foregroundStyle(Theme.text)
            Text(verbatim: RecFormat.duration(model.playedLength))
                .font(Theme.body).monospacedDigit().foregroundStyle(Theme.textMuted)
            Spacer()
            BarButton(symbol: "arrow.uturn.backward", help: L("Geri al  ⌘Z", "Undo  ⌘Z")) { model.undo() }
                .disabled(!model.canUndo).opacity(model.canUndo ? 1 : 0.35)
            BarButton(symbol: "arrow.uturn.forward", help: L("Yinele  ⇧⌘Z", "Redo  ⇧⌘Z")) { model.redo() }
                .disabled(!model.canRedo).opacity(model.canRedo ? 1 : 0.35)
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 18).padding(.horizontal, Theme.Spacing.xs)
            BarButton(symbol: "folder", help: L("Kaydın dosyası", "The recording's file")) {
                NSWorkspace.shared.activateFileViewerSelecting([RecStore.video(for: model.meta.id)])
            }
            BarButton(symbol: "trash", help: L("Kaydı sil", "Delete the recording")) { RecEditor.confirmDelete(model.meta.id) }
            if let progress = model.exportProgress {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView(value: progress).progressViewStyle(.linear).frame(width: 110).controlSize(.small)
                    Text(verbatim: "%\(Int(progress * 100))").font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted)
                }
                .transition(.opacity)
            }
            Button { model.export(.hd, copy: true) } label: {
                Text(L("Kopyala", "Copy")).font(Theme.bodyStrong).foregroundStyle(Theme.text)
                    .padding(.horizontal, Theme.Spacing.m).frame(height: 26)
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
                HStack(spacing: 5) {
                    Text(L("Dışa aktar", "Export")).font(Theme.bodyStrong)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.m).frame(height: 26)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(model.exportProgress != nil)
        }
        .padding(.trailing, Theme.Spacing.l)
        .animation(.easeOut(duration: 0.2), value: model.exportProgress == nil)
    }
}

enum RecFormat {
    /// "0:05.2"
    static func time(_ seconds: Double) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }

    /// "0:34"
    static func duration(_ seconds: Double) -> String {
        let s = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "2.8 s"
    static func length(_ seconds: Double) -> String { String(format: L("%.1f sn", "%.1f s"), seconds) }
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

// MARK: - Building blocks

/// A titled group in the inspector, with a hairline under it.
struct RecGroup<Content: View>: View {
    let title: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let title { Text(title).font(Theme.smallStrong).foregroundStyle(Theme.textMuted) }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m + 2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

/// A slider with its title and its value on one line above it.
struct RecSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: (Double) -> String

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(title).font(Theme.body).foregroundStyle(Theme.text)
                Spacer()
                Text(verbatim: label(value)).font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted)
            }
            Slider(value: $value, in: range).controlSize(.small)
        }
    }
}

/// A switch on the right of its title (and an optional line under it).
struct RecSwitch: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body).foregroundStyle(Theme.text)
                if let detail {
                    Text(detail).font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
    }
}

/// A full-width segmented choice.
struct RecChoice<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        .pickerStyle(.segmented).labelsHidden().controlSize(.small)
    }
}

/// A small text button in the accent colour, with an optional symbol.
struct RecLink: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .medium)) }
                Text(title).font(Theme.smallStrong)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, Theme.Spacing.s + 2).frame(height: 24)
            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private func percent(_ v: Double) -> String { "%\(Int((v * 100).rounded()))" }
private func times(_ v: Double) -> String { String(format: "%.1f×", v) }

// MARK: - Inspector

struct RecInspector: View {
    @Bindable var model: RecEditorModel

    var body: some View {
        VStack(spacing: 0) {
            if model.selection != nil {
                RecItemPanel(model: model)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                tabs
                Rectangle().fill(Theme.hairline).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.tab.title).font(Theme.title).foregroundStyle(Theme.text)
                            .padding(.horizontal, Theme.Spacing.l).padding(.top, Theme.Spacing.l).padding(.bottom, Theme.Spacing.xs)
                        page
                    }
                    .padding(.bottom, Theme.Spacing.xl)
                }
                .scrollIndicators(.never)
                .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.28, bounce: 0.1), value: model.selection)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(RecTab.allCases) { tab in
                ShotToolButton(symbol: tab.symbol, help: tab.title, active: model.tab == tab) { model.tab = tab }
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: 44)
    }

    @ViewBuilder
    private var page: some View {
        switch model.tab {
        case .frame: frame
        case .pointer: pointer
        case .zoom: zoom
        case .camera: camera
        case .text: text
        case .sound: sound
        }
    }

    // MARK: Frame

    @ViewBuilder
    private var frame: some View {
        RecGroup(L("Biçim", "Shape")) {
            RecChoice(selection: $model.edit.style.aspect, options: [("auto", L("Kaydın", "Own")), ("16:9", "16:9"), ("9:16", "9:16"), ("1:1", "1:1"), ("4:3", "4:3")])
            Text(L("9:16 Reels, Shorts ve TikTok için; 1:1 gönderiler için.", "9:16 for Reels, Shorts and TikTok; 1:1 for posts."))
                .font(Theme.small).foregroundStyle(Theme.textMuted)
        }
        RecGroup(L("Arka plan", "Background")) {
            RecChoice(selection: $model.edit.style.backgroundKind, options: [("gradient", L("Gradyan", "Gradient")), ("solid", L("Renk", "Colour")),
                                                                         ("wallpaper", L("Duvar kâğıdı", "Wallpaper")), ("image", L("Resim", "Image"))])
            background
        }
        RecGroup(L("Kart", "Card")) {
            RecSlider(title: L("Boşluk", "Padding"), value: $model.edit.style.padding, range: 0...0.2, label: percent)
            RecSlider(title: L("Köşeler", "Corners"), value: $model.edit.style.radius, range: 0...0.04) { percent($0 / 0.04) }
            RecSwitch(title: L("Gölge", "Shadow"), isOn: $model.edit.style.shadow)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch model.edit.style.backgroundKind {
        case "solid":
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 8), alignment: .leading, spacing: 6) {
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
                .font(Theme.body)
        case "wallpaper":
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(RecBackdrop.wallpapers, id: \.self) { url in
                    let chosen = model.edit.style.backgroundImage == url.path
                    Button { model.edit.style.backgroundImage = url.path } label: {
                        Group {
                            if let thumb = RecBackdrop.thumbnail(url) { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill) } else { Theme.field }
                        }
                        .frame(height: 48).frame(maxWidth: .infinity).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(chosen ? Theme.accent : Theme.hairline, lineWidth: chosen ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .help(url.deletingPathExtension().lastPathComponent)
                }
            }
            RecSlider(title: L("Bulanıklık", "Blur"), value: $model.edit.style.backgroundBlur, range: 0...1, label: percent)
        case "image":
            HStack {
                Text(model.edit.style.backgroundImage.isEmpty ? L("Resim seçilmedi", "No image yet")
                     : URL(fileURLWithPath: model.edit.style.backgroundImage).lastPathComponent)
                    .font(Theme.body).foregroundStyle(Theme.textMuted).lineLimit(1).truncationMode(.middle)
                Spacer()
                RecLink(title: L("Seç…", "Choose…"), symbol: "photo") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    if panel.runModal() == .OK, let url = panel.url { model.edit.style.backgroundImage = url.path }
                }
            }
            RecSlider(title: L("Bulanıklık", "Blur"), value: $model.edit.style.backgroundBlur, range: 0...1, label: percent)
        default:
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 8), alignment: .leading, spacing: 6) {
                ForEach(Array(ShotBackground.presets.enumerated()), id: \.offset) { index, pair in
                    ShotSwatch(fill: AnyShapeStyle(LinearGradient(colors: [Color(nsColor: pair.0.nsColor), Color(nsColor: pair.1.nsColor)],
                                                                  startPoint: .topLeading, endPoint: .bottomTrailing)),
                               selected: model.edit.style.background == index, help: "") { model.edit.style.background = index }
                }
            }
        }
    }

    // MARK: Pointer

    @ViewBuilder
    private var pointer: some View {
        RecGroup {
            RecSlider(title: L("Boyut", "Size"), value: $model.edit.style.cursorSize, range: 1...5, label: times)
            RecSwitch(title: L("Pürüzsüz hareket", "Smooth movement"), detail: L("Titremeyi alır, tıkladığın yere tam iner.", "Takes out the jitter, lands exactly where you clicked."),
                      isOn: $model.edit.style.smoothCursor)
            RecSwitch(title: L("Dururken gizle", "Hide when still"), isOn: $model.edit.style.hideIdleCursor)
            RecSwitch(title: L("Hareket bulanıklığı", "Motion blur"), detail: L("İmleç ve kamera hızlı giderken, gerçek bir kameradaki gibi.", "When the pointer and the camera move fast, like a real camera."),
                      isOn: $model.edit.style.motionBlur)
        }
        RecGroup(L("Tıklama", "Click")) {
            RecSwitch(title: L("Basılıp sekme", "Press and bounce"), isOn: $model.edit.style.clickBounce)
            RecSwitch(title: L("Halka", "Ring"), isOn: $model.edit.style.clickRings)
            RecSwitch(title: L("Tıklama sesi", "Click sound"), isOn: $model.edit.style.clickSound)
        }
    }

    // MARK: Zoom

    @ViewBuilder
    private var zoom: some View {
        RecGroup {
            Text(model.meta.track.clicks.isEmpty
                 ? L("Bu kayıtta tıklama yok. Zaman çizelgesinde yakınlaştırma şeridine çift tıkla ya da Z'ye bas.",
                     "No clicks in this recording. Double-click the zoom lane on the timeline, or press Z.")
                 : L("Tıkladığın yerlere kendiliğinden yakınlaşır ve imleci yumuşakça takip eder.",
                     "Zooms in where you clicked and follows the pointer smoothly."))
                .font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.s) {
                RecLink(title: L("Tıklamalardan yap", "Make from clicks"), symbol: "wand.and.stars") { model.remakeZooms() }
                    .disabled(model.meta.track.clicks.isEmpty)
                RecLink(title: L("Ekle", "Add"), symbol: "plus") { model.addZoom() }
            }
        }
        RecGroup(L("Derinlik", "Depth")) {
            RecSlider(title: L("Yeni yakınlaştırmalar", "New zooms"), value: Binding(get: { model.edit.style.zoomLevel }, set: { level in
                model.edit.style.zoomLevel = level
                for i in model.edit.zooms.indices { model.edit.zooms[i].scale = level }
            }), range: 1.1...4, label: times)
        }
        if !model.edit.zooms.isEmpty {
            RecGroup(L("Bu kayıtta", "In this recording")) {
                VStack(spacing: 2) {
                    ForEach(Array(model.edit.zooms.enumerated()), id: \.element.id) { index, item in
                        RecListRow(symbol: "plus.magnifyingglass", title: L("Yakınlaştırma \(index + 1)", "Zoom \(index + 1)"),
                                   detail: "\(RecFormat.time(item.start)) · \(times(item.scale))") {
                            model.selection = .zoom(item.id)
                            model.seek(item.start)
                        }
                    }
                }
            }
        }
    }

    // MARK: Camera

    @ViewBuilder
    private var camera: some View {
        if model.hasCamera {
            RecGroup {
                RecSwitch(title: L("Göster", "Show"), isOn: $model.edit.style.camera)
            }
            RecGroup(L("Konum", "Position")) {
                RecSpotGrid(selection: $model.edit.style.cameraCorner)
            }
            RecGroup(L("Görünüm", "Look")) {
                RecSlider(title: L("Boyut", "Size"), value: $model.edit.style.cameraSize, range: 0.12...0.4, label: percent)
                RecSlider(title: L("Yuvarlaklık", "Roundness"), value: $model.edit.style.cameraRoundness, range: 0...0.5) { percent($0 / 0.5) }
                RecSwitch(title: L("Ayna", "Mirror"), isOn: $model.edit.style.cameraMirror)
            }
        } else {
            RecGroup {
                Text(L("Bu kayıtta kamera yok. Sonraki kayıtta kayıt çubuğundaki kamera düğmesini aç; görüntün köşede bir balonda çıkar.",
                       "There's no camera in this recording. Turn on the camera button in the recording bar next time; you'll show in a bubble in a corner."))
                    .font(Theme.body).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Text

    @ViewBuilder
    private var text: some View {
        RecGroup(L("Altyazı", "Captions")) { RecCaptionControls(model: model) }
        RecGroup(L("Kısayol tuşları", "Shortcut keys")) {
            RecSwitch(title: L("Ekranda göster", "Show on screen"),
                      detail: model.meta.track.keys.isEmpty
                        ? L("Bu kayıtta kısayol yok. Erişilebilirlik izniyle ⌘C gibi kısayollar kaydedilir; yazdığın metin asla.",
                            "No shortcuts in this recording. With Accessibility access, shortcuts like ⌘C are recorded; what you type never is.")
                        : L("⌘C, ⌃⌥R gibi kısayollar altta kısa bir etiketle görünür.", "Shortcuts like ⌘C show as a short label at the bottom."),
                      isOn: $model.edit.style.showKeys)
        }
        RecGroup(L("Notlar", "Notes")) {
            if !model.edit.notes.isEmpty {
                VStack(spacing: 2) {
                    ForEach(model.edit.notes) { note in
                        RecListRow(symbol: note.arrow ? "arrow.up.right" : "text.bubble", title: note.text.isEmpty ? L("Not", "Note") : note.text,
                                   detail: RecFormat.time(note.start)) {
                            model.selection = .note(note.id)
                            model.seek(note.start)
                        }
                    }
                }
            }
            RecLink(title: L("Oynatma çizgisine not ekle", "Add a note at the playhead"), symbol: "plus") { model.addNote() }
        }
    }

    // MARK: Sound

    @ViewBuilder
    private var sound: some View {
        RecGroup(L("Düzeyler", "Levels")) {
            RecSlider(title: L("Bilgisayarın sesi", "The Mac's sound"), value: $model.edit.style.soundVolume, range: 0...1, label: percent)
            RecSlider(title: L("Mikrofon", "Microphone"), value: $model.edit.style.micVolume, range: 0...1, label: percent)
            RecSlider(title: L("Tıklama ve tuş sesleri", "Click and key sounds"), value: $model.edit.style.effectsVolume, range: 0...1, label: percent)
        }
        RecGroup(L("Eklenen sesler", "Added sounds")) {
            RecSwitch(title: L("Tıklama sesi", "Click sound"), detail: L("Her tıklamada yumuşak bir tık.", "A soft click on every click."),
                      isOn: $model.edit.style.clickSound)
            RecSwitch(title: L("Klavye sesi", "Keyboard sound"),
                      detail: model.meta.track.typing.isEmpty && model.meta.track.keys.isEmpty
                        ? L("Bu kayıtta tuş yok: tuşlar Erişilebilirlik izniyle kaydedilir.", "No keys in this recording: keys are recorded with Accessibility access.")
                        : L("Her tuşta hafif bir tık.", "A light tap on every key."),
                      isOn: $model.edit.style.keySound)
        }
        RecGroup(L("Hız", "Speed")) {
            Text(L("Uzun yazma kısımlarını tek tıkla 3× hızlandır; ses tonu bozulmaz.", "Speed up long typing 3× in one click; voices keep their pitch."))
                .font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            RecLink(title: L("Yazmayı hızlandır", "Speed up typing"), symbol: "forward") { model.speedUpTyping() }
                .disabled(model.meta.track.typing.isEmpty)
        }
    }
}

/// A row in a list (zooms, notes) that selects what it names.
struct RecListRow: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Theme.accent).frame(width: 16)
                Text(title).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
                Text(verbatim: detail).font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, Theme.Spacing.s).frame(height: 28)
            .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Nine spots for the camera (the middle one left out), drawn as a little screen.
struct RecSpotGrid: View {
    @Binding var selection: String
    private let rows = [["topLeft", "top", "topRight"], ["left", "", "right"], ["bottomLeft", "bottom", "bottomRight"]]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { spot in
                        if spot.isEmpty {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 30)
                        } else {
                            Button { selection = spot } label: {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(selection == spot ? Theme.accent : Theme.hover)
                                    .overlay(Circle().fill(selection == spot ? Color.white : Theme.textMuted.opacity(0.5)).frame(width: 8, height: 8))
                                    .frame(maxWidth: .infinity).frame(height: 30)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(6)
        .background(Theme.track, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.spring(duration: 0.25), value: selection)
    }
}

// MARK: - The selected part

struct RecItemPanel: View {
    @Bindable var model: RecEditorModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                    RecGroup {
                        Button(role: .destructive) { model.deleteSelection() } label: {
                            Label(deleteTitle, systemImage: "trash").font(Theme.body)
                        }
                        .buttonStyle(TextButtonStyle(font: Theme.body))
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.never)
        }
    }

    private var info: (symbol: String, title: String, start: Double, end: Double)? {
        switch model.selection {
        case let .zoom(id):
            guard let index = model.edit.zooms.firstIndex(where: { $0.id == id }) else { return nil }
            let zoom = model.edit.zooms[index]
            return ("plus.magnifyingglass", L("Yakınlaştırma \(index + 1)", "Zoom \(index + 1)"), zoom.start, zoom.end)
        case let .speed(id):
            guard let speed = model.edit.speeds.first(where: { $0.id == id }) else { return nil }
            return ("forward", L("Hızlı bölüm", "Faster part"), speed.start, speed.end)
        case let .cut(id):
            guard let cut = model.edit.cuts.first(where: { $0.id == id }) else { return nil }
            return ("scissors", L("Kesilen bölüm", "Cut part"), cut.start, cut.end)
        case let .note(id):
            guard let note = model.edit.notes.first(where: { $0.id == id }) else { return nil }
            return ("text.bubble", L("Not", "Note"), note.start, note.end)
        case nil:
            return nil
        }
    }

    private var deleteTitle: String {
        if case .cut = model.selection { return L("Geri koy  ⌫", "Put back  ⌫") }
        return L("Sil  ⌫", "Delete  ⌫")
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let info {
                Image(systemName: info.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.title).font(Theme.bodyStrong).foregroundStyle(Theme.text)
                    Text(verbatim: "\(RecFormat.time(info.start)) – \(RecFormat.time(info.end)) · \(RecFormat.length(info.end - info.start))")
                        .font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted)
                }
            }
            Spacer()
            BarButton(symbol: "xmark", help: L("Kapat  ⎋", "Close  ⎋")) { model.selection = nil }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(height: 60)
    }

    @ViewBuilder
    private var content: some View {
        switch model.selection {
        case let .zoom(id):
            if let index = model.edit.zooms.firstIndex(where: { $0.id == id }) {
                RecGroup(L("Derinlik", "Depth")) {
                    RecSlider(title: L("Yakınlık", "Closeness"), value: $model.edit.zooms[index].scale, range: 1.1...5, label: times)
                }
                RecGroup(L("Nereye bakar", "Where it looks")) {
                    RecChoice(selection: Binding(get: { model.edit.zooms[index].focusX == nil ? 0 : 1 }, set: { fixed in
                        model.edit.zooms[index].focusX = fixed == 1 ? 0.5 : nil
                        model.edit.zooms[index].focusY = fixed == 1 ? 0.5 : nil
                    }), options: [(0, L("İmleci takip et", "Follow the pointer")), (1, L("Sabit nokta", "Fixed point"))])
                    if model.edit.zooms[index].focusX != nil {
                        RecFocusPicker(model: model, index: index)
                    }
                }
            }
        case let .speed(id):
            if let index = model.edit.speeds.firstIndex(where: { $0.id == id }) {
                RecGroup(L("Hız", "Speed")) {
                    RecSlider(title: L("Kaç kat", "How fast"), value: $model.edit.speeds[index].rate, range: 1.25...8, label: times)
                    let speed = model.edit.speeds[index]
                    Text(L("\(RecFormat.length(speed.end - speed.start)) yerine \(RecFormat.length((speed.end - speed.start) / speed.rate)) sürer; ses tonu bozulmaz.",
                           "Plays in \(RecFormat.length((speed.end - speed.start) / speed.rate)) instead of \(RecFormat.length(speed.end - speed.start)); voices keep their pitch."))
                        .font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
        case .cut:
            RecGroup {
                Text(L("Bu bölüm videoda yer almaz. Kenarlarından sürükleyerek ne kadarını çıkaracağını ayarla.",
                       "This part is left out of the video. Drag its edges to choose how much."))
                    .font(Theme.body).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        case let .note(id):
            if let index = model.edit.notes.firstIndex(where: { $0.id == id }) {
                RecGroup(L("Yazı", "Text")) {
                    TextField(L("Not", "Note"), text: $model.edit.notes[index].text).textFieldStyle(.roundedBorder).font(Theme.body)
                    RecSwitch(title: L("Ok ile göster", "Point with an arrow"), isOn: $model.edit.notes[index].arrow)
                }
                RecGroup(L("Yer", "Place")) {
                    RecNotePicker(model: model, index: index)
                    Text(L("Etiketi ya da ok ucunu sürükle; not yakınlaşınca gösterdiği yerle birlikte hareket eder.",
                           "Drag the label or the arrow's tip; the note moves with the zoom, staying on what it points at."))
                        .font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Pickers

/// Where a fixed zoom looks: a still of the recording with the visible part to drag.
struct RecFocusPicker: View {
    @Bindable var model: RecEditorModel
    let index: Int

    var body: some View {
        let zoom = model.edit.zooms[index]
        let aspect = CGFloat(model.meta.width) / CGFloat(max(model.meta.height, 1))
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                if let still = model.still(at: zoom.start) {
                    Image(decorative: still, scale: 1).resizable().aspectRatio(contentMode: .fill).frame(width: size.width, height: size.height).clipped()
                } else {
                    Theme.field
                }
                Color.black.opacity(0.35)
                let box = CGSize(width: size.width / zoom.scale, height: size.height / zoom.scale)
                let x = min(max(CGFloat(zoom.focusX ?? 0.5) * size.width - box.width / 2, 0), size.width - box.width)
                let y = min(max(CGFloat(zoom.focusY ?? 0.5) * size.height - box.height / 2, 0), size.height - box.height)
                Group {
                    if let still = model.still(at: zoom.start) {
                        Image(decorative: still, scale: 1).resizable().aspectRatio(contentMode: .fill).frame(width: size.width, height: size.height)
                            .offset(x: -x, y: -y).frame(width: box.width, height: box.height, alignment: .topLeading).clipped()
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white, lineWidth: 1.5))
                .offset(x: x, y: y)
                .shadow(color: .black.opacity(0.4), radius: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

/// Where a note sits (and where its arrow points), dragged on a still of the recording.
struct RecNotePicker: View {
    @Bindable var model: RecEditorModel
    let index: Int
    @State private var movingTarget = false

    var body: some View {
        let note = model.edit.notes[index]
        let aspect = CGFloat(model.meta.width) / CGFloat(max(model.meta.height, 1))
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                if let still = model.still(at: note.start) {
                    Image(decorative: still, scale: 1).resizable().aspectRatio(contentMode: .fill).frame(width: size.width, height: size.height).clipped()
                } else {
                    Theme.field
                }
                if note.arrow {
                    Path { path in
                        path.move(to: CGPoint(x: note.x * size.width, y: note.y * size.height))
                        path.addLine(to: CGPoint(x: note.toX * size.width, y: note.toY * size.height))
                    }
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    Circle().fill(.white).frame(width: 10, height: 10).overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2))
                        .position(x: note.toX * size.width, y: note.toY * size.height)
                }
                Text(note.text.isEmpty ? " " : note.text).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 4))
                    .position(x: note.x * size.width, y: note.y * size.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let p = CGPoint(x: min(max(drag.location.x / size.width, 0), 1), y: min(max(drag.location.y / size.height, 0), 1))
                    if drag.translation == .zero {
                        let label = hypot(p.x - note.x, p.y - note.y), tip = hypot(p.x - note.toX, p.y - note.toY)
                        movingTarget = note.arrow && tip < label
                    }
                    if movingTarget { model.edit.notes[index].toX = p.x; model.edit.notes[index].toY = p.y } else { model.edit.notes[index].x = p.x; model.edit.notes[index].y = p.y }
                })
        }
        .aspectRatio(aspect, contentMode: .fit)
    }
}

/// Making, showing and editing captions.
struct RecCaptionControls: View {
    @Bindable var model: RecEditorModel
    @AppStorage("rec.captionLanguage") private var language = Prefs.isTurkish ? "tr-TR" : "en-US"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Picker("", selection: $language) {
                    Text(verbatim: "Türkçe").tag("tr-TR")
                    Text(verbatim: "English").tag("en-US")
                }
                .labelsHidden().controlSize(.small).fixedSize()
                Spacer()
                if model.transcribing { ProgressView().controlSize(.small) }
                RecLink(title: model.edit.captions.isEmpty ? L("Konuşmadan oluştur", "Make from speech") : L("Yeniden oluştur", "Make again"),
                        symbol: "waveform") { model.transcribe(language: language) }
                    .disabled(model.transcribing)
            }
            if model.edit.captions.isEmpty {
                Text(L("Konuşman bu Mac'te yazıya dökülür, hiçbir yere gönderilmez.", "Your speech is transcribed on this Mac and sent nowhere."))
                    .font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            } else {
                RecSwitch(title: L("Videoda göster", "Show in the video"), isOn: $model.edit.style.showCaptions)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach($model.edit.captions) { $line in
                        HStack(spacing: 6) {
                            Button(RecFormat.time(line.start)) { model.seek(line.start) }
                                .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.textMuted)).monospacedDigit()
                            TextField("", text: $line.text).textFieldStyle(.plain).font(Theme.body)
                            Button { model.cutCaption(line.id) } label: { Image(systemName: "scissors").font(.system(size: 10)) }
                                .buttonStyle(TextButtonStyle(font: Theme.small, color: Theme.textMuted))
                                .help(L("Bu sözleri videodan çıkar", "Leave these words out of the video"))
                        }
                        .padding(.vertical, 3)
                    }
                }
                Text(L("Bir satırı düzeltebilir ya da makasla o sözleri videodan çıkarabilirsin.", "Fix a line, or use the scissors to leave those words out of the video."))
                    .font(Theme.small).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
