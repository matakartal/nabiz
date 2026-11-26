// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import AVFoundation
import SwiftUI

/// The timeline: a ruler, the video (stills, loudness, trim handles), and three lanes (zooms; speed-ups and cuts;
/// notes and captions). Drag a part to move it, drag either edge to stretch it, double-click an empty lane to add
/// one there; edges snap to the playhead and to each other.
struct RecTimeline: View {
    @Bindable var model: RecEditorModel
    @State private var showKeys = false

    static let gutter: CGFloat = 30
    static let ruler: CGFloat = 22
    static let video: CGFloat = 46
    static let lane: CGFloat = 26
    static let gap: CGFloat = 6

    /// Top of each row.
    static let videoY = ruler + 4
    static let zoomY = videoY + video + gap
    static let timeY = zoomY + lane + gap
    static let textY = timeY + lane + gap
    static let height = textY + lane

    var body: some View {
        VStack(spacing: Theme.Spacing.s + 2) {
            header
            GeometryReader { geometry in
                RecLanes(model: model, width: geometry.size.width)
            }
            .frame(height: Self.height)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.m)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.text)
                    .frame(width: 30, height: 26)
                    .background(Theme.hover, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Oynat / durdur  Boşluk", "Play / pause  Space"))
            HStack(spacing: 4) {
                Text(verbatim: RecFormat.time(model.time)).foregroundStyle(Theme.text)
                Text(verbatim: "/ \(RecFormat.time(model.duration))").foregroundStyle(Theme.textMuted)
            }
            .font(Theme.small).monospacedDigit()
            Spacer()
            addButton(L("Yakınlaştır", "Zoom"), "plus.magnifyingglass", key: "Z") { model.addZoom() }
            addButton(L("Hızlandır", "Speed up"), "forward", key: "S") { model.addSpeed() }
            addButton(L("Kes", "Cut"), "scissors", key: "X") { model.addCut() }
            addButton(L("Not", "Note"), "text.bubble", key: "N") { model.addNote() }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 18)
            BarButton(symbol: model.looping ? "repeat.circle.fill" : "repeat", help: L("Döngü  L", "Loop  L"), active: model.looping) {
                model.looping.toggle()
            }
            BarButton(symbol: "keyboard", help: L("Kısayollar", "Shortcuts")) { showKeys.toggle() }
                .popover(isPresented: $showKeys, arrowEdge: .top) { RecShortcutList() }
        }
    }

    private func addButton(_ title: String, _ symbol: String, key: String, action: @escaping () -> Void) -> some View {
        RecHoverButton(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(title).font(Theme.small)
            }
        }
        .help(L("Oynatma çizgisine ekle  \(key)", "Add at the playhead  \(key)"))
    }
}

/// A plain button that lights up on hover, like the bar buttons but with a label.
struct RecHoverButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(hovering ? Theme.text : Theme.textMuted)
                .padding(.horizontal, Theme.Spacing.s).frame(height: 26)
                .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The ruler, the lanes and the playhead, `width` points wide.
private struct RecLanes: View {
    @Bindable var model: RecEditorModel
    let width: CGFloat
    /// Where the pointer is over the timeline, for a guide line and its time.
    @State private var hover: CGFloat?

    private var track: CGFloat { max(width - RecTimeline.gutter, 1) }
    private func x(_ t: Double) -> CGFloat { RecTimeline.gutter + CGFloat(t / max(model.duration, 0.01)) * track }
    private func time(_ x: CGFloat) -> Double { min(max(Double((x - RecTimeline.gutter) / track) * model.duration, 0), model.duration) }
    private func seconds(_ dx: CGFloat) -> Double { Double(dx / track) * model.duration }

