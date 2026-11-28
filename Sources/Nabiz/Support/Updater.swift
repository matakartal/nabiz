// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Observation
import SwiftUI

/// Checks GitHub Releases once a day and installs a newer version in one click: shows what's new, downloads the
/// DMG, checks it is Nabız signed by its own developer, copies it over this one once Nabız has quit, and opens it
/// again. Anything that goes wrong on the way reopens the old app and says why on the next launch.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    struct Release: Equatable {
        let version: String
        let notes: String
        let dmg: URL
        let page: URL
    }

    /// What the last check said, for Settings → About.
    enum Status: Equatable {
        case idle, checking, upToDate
        case failed(String)
    }

    private(set) var available: Release?
    private(set) var installing = false
    private(set) var lastError: String?
    private(set) var status: Status = .idle

    /// The developer team every real Nabız is signed by; anything else is never installed.
    nonisolated static let teamID = "3Q2LK426HF"
    private static let api = URL(string: "https://api.github.com/repos/matakartal/nabiz/releases/latest")!
    private static let checkedKey = "updater.checkedAt"
    private static let skippedKey = "updater.skippedVersion"
    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// The last check that got an answer from GitHub (a failed one doesn't count).
    var checkedAt: Date? { UserDefaults.standard.object(forKey: Self.checkedKey) as? Date }
    /// Asked in the panel every few seconds: this keeps a failing network from being tried more than hourly.
    @ObservationIgnored private var attemptedAt: Date?
    @ObservationIgnored private var checkedThisRun = false

    /// Once a day at most, unless `force` (Settings → About → Check for updates), which also says what it found.
    func check(force: Bool = false) {
        if status == .checking { return }
        if !force {
            if checkedThisRun, let checkedAt, Date().timeIntervalSince(checkedAt) < 86_400 { return }
            if let attemptedAt, Date().timeIntervalSince(attemptedAt) < 3600 { return }
        }
        attemptedAt = Date()
        status = .checking
        Task {
            switch await Self.fetch() {
            case .success(let release):
                checkedThisRun = true
                UserDefaults.standard.set(Date(), forKey: Self.checkedKey)
                let newer = Self.isNewer(release.version, than: Self.current)
                let skipped = UserDefaults.standard.string(forKey: Self.skippedKey) == release.version
                available = newer && (force || !skipped) ? release : nil
                status = newer ? .idle : .upToDate
                if force, newer { UpdateWindow.show(release) }
            case .failure(let reason):
                status = .failed(reason.text)
            }
        }
    }

    private struct Reason: Error { let text: String }

    private static func fetch() async -> Result<Release, Reason> {
        var request = URLRequest(url: api, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .failure(Reason(text: error.localizedDescription))
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return .failure(Reason(text: L("henüz yayımlanmış sürüm yok", "no published release yet"))) }
        if code == 403 || code == 429 { return .failure(Reason(text: L("GitHub şimdilik çok fazla istek diyor, sonra dene", "GitHub says too many requests, try later"))) }
        guard code == 200 else { return .failure(Reason(text: L("GitHub \(code) yanıtı verdi", "GitHub answered \(code)"))) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let dmg = (json["assets"] as? [[String: Any]])?
                  .first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true })?["browser_download_url"] as? String,
              let dmgURL = URL(string: dmg)
        else { return .failure(Reason(text: L("GitHub'ın yanıtı okunamadı", "couldn't read GitHub's answer"))) }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return .success(Release(version: version, notes: json["body"] as? String ?? "", dmg: dmgURL, page: page))
    }

    /// "1.10.0" > "1.9.2".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let left = a.split(separator: ".").map { Int($0) ?? 0 }, right = b.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let x = index < left.count ? left[index] : 0, y = index < right.count ? right[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The panel's and Settings' update button: what's new first, then Install, Skip or Later.
    func offer() {
        guard let available else { return }
        UpdateWindow.show(available)
    }

    /// Not offered again until a newer version than this one comes out.
    func skip(_ release: Release) {
        UserDefaults.standard.set(release.version, forKey: Self.skippedKey)
        if available == release { available = nil }
    }

    /// Downloads, then hands over to a small script that waits for Nabız to quit, swaps the app and reopens it.
    func install() {
        guard let release = available, !installing else { return }
        installing = true
        lastError = nil
        Task {
            do {
                let (file, _) = try await URLSession.shared.download(from: release.dmg)
                let dmg = FileManager.default.temporaryDirectory.appendingPathComponent("Nabiz-\(release.version).dmg")
                try? FileManager.default.removeItem(at: dmg)
                try FileManager.default.moveItem(at: file, to: dmg)
                try relaunch(installing: dmg)
            } catch {
                installing = false
                lastError = L("İndirilemedi. Sürüm sayfasından elle indirebilirsin.", "Couldn't download. You can get it from the release page.")
            }
        }
    }

    /// Written by the install script when it refused or failed, read on the next launch.
    nonisolated static var failureFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nabiz/update-failed.txt")
    }

    /// The script's own words for why it stopped, in the person's language.
    static func failureText(_ code: String) -> String {
        switch code.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "mount": L("Güncelleme açılamadı (disk görüntüsü bağlanamadı)", "The update couldn't be opened (the disk image didn't mount)")
        case "missing": L("Güncellemede Nabız bulunamadı", "Nabız wasn't in the update")
        case "signature": L("Güncellemenin imzası geçersiz, kurulmadı", "The update's signature isn't valid, so it wasn't installed")
        case "team": L("Güncelleme Nabız'ın geliştiricisince imzalanmamış, kurulmadı", "The update isn't signed by Nabız's developer, so it wasn't installed")
        case "copy": L("Güncelleme kopyalanamadı, eski sürüm geri kondu", "The update couldn't be copied, the old version was put back")
        default: L("Güncelleme kurulamadı", "The update couldn't be installed")
        }
    }

    /// At launch: if the last install was refused, say why (in Settings, and briefly in the menu bar).
    func reportFailedInstall() {
        guard let code = try? String(contentsOf: Self.failureFile, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: Self.failureFile)
        lastError = Self.failureText(code)
        if let lastError { Monitor.panelActions.flash(lastError) }
    }

    /// The install script. Paths come in as arguments, never pasted into the script. Whatever fails, the old
    /// app is opened again, so nobody is left without Nabız.
    nonisolated static let installScript = """
    pid="$1"; app="$2"; dmg="$3"; mount="$4"; log="$5"; team="$6"
    while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
    fail() {
      mkdir -p "$(dirname "$log")"; echo "$1" > "$log"
      hdiutil detach "$mount" -quiet 2>/dev/null
      rm -f "$dmg"
      open "$app"
      exit 1
    }
    mkdir -p "$mount"
    hdiutil attach "$dmg" -nobrowse -quiet -mountpoint "$mount" || fail mount
    new="$mount/Nabiz.app"
    [ -d "$new" ] || fail missing
    /usr/bin/codesign --verify --deep --strict "$new" 2>/dev/null || fail signature
    signed=$(/usr/bin/codesign -dv "$new" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    [ "$signed" = "$team" ] || fail team
    rm -rf "$app.old"
    mv "$app" "$app.old" || fail copy
    if ditto "$new" "$app"; then
      rm -rf "$app.old"
    else
      rm -rf "$app"; mv "$app.old" "$app"
      fail copy
    fi
    hdiutil detach "$mount" -quiet
    rm -f "$dmg"
    open "$app"
    """

    private func relaunch(installing dmg: URL) throws {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("nabiz-update-mount").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", Self.installScript, "nabiz-update", String(ProcessInfo.processInfo.processIdentifier),
                             Bundle.main.bundleURL.path, dmg.path, mount, Self.failureFile.path, Self.teamID]
        try process.run()
        NSApp.terminate(nil)
    }
}

