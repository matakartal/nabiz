// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
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

    /// The newest report, if any.
    static var latest: (url: URL, date: Date)? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.compactMap { url -> (URL, Date)? in
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
            return (url, date)
        }.max { $0.1 < $1.1 }
    }

    /// A new GitHub issue, filled in with the report, for the person to look over and send.
    static func reportURL(_ file: URL) -> URL? {
        let report = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        var components = URLComponents(string: "https://github.com/matakartal/nabiz/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: "Crash in \(version)"),
            URLQueryItem(name: "body", value: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n\n```\n\(report.prefix(5000))\n```"),
        ]
        return components?.url
    }
}