    var body: some View {
        ZStack(alignment: .topLeading) {
            gutterIcons
            ruler
            videoRow
            lane(y: RecTimeline.zoomY, hint: L("Çift tıkla: yakınlaştırma ekle", "Double-click to add a zoom"), empty: model.edit.zooms.isEmpty) { model.addZoom(at: $0) }
            lane(y: RecTimeline.timeY, hint: L("Çift tıkla: hızlandır · kes için X", "Double-click to speed up · X to cut"),
                 empty: model.edit.speeds.isEmpty && model.edit.cuts.isEmpty) { model.addSpeed(at: $0) }
            lane(y: RecTimeline.textY, hint: L("Çift tıkla: not ekle", "Double-click to add a note"), empty: model.edit.notes.isEmpty && model.edit.captions.isEmpty) { model.addNote(at: $0) }
            // Caption lines: thin marks along the bottom of the text lane.
            ForEach(model.edit.captions) { line in
                Capsule().fill(Theme.textMuted.opacity(0.55))
                    .frame(width: max(3, x(line.end) - x(line.start) - 2), height: 4)
                    .offset(x: x(line.start) + 1, y: RecTimeline.textY + RecTimeline.lane - 7)
                    .allowsHitTesting(false)
            }
            ForEach(Array(model.edit.zooms.enumerated()), id: \.element.id) { index, zoom in
                RecPart(model: model, selection: .zoom(zoom.id), start: zoom.start, end: zoom.end, y: RecTimeline.zoomY,
                        symbol: zoom.focusX == nil ? "plus.magnifyingglass" : "scope", label: String(format: "%.1f×", zoom.scale),
                        style: .accent, track: track, x: x, seconds: seconds)
            }
            ForEach(model.edit.speeds) { speed in
                RecPart(model: model, selection: .speed(speed.id), start: speed.start, end: speed.end, y: RecTimeline.timeY,
                        symbol: "forward.fill", label: String(format: "%.1f×", speed.rate), style: .muted, track: track, x: x, seconds: seconds)
            }
            ForEach(model.edit.cuts) { cut in
                RecPart(model: model, selection: .cut(cut.id), start: cut.start, end: cut.end, y: RecTimeline.timeY,
                        symbol: "scissors", label: L("Kesildi", "Cut"), style: .cut, track: track, x: x, seconds: seconds)
            }
            ForEach(model.edit.notes) { note in
                RecPart(model: model, selection: .note(note.id), start: note.start, end: note.end, y: RecTimeline.textY,
                        symbol: note.arrow ? "arrow.up.right" : "text.bubble", label: note.text, style: .soft, track: track, x: x, seconds: seconds)
            }
            if let hover, hover >= RecTimeline.gutter, abs(hover - x(model.time)) > 4 {
                Rectangle().fill(Theme.text.opacity(0.35)).frame(width: 1, height: RecTimeline.height - RecTimeline.ruler)
                    .offset(x: hover, y: RecTimeline.ruler).allowsHitTesting(false)
                Text(verbatim: RecFormat.time(time(hover)))
                    .font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(Theme.text)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(MenuMaterial(blending: .withinWindow).clipShape(Capsule()))
                    .overlay(Capsule().strokeBorder(Theme.hairline))
                    .fixedSize()
                    .offset(x: min(hover + 4, width - 52), y: 2)
                    .allowsHitTesting(false)
            }
            playhead
        }
        .frame(width: width, height: RecTimeline.height, alignment: .topLeading)
        .onContinuousHover { phase in
            switch phase {
            case let .active(location): hover = location.x
            case .ended: hover = nil
            }
        }
        .coordinateSpace(name: "lanes")
    }

    // MARK: Rows

    private var gutterIcons: some View {
        ZStack(alignment: .topLeading) {
            ForEach([(RecTimeline.videoY, RecTimeline.video, "film"), (RecTimeline.zoomY, RecTimeline.lane, "plus.magnifyingglass"),
                     (RecTimeline.timeY, RecTimeline.lane, "forward"), (RecTimeline.textY, RecTimeline.lane, "text.bubble")], id: \.0) { y, height, symbol in
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                    .frame(width: RecTimeline.gutter - 6, height: height)
                    .offset(y: y)
            }
        }
        .allowsHitTesting(false)
    }

