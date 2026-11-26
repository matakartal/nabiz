// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Observation

/// Checks GitHub Releases once a day and installs a newer version in one click: downloads the DMG, copies the app
/// over this one once Nabız has quit, and opens it again. While the repository is private, GitHub answers 404 to
/// anonymous checks and the updater simply stays quiet.
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

    private(set) var available: Release?
    private(set) var installing = false
    private(set) var lastError: String?
    @ObservationIgnored private var checkedAt: Date?

    private static let api = URL(string: "https://api.github.com/repos/matakartal/nabiz/releases/latest")!
    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// Once a day at most, unless `force` (Settings → About → Check now).
    func check(force: Bool = false) {
        if !force, let checkedAt, Date().timeIntervalSince(checkedAt) < 86_400 { return }
        checkedAt = Date()
        Task {
            var request = URLRequest(url: Self.api, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
                  let dmg = (json["assets"] as? [[String: Any]])?
                      .first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true })?["browser_download_url"] as? String,
                  let dmgURL = URL(string: dmg)
            else { return }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            available = Self.isNewer(version, than: Self.current)
                ? Release(version: version, notes: json["body"] as? String ?? "", dmg: dmgURL, page: page) : nil
        }
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

    private func relaunch(installing dmg: URL) throws {
        let app = Bundle.main.bundleURL.path
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("nabiz-update-mount").path
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        mkdir -p "\(mount)"
        hdiutil attach "\(dmg.path)" -nobrowse -quiet -mountpoint "\(mount)" || exit 1
        if [ -d "\(mount)/Nabiz.app" ]; then
          rm -rf "\(app).old" && mv "\(app)" "\(app).old" && ditto "\(mount)/Nabiz.app" "\(app)" && rm -rf "\(app).old" \\
            || { rm -rf "\(app)"; mv "\(app).old" "\(app)"; }
        fi
        hdiutil detach "\(mount)" -quiet
        rm -f "\(dmg.path)"
        open "\(app)"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        NSApp.terminate(nil)
    }
}
