import AppKit
import AVFoundation

/// The camera during a recording: its own file (camera.mov, H.264), with the time of its first frame on the host
/// clock so the editor can line it up with the screen, and a small live bubble so you can see yourself (Nabız's own
/// windows stay out of the screen recording, so the bubble isn't recorded twice).
final class RecCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "nabiz.rec.camera")
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var first: CMTime = .invalid
    private let lock = NSLock()
    private var preview: NSPanel?

    /// Asks for the camera if macOS hasn't been told yet. False when it's refused or there is none.
    static func allowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return AVCaptureDevice.default(for: .video) != nil
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start(to url: URL) throws {
        guard let device = AVCaptureDevice.default(for: .video) else { throw RecError.noCamera }
        let deviceInput = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        if session.canAddInput(deviceInput) { session.addInput(deviceInput) }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 600)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1280,
            AVVideoHeightKey: 720,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000] as [String: Any],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        self.writer = writer
        self.input = input
        session.startRunning()
        Task { @MainActor in self.showPreview() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let writer, let input else { return }
        let time = buffer.presentationTimeStamp
        if writer.status == .unknown {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: time)
            // The capture session's clock, moved onto the host clock the screen uses.
            let host = CMSyncConvertTime(time, from: session.synchronizationClock ?? CMClockGetHostTimeClock(), to: CMClockGetHostTimeClock())
            lock.withLock { first = host }
        }
        if writer.status == .writing, input.isReadyForMoreMediaData { input.append(buffer) }
    }

    /// Stops and returns the first frame's host time in seconds (nil if nothing was written).
    func stop() async -> Double? {
        session.stopRunning()
        await MainActor.run { hidePreview() }
        let written: Bool = await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let writer, writer.status == .writing else { continuation.resume(returning: false); return }
                input?.markAsFinished()
                writer.finishWriting { [self] in continuation.resume(returning: self.writer?.status == .completed) }
            }
        }
        let start = lock.withLock { first }
        return written && start.isValid ? start.seconds : nil
    }

    // MARK: The live bubble

    @MainActor
    private func showPreview() {
        let side: CGFloat = 150
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let panel = NSPanel(contentRect: NSRect(x: screen.maxX - side - 24, y: screen.minY + 24, width: side, height: side),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.wantsLayer = true
        view.layer?.cornerRadius = side / 2
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 3
        view.layer?.borderColor = NSColor.white.cgColor
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        layer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        view.layer?.addSublayer(layer)
        panel.contentView = view
        panel.orderFrontRegardless()
        preview = panel
    }

    @MainActor
    private func hidePreview() {
        preview?.orderOut(nil)
        preview = nil
    }
}