    /// Ticks every so many seconds (at least 64 points apart), labelled; drag it to scrub.
    private var ruler: some View {
        let steps: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300]
        let step = steps.first { CGFloat($0 / max(model.duration, 0.01)) * track >= 84 } ?? 600
        return Canvas { context, size in
            var t = 0.0
            while t <= model.duration + 0.0001 {
                let px = x(t)
                context.fill(Path(CGRect(x: px, y: size.height - 7, width: 1, height: 7)), with: .color(Theme.textMuted.opacity(0.6)))
                // Labels that would run off the end are left out.
                if px + 30 < size.width {
                    let text = step < 1 ? String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60)) : RecFormat.duration(t)
                    let label = Text(verbatim: text).font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.textMuted)
                    context.draw(label, at: CGPoint(x: px + 4, y: 4), anchor: .topLeading)
                }
                let half = t + step / 2
                if half < model.duration {
                    context.fill(Path(CGRect(x: x(half), y: size.height - 4, width: 1, height: 4)), with: .color(Theme.textMuted.opacity(0.35)))
                }
                t += step
            }
        }
        .frame(width: width, height: RecTimeline.ruler)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { model.seek(time($0.location.x)) })
        .help(L("Sürükle: kayıtta gez", "Drag to scrub"))
    }

    private var videoRow: some View {
        let left = x(0), right = x(model.duration)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, image in
                        Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: track / CGFloat(max(model.thumbnails.count, 1)), height: RecTimeline.video - 14).clipped()
                    }
                }
                .frame(width: track, height: RecTimeline.video - 14, alignment: .leading)
                // The loudness on its own strip, readable whatever the screen looked like.
                RecWaveformView(levels: model.waveform).frame(width: track, height: 14).background(Theme.track).allowsHitTesting(false)
            }
            .frame(width: track, height: RecTimeline.video, alignment: .leading)
            .background(Theme.field)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.hairline))
            .offset(x: left)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { model.seek(time($0.location.x + left)) })
            // Outside the kept part, dimmed.
            Rectangle().fill(.black.opacity(0.55))
                .frame(width: max(0, x(model.edit.trimStart) - left), height: RecTimeline.video)
                .offset(x: left).allowsHitTesting(false)
            Rectangle().fill(.black.opacity(0.55))
                .frame(width: max(0, right - x(model.trimEnd)), height: RecTimeline.video)
                .offset(x: x(model.trimEnd)).allowsHitTesting(false)
            RecTrimHandle(model: model, leading: true, at: x(model.edit.trimStart), time: time)
            RecTrimHandle(model: model, leading: false, at: x(model.trimEnd), time: time)
        }
        .offset(y: RecTimeline.videoY)
    }

    /// An empty lane: a soft track, a hint while it has nothing, double-click to add at that spot.
    private func lane(y: CGFloat, hint: String, empty: Bool, add: @escaping (Double) -> Void) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Theme.track)
            .overlay {
                if empty { Text(hint).font(Theme.small).foregroundStyle(Theme.textMuted.opacity(0.8)).allowsHitTesting(false) }
            }
            .frame(width: track, height: RecTimeline.lane)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, coordinateSpace: .local) { location in add(time(location.x + RecTimeline.gutter)) }
            .onTapGesture(count: 1, coordinateSpace: .local) { location in
                model.selection = nil
                model.seek(time(location.x + RecTimeline.gutter))
            }
            .offset(x: RecTimeline.gutter, y: y)
    }

    private var playhead: some View {
        let px = x(model.time)
        return ZStack(alignment: .top) {
            Rectangle().fill(Theme.accent).frame(width: 2, height: RecTimeline.height - 6).offset(y: 6)
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Theme.accent).frame(width: 11, height: 14)
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
        }
        .frame(width: 12)
        .offset(x: px - 6)
        .allowsHitTesting(false)
    }
}

/// The trim handle at either end of the video row.
private struct RecTrimHandle: View {
    @Bindable var model: RecEditorModel
    let leading: Bool
    let at: CGFloat
    let time: (CGFloat) -> Double
    @State private var hovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Theme.accent)
            .overlay(Capsule().fill(.white.opacity(0.9)).frame(width: 2, height: 16))
            .frame(width: hovering ? 10 : 8, height: RecTimeline.video)
            .offset(x: leading ? at : at - (hovering ? 10 : 8))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("lanes")).onChanged { drag in
                let t = time(drag.location.x)
                if leading { model.edit.trimStart = min(t, model.trimEnd - 0.5) } else { model.edit.trimEnd = max(t, model.edit.trimStart + 0.5) }
                model.seek(t)
            })
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .help(L("Baştan ya da sondan kırp", "Trim the start or the end"))
    }
}

/// One part on a lane: a zoom, a speed-up, a cut or a note.
private struct RecPart: View {
    enum Style { case accent, muted, cut, soft }

    @Bindable var model: RecEditorModel
    let selection: RecSelection
    let start: Double
    let end: Double
    let y: CGFloat
    let symbol: String
    let label: String
    let style: Style
    let track: CGFloat
    let x: (Double) -> CGFloat
    let seconds: (CGFloat) -> Double

    /// Where the drag began (start, end), so the part follows the pointer exactly instead of drifting.
    @State private var origin: (Double, Double)?
    @State private var hovering = false

    private var selected: Bool { model.selection == selection }
    private var id: UUID? {
        switch selection {
        case let .zoom(id), let .speed(id), let .cut(id), let .note(id): id
        }
    }

    private var fill: Color {
        switch style {
        case .accent: Theme.accent.opacity(selected ? 1 : 0.78)
        case .muted: Theme.textMuted.opacity(selected ? 0.85 : 0.55)
        case .cut: Theme.text.opacity(selected ? 0.85 : 0.6)
        case .soft: Theme.accent.opacity(selected ? 0.75 : 0.4)
        }
    }

