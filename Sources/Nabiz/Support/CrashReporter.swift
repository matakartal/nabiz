// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import MetricKit

/// Keeps crash reports on this Mac so a crash isn't lost: macOS delivers them through MetricKit on the next launch,
/// and Objective-C exceptions are written the moment they happen. Nothing is sent anywhere; Settings → About
/// shows the latest one with a button to report it.
final class CrashReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = CrashReporter()

    static var folder: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nabiz/Crashes")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func start() {
        MXMetricManager.shared.add(self)
        NSSetUncaughtExceptionHandler { exception in
            let text = """
            \(exception.name.rawValue): \(exception.reason ?? "")
            \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · \(ProcessInfo.processInfo.operatingSystemVersionString)

            \(exception.callStackSymbols.joined(separator: "\n"))
            """
            let file = CrashReporter.folder.appendingPathComponent("exception-\(Int(Date().timeIntervalSince1970)).txt")
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads where !(payload.crashDiagnostics ?? []).isEmpty || !(payload.hangDiagnostics ?? []).isEmpty {
            let name = "diagnostic-\(Int(payload.timeStampEnd.timeIntervalSince1970)).json"
            try? payload.jsonRepresentation().write(to: Self.folder.appendingPathComponent(name))
        }
    }

    /// The newest report not yet sent, if any.
    static var latest: (url: URL, date: Date)? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let newest = files.compactMap { url -> (URL, Date)? in
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
            return (url, date)
        }.max { $0.1 < $1.1 }
        guard let newest, newest.0.lastPathComponent != UserDefaults.standard.string(forKey: reportedKey) else { return nil }
        return newest
    }

    private static let reportedKey = "crashReported"
    /// GitHub turns away issue links much longer than 8 KB; this leaves room to spare.
    static let urlLimit = 7_000

    /// Opens a new GitHub issue filled in with the report, for the person to look over and send. A report too long
    /// for the link is shortened there and copied in full to the clipboard. The button then goes away.
    @MainActor
    static func report(_ file: URL) {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let made = reportURL(text)
        guard let url = made.url else { return }
        if made.trimmed {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            let alert = NSAlert()
            alert.messageText = L("Raporun tamamı kopyalandı", "Full report copied")
            alert.informativeText = L("Rapor bağlantıya sığmadığı için kısaltıldı. Açılan sayfada kısaltılmış kısmın yerine yapıştır (⌘V).",
                                      "The report was too long for the link, so it was shortened. Paste it into the issue (⌘V) in place of the shortened part.")
            alert.runModal()
        }
        NSWorkspace.shared.open(url)
        UserDefaults.standard.set(file.lastPathComponent, forKey: reportedKey)
    }

    /// The issue's address, with as much of the report as fits under `limit` bytes once encoded.
    static func reportURL(_ report: String, limit: Int = urlLimit) -> (url: URL?, trimmed: Bool) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        func make(_ part: Substring, trimmed: Bool) -> URL? {
            var components = URLComponents(string: "https://github.com/matakartal/nabiz/issues/new")
            let note = trimmed ? "\n\n(Shortened. The full report was copied to the clipboard; paste it here.)" : ""
            components?.queryItems = [
                URLQueryItem(name: "title", value: "Crash in \(version)"),
                URLQueryItem(name: "body", value: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n\n```\n\(part)\n```\(note)"),
            ]
            return components?.url
        }
        func fits(_ url: URL?) -> Bool { (url?.absoluteString.utf8.count ?? .max) <= limit }
        if let url = make(report[...], trimmed: false), fits(url) { return (url, false) }
        // The longest start of the report that still fits, found by halving.
        var low = 0, high = report.count
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(make(report.prefix(middle), trimmed: true)) { low = middle } else { high = middle - 1 }
        }
        return (make(report.prefix(low), trimmed: true), true)
    }
}
