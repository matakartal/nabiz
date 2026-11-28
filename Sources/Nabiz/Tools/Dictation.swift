// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import AVFoundation
import Speech
import SwiftUI

/// Type with your voice in any app: a shortcut starts listening, the words show live in a small bar at the bottom of
/// the screen, and the same shortcut (or Paste) types them where the cursor is. On-device when macOS has the language.
@MainActor
@Observable
final class Dictation {
    static let shared = Dictation()

    private(set) var isListening = false
    private(set) var text = ""
    private(set) var level: Float = 0
    @ObservationIgnored private var engine: DictationEngine?
    @ObservationIgnored private var hud: NSPanel?
    @ObservationIgnored private var startedAt: Date?

    func toggle() {
        if isListening { finish(paste: true) } else { start() }
    }

    static var locale: Locale {
        switch Prefs.string(Prefs.dictationLanguage) {
        case "tr": Locale(identifier: "tr-TR")
        case "en": Locale(identifier: "en-US")
        default: Prefs.isTurkish ? Locale(identifier: "tr-TR") : Locale(identifier: "en-US")
        }
    }

    func start() {
        guard !isListening else { return }
        Task {
            guard await Self.authorize() else {
                Monitor.panelActions.flash(L("Dikte için mikrofon ve konuşma tanıma izni gerekli", "Dictation needs microphone and speech recognition access"))
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                return
            }
            guard let recognizer = SFSpeechRecognizer(locale: Self.locale), recognizer.isAvailable else {
                Monitor.panelActions.flash(L("Bu dilde dikte şu an kullanılamıyor", "Dictation isn't available for this language right now"))
                return
            }
            let engine = DictationEngine(recognizer: recognizer,
                                         onText: { text in Task { @MainActor in Dictation.shared.text = text } },
                                         onLevel: { level in Task { @MainActor in Dictation.shared.level = level } },
                                         onError: { message in Task { @MainActor in Dictation.shared.failed(message) } })
            do {
                try engine.start()
            } catch {
                Monitor.panelActions.flash(L("Mikrofon açılamadı", "Couldn't open the microphone"))
                return
            }
            self.engine = engine
            text = ""
            level = 0
            isListening = true
            startedAt = Date()
            showHUD()
            // A forgotten session ends by itself.
            Task {
                try? await Task.sleep(for: .seconds(120))
                if Dictation.shared.isListening && Date().timeIntervalSince(Dictation.shared.startedAt ?? Date()) >= 119 {
                    Dictation.shared.finish(paste: true)
                }
            }
        }
    }

    func finish(paste: Bool) {
        guard isListening else { return }
        isListening = false
        engine?.stop()
        Task {
            // The last words arrive a moment after the audio ends.
            if paste { try? await Task.sleep(for: .milliseconds(700)) }
            let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
            engine?.cancel()
            engine = nil
            hideHUD()
            guard paste, !result.isEmpty else { return }
            // Typed where the cursor is; the clipboard comes back as it was.
            if Paster.canPaste {
                Paster.paste(result, delay: .zero)
            } else {
                ClipboardHistory.shared.writeOwn(result)
                Monitor.panelActions.flash(L("Kopyalandı; yapıştırabilirsin", "Copied; paste it anywhere"))
            }
        }
    }

    private func failed(_ message: String) {
        // "No speech" after stopping is normal.
        guard isListening else { return }
        Monitor.panelActions.flash(message)
        finish(paste: !text.isEmpty)
    }

    private static func authorize() async -> Bool {
        let speech: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    // MARK: The bar

    private func showHUD() {
        let panel = hud ?? {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 64),
                                styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            return panel
        }()
        hud = panel
        panel.contentView = NSHostingView(rootView: DictationBar())
        if let screen = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.midX - panel.frame.width / 2, y: screen.minY + 80))
        }
        panel.orderFrontRegardless()
    }

    private func hideHUD() {
        hud?.orderOut(nil)
        hud?.contentView = nil
    }
}

/// Audio in, words out; runs on the audio and speech threads and reports back through the closures.
final class DictationEngine: @unchecked Sendable {
    private let audio = AVAudioEngine()
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private let recognizer: SFSpeechRecognizer
    private var task: SFSpeechRecognitionTask?
    private let onText: @Sendable (String) -> Void
    private let onLevel: @Sendable (Float) -> Void
    private let onError: @Sendable (String) -> Void

    init(recognizer: SFSpeechRecognizer, onText: @escaping @Sendable (String) -> Void, onLevel: @escaping @Sendable (Float) -> Void,
         onError: @escaping @Sendable (String) -> Void) {
        self.recognizer = recognizer
        self.onText = onText
        self.onLevel = onLevel
        self.onError = onError
    }

    func start() throws {
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        nonisolated(unsafe) let request = request
        let onLevel = onLevel
        var lastLevel = Date.distantPast
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            guard Date().timeIntervalSince(lastLevel) > 0.08, let samples = buffer.floatChannelData?[0] else { return }
            lastLevel = Date()
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for index in 0..<count { sum += samples[index] * samples[index] }
            let rms = count > 0 ? (sum / Float(count)).squareRoot() : 0
            onLevel(min(rms * 12, 1))
        }
        audio.prepare()
        try audio.start()
        let onText = onText, onError = onError
        task = recognizer.recognitionTask(with: request) { result, error in
            if let result { onText(result.bestTranscription.formattedString) }
            if let error, result == nil {
                onError(L("Dikte durdu: \(error.localizedDescription)", "Dictation stopped: \(error.localizedDescription)"))
            }
        }
    }

    func stop() {
        audio.stop()
        audio.inputNode.removeTap(onBus: 0)
        request.endAudio()
    }

    func cancel() { task?.cancel() }
}

/// The floating bar: a level-driven mic, the words so far, Paste and Cancel.
private struct DictationBar: View {
    private let dictation = Dictation.shared

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.18)).frame(width: 30 + CGFloat(dictation.level) * 14)
                Image(systemName: "mic.fill").foregroundStyle(Theme.accent)
            }
            .frame(width: 44, height: 44)
            .animation(.easeOut(duration: 0.12), value: dictation.level)
            Text(verbatim: dictation.text.isEmpty ? L("Dinliyorum…", "Listening…") : String(dictation.text.suffix(160)))
                .font(Theme.body)
                .foregroundStyle(dictation.text.isEmpty ? Theme.textMuted : Theme.text)
                .lineLimit(2)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(L("Yapıştır", "Paste")) { dictation.finish(paste: true) }
                .buttonStyle(.borderedProminent).controlSize(.small)
            Button { dictation.finish(paste: false) } label: { Image(systemName: "xmark") }
                .buttonStyle(TextButtonStyle(color: Theme.textMuted))
                .help(L("Vazgeç", "Cancel"))
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(width: 460, height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