    var body: some View {
        let width = max(16, x(end) - x(start))
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fill)
            .overlay {
                if style == .cut {
                    // Hatching: this part is left out.
                    Canvas { context, size in
                        var path = Path()
                        var px: CGFloat = -size.height
                        while px < size.width { path.move(to: CGPoint(x: px, y: size.height)); path.addLine(to: CGPoint(x: px + size.height, y: 0)); px += 7 }
                        context.stroke(path, with: .color(Theme.surface.opacity(0.25)), lineWidth: 1.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .overlay(alignment: .leading) {
                HStack(spacing: 4) {
                    Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                    Text(label).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(style == .cut || style == .muted ? Theme.surface : .white)
                .padding(.leading, 8).padding(.trailing, 10)
                .frame(width: width, alignment: .leading)
                .clipped()
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? Color.white.opacity(0.95) : .clear, lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(selected ? 0.25 : 0), radius: 3, y: 1)
            .overlay(alignment: .leading) { edge(leading: true) }
            .overlay(alignment: .trailing) { edge(leading: false) }
            .frame(width: width, height: RecTimeline.lane - 4)
            .scaleEffect(hovering && !selected ? 1.0 : 1, anchor: .center)
            .contentShape(Rectangle())
            .onTapGesture {
                model.selection = selected ? nil : selection
            }
            .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                let begin = origin ?? (start, end)
                origin = begin
                let length = begin.1 - begin.0
                var s = begin.0 + seconds(drag.translation.width)
                let snapped = model.snap(s, slop: seconds(7), except: id)
                let snappedEnd = model.snap(s + length, slop: seconds(7), except: id)
                if snapped != s { s = snapped } else if snappedEnd != s + length { s = snappedEnd - length }
                model.selection = selection
                model.setRange(selection, start: s, end: s + length)
            }.onEnded { _ in origin = nil })
            .onHover { hovering = $0 }
            .offset(x: x(start), y: y + 2)
            .animation(.spring(duration: 0.2), value: selected)
    }

    /// A grip on one edge: drag to stretch that side.
    private func edge(leading: Bool) -> some View {
        Color.clear
            .frame(width: 8)
            .overlay {
                if selected || hovering {
                    Capsule().fill(Color.white.opacity(0.9)).frame(width: 2, height: 10)
                }
            }
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1).onChanged { drag in
                let begin = origin ?? (start, end)
                origin = begin
                let moved = model.snap((leading ? begin.0 : begin.1) + seconds(drag.translation.width), slop: seconds(7), except: id)
                model.selection = selection
                if leading { model.setRange(selection, start: min(moved, begin.1 - 0.1), end: begin.1) } else { model.setRange(selection, start: begin.0, end: max(moved, begin.0 + 0.1)) }
            }.onEnded { _ in origin = nil })
    }
}

// MARK: - Loudness

/// The recording's loudness, read once off the main thread.
enum RecWaveform {
    nonisolated static func read(_ url: URL, bins: Int) -> [Float] {
        let asset = AVURLAsset(url: url)
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var tracks: [AVAssetTrack] = []
        Task.detached {
            tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            semaphore.signal()
        }
        semaphore.wait()
        guard !tracks.isEmpty, let reader = try? AVAssetReader(asset: asset) else { return [] }
        // Every voice mixed to one channel.
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
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
                path.addRoundedRect(in: CGRect(x: CGFloat(i) * step, y: size.height - h, width: max(1, step - 0.6), height: h), cornerSize: CGSize(width: 0.5, height: 0.5))
            }
            context.fill(path, with: .color(Theme.accent.opacity(0.75)))
        }
    }
}

/// Every key the editor answers, in one list.
struct RecShortcutList: View {
    private let rows: [(String, String)] = [
        ("Boşluk", L("Oynat / durdur (sondaysa baştan)", "Play / pause (from the start at the end)")),
        ("↩", L("Baştan oynat", "Play from the start")),
        ("← →", L("Bir kare geri / ileri", "One frame back / forward")),
        ("⇧← ⇧→", L("Bir saniye geri / ileri", "One second back / forward")),
        ("Home End", L("Başa / sona git", "Go to the start / end")),
        ("L", L("Döngü", "Loop")),
        ("Z", L("Yakınlaştırma ekle", "Add a zoom")),
        ("S", L("Hızlandırma ekle", "Add a speed-up")),
        ("X", L("Kes", "Cut")),
        ("N", L("Not ekle", "Add a note")),
        ("⌫", L("Seçileni sil", "Delete the selected part")),
        ("⎋", L("Seçimi bırak", "Deselect")),
        ("⌘Z ⇧⌘Z", L("Geri al / yinele", "Undo / redo")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Kısayollar", "Shortcuts")).font(Theme.bodyStrong).foregroundStyle(Theme.text).padding(.bottom, 2)
            ForEach(rows, id: \.0) { key, what in
                HStack(spacing: Theme.Spacing.m) {
                    Text(verbatim: key == "Boşluk" ? L("Boşluk", "Space") : key)
                        .font(Theme.smallStrong).monospaced().foregroundStyle(Theme.text)
                        .padding(.horizontal, 6).frame(minWidth: 64, minHeight: 20)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text(what).font(Theme.small).foregroundStyle(Theme.textMuted)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(width: 330)
    }
}
