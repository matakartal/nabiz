// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Observation

/// Saves a video or its sound from YouTube, X, Instagram, TikTok, Vimeo and many more, with yt-dlp
/// (installed with Homebrew from Nabız when it's missing) and ffmpeg when present for the best quality.
@MainActor
@Observable
final class Downloader {
    static let shared = Downloader()

    enum Kind: String { case video, audio }

    enum Status: Equatable {
        case running, done, failed(String)
    }

    struct Job: Identifiable {
        let id = UUID()
        let url: String
        let kind: Kind
        var title: String
        var progress: Double?
        var eta: String?
        var status: Status = .running
        var file: URL?
    }

    private(set) var jobs: [Job] = []
    private(set) var installing = false
    @ObservationIgnored private var processes: [UUID: Process] = [:]

    static let videoHosts = [
        "youtube.com", "youtu.be", "x.com", "twitter.com", "instagram.com", "tiktok.com", "vimeo.com", "twitch.tv",
        "reddit.com", "facebook.com", "fb.watch", "dailymotion.com", "soundcloud.com", "bilibili.com", "threads.net",
        "linkedin.com", "bsky.app", "kick.com", "rumble.com", "streamable.com", "music.youtube.com",
    ]

    /// A web link worth offering a download for.
    static func videoURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme),
              let host = url.host?.lowercased() else { return nil }
        return videoHosts.contains { host == $0 || host.hasSuffix("." + $0) } ? url : nil
    }

    private static func tool(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "/opt/local/bin"]
            .map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var ytdlp: String? { Self.tool("yt-dlp") }
    var ffmpeg: String? { Self.tool("ffmpeg") }
    var brew: String? { Self.tool("brew") }

    var folder: URL {
        let saved = Prefs.string(Prefs.downloadFolder)
        if !saved.isEmpty, FileManager.default.fileExists(atPath: saved) { return URL(fileURLWithPath: saved) }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    var running: Job? { jobs.first { $0.status == .running } }

    // MARK: Downloading

    func download(_ url: String, kind: Kind) {
        guard let ytdlp else {
            install()
            return
        }
        var job = Job(url: url, kind: kind, title: url)
        job.title = URL(string: url)?.host ?? url
        jobs.insert(job, at: 0)
        if jobs.count > 20 { jobs.removeLast(jobs.count - 20) }

        var arguments = [
            "--newline", "--no-playlist", "--no-mtime", "--progress", "--no-simulate",
            "--progress-template", "download:NBZP|%(progress._percent_str)s|%(progress._eta_str)s",
            "--print", "before_dl:NBZT|%(title)s", "--print", "after_move:NBZF|%(filepath)s",
            "-P", folder.path, "-o", "%(title).150B [%(id)s].%(ext)s",
        ]
        if let ffmpeg { arguments += ["--ffmpeg-location", ffmpeg] }
        switch kind {
        case .audio:
            arguments += ffmpeg != nil ? ["-x", "--audio-format", "mp3", "--audio-quality", "0"] : ["-f", "ba[ext=m4a]/ba"]
        case .video:
            let limit = switch Prefs.string(Prefs.downloadQuality) {
            case "1080": "[height<=1080]"
            case "720": "[height<=720]"
            default: ""
            }
            arguments += ffmpeg != nil
                ? ["-f", "bv*\(limit)[ext=mp4]+ba[ext=m4a]/bv*\(limit)+ba/b\(limit)", "--merge-output-format", "mp4"]
                : ["-f", "b\(limit)[ext=mp4]/b\(limit)/b"]
        }
        arguments.append(url)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlp)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else {
            update(job.id) { $0.status = .failed(L("yt-dlp başlatılamadı", "yt-dlp didn't start")) }
            return
        }
        processes[job.id] = process
        let id = job.id
        let handle = pipe.fileHandleForReading
        nonisolated(unsafe) let running = process
        Task.detached(priority: .utility) {
            var lastError = ""
            do {
                for try await line in handle.bytes.lines {
                    if line.hasPrefix("ERROR:") { lastError = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
                    await MainActor.run { Downloader.shared.read(line, job: id) }
                }
            } catch {}
            running.waitUntilExit()
            let status = running.terminationStatus
            let error = lastError
            await MainActor.run { Downloader.shared.finish(id, status: status, error: error) }
        }
    }

    func cancel(_ id: UUID) {
        processes[id]?.terminate()
        processes[id] = nil
        jobs.removeAll { $0.id == id }
    }

    func retry(_ job: Job) {
        jobs.removeAll { $0.id == job.id }
        download(job.url, kind: job.kind)
    }

    func reveal(_ job: Job) {
        if let file = job.file { NSWorkspace.shared.activateFileViewerSelecting([file]) } else { NSWorkspace.shared.open(folder) }
    }

    func clearFinished() {
        jobs.removeAll { $0.status != .running }
    }

    private func read(_ line: String, job id: UUID) {
        if line.hasPrefix("NBZP|") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let percent = parts.count > 1 ? Double(parts[1].replacingOccurrences(of: "%", with: "")) : nil
            update(id) {
                $0.progress = percent.map { $0 / 100 }
                $0.eta = parts.count > 2 && parts[2] != "NA" && parts[2] != "Unknown" ? parts[2] : nil
            }
        } else if line.hasPrefix("NBZT|") {
            let title = String(line.dropFirst(5))
            update(id) { $0.title = title }
        } else if line.hasPrefix("NBZF|") {
            let path = String(line.dropFirst(5))
            update(id) { $0.file = URL(fileURLWithPath: path) }
        }
    }

    private func finish(_ id: UUID, status: Int32, error: String) {
        processes[id] = nil
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        if status == 0 {
            update(id) { $0.status = .done; $0.progress = 1 }
            NSSound(named: "Glass")?.play()
            Notifier.shared.post(id: "download-\(id)", title: job.kind == .audio ? L("Ses indirildi", "Audio saved") : L("Video indirildi", "Video saved"),
                                 body: job.title)
            Monitor.panelActions.flash(L("İndirildi", "Downloaded"))
        } else {
            update(id) { $0.status = .failed(error.isEmpty ? L("İndirilemedi", "Couldn't download") : error) }
            Monitor.panelActions.flash(L("İndirme başarısız", "Download failed"))
        }
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    // MARK: Installing yt-dlp

    /// yt-dlp (and ffmpeg for the best quality) with Homebrew; without Homebrew, opens the install page.
    func install() {
        guard !installing else { return }
        guard let brew else {
            NSWorkspace.shared.open(URL(string: "https://github.com/yt-dlp/yt-dlp/wiki/Installation")!)
            return
        }
        let alert = NSAlert()
        alert.messageText = L("Video indirmek için yt-dlp gerekli", "Downloading videos needs yt-dlp")
        alert.informativeText = L("Homebrew ile yt-dlp\(ffmpeg == nil ? " ve ffmpeg" : "") kurulsun mu? Açık kaynaklı, birkaç dakika sürebilir.",
                                  "Install yt-dlp\(ffmpeg == nil ? " and ffmpeg" : "") with Homebrew? It's open source and may take a few minutes.")
        alert.addButton(withTitle: L("Kur", "Install"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        installing = true
        Monitor.panelActions.flash(L("yt-dlp kuruluyor…", "Installing yt-dlp…"))
        let packages = ["install", "yt-dlp"] + (ffmpeg == nil ? ["ffmpeg"] : [])
        Task {
            let output = await Toolbox.run(brew, packages)
            installing = false
            if output != nil && ytdlp != nil {
                Monitor.panelActions.flash(L("yt-dlp hazır", "yt-dlp is ready"))
            } else {
                Monitor.panelActions.flash(L("Kurulamadı; Terminal'de: brew install yt-dlp", "Couldn't install; in Terminal: brew install yt-dlp"))
            }
        }
    }
}