/// "Nabız 1.4 is out": its release notes, then Install, Skip this version or Later.
@MainActor
enum UpdateWindow {
    private static var window: NSWindow?

    static func show(_ release: Updater.Release) {
        window?.close()
        let view = UpdateView(release: release) { close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(Theme.surface)
        window.center()
        self.window = window
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            NSRunningApplication.current.activate(from: front, options: [])
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    static func close() {
        window?.close()
        window = nil
    }
}

struct UpdateView: View {
    let release: Updater.Release
    let onClose: () -> Void
    private let updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.m) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                    Text(L("Nabız \(release.version) çıktı", "Nabız \(release.version) is out")).font(Theme.title).foregroundStyle(Theme.text)
                    Text(L("Sende \(Updater.current) var. Yenilikler:", "You have \(Updater.current). What's new:"))
                        .font(Theme.small).foregroundStyle(Theme.textMuted)
                }
            }
            ScrollView {
                if release.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L("Bu sürüm için not yazılmamış.", "No notes for this version."))
                        .font(Theme.body).foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownView(text: release.notes, size: 13)
                }
            }
            .padding(Theme.Spacing.m)
            .frame(height: 260)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            if let error = updater.lastError {
                Text(verbatim: error).font(Theme.small).foregroundStyle(Theme.warning.mark)
            }
            HStack(spacing: Theme.Spacing.s) {
                Button(L("Bu sürümü atla", "Skip this version")) {
                    updater.skip(release)
                    onClose()
                }
                Button(L("Sürüm sayfası", "Release page")) { NSWorkspace.shared.open(release.page) }
                Spacer()
                Button(L("Sonra", "Later")) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    updater.install()
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        if updater.installing { ProgressView().controlSize(.small) }
                        Text(updater.installing ? L("İndiriliyor…", "Downloading…") : L("Kur ve yeniden aç", "Install and reopen"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(updater.installing)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 480)
        .background(Theme.surface)
    }
}
