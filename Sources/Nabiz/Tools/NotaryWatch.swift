// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import Foundation
import Observation

/// Notices a running `notarytool submit` (release scripts wait on it for up to an hour) and says when Apple answers:
/// no polling of Apple in between, one `notarytool history` call after the submit ends.
@MainActor
@Observable
final class NotaryWatch {
    static let shared = NotaryWatch()

    struct Submission: Sendable, Equatable {
        let started: Date
        let profile: String?
        let file: String?
    }

    private(set) var running: Submission?
    private(set) var lastResult: (status: String, name: String, date: Date)?
    @ObservationIgnored private var checking = false

    /// Called from the monitor's tick: a few milliseconds through libproc.
    func check() {
        guard Prefs.bool(Prefs.notaryWatch), !checking else { return }
        checking = true
        Task {
            let found = await Task.detached(priority: .utility) { Self.findSubmit() }.value
            checking = false
            if let found, running == nil {
                running = found
            } else if found == nil, let finished = running {
                running = nil
                await report(finished)
            }
        }
    }

    private func report(_ submission: Submission) async {
        let profile = submission.profile ?? (Prefs.string(Prefs.notaryProfile).isEmpty ? nil : Prefs.string(Prefs.notaryProfile))
        let latest = await Task.detached(priority: .utility) { profile.flatMap(Self.latest) }.value
        let elapsed = Format.duration(Date().timeIntervalSince(submission.started))
        let name = latest?.name ?? submission.file.map { ($0 as NSString).lastPathComponent } ?? "notarytool"
        let body: String
        switch latest?.status {
        case "Accepted": body = L("\(name): Apple onayladı (\(elapsed)).", "\(name): accepted by Apple (\(elapsed)).")
        case "Invalid": body = L("\(name): Apple reddetti. Neden için: xcrun notarytool log <id>", "\(name): rejected by Apple. For why: xcrun notarytool log <id>")
        case "Rejected": body = L("\(name): reddedildi.", "\(name): rejected.")
        default: body = L("Notarize bitti (\(elapsed)).", "Notarization finished (\(elapsed)).")
        }
        if let latest { lastResult = (latest.status, latest.name, Date()) }
        Notifier.shared.post(id: "notary-\(Int(submission.started.timeIntervalSince1970))", title: L("Notarize", "Notarization"), body: body)
    }

    // MARK: Off the main actor

    nonisolated static func findSubmit() -> Submission? {
        for pid in ProcInfo.allPIDs() {
            guard let info = ProcInfo.bsdInfo(pid), info.pbi_uid == getuid(), ProcInfo.name(info) == "notarytool" else { continue }
            let arguments = ProcInfo.arguments(pid)
            guard arguments.contains("submit") else { continue }
            return Submission(started: ProcInfo.started(info) ?? Date(), profile: value(after: "--keychain-profile", in: arguments) ?? value(after: "-p", in: arguments),
                              file: arguments.first { $0.hasSuffix(".zip") || $0.hasSuffix(".dmg") || $0.hasSuffix(".pkg") })
        }
        return nil
    }

    nonisolated static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// The newest submission in `notarytool history`.
    nonisolated static func latest(profile: String) -> (status: String, name: String)? {
        let result = Shell.run("/usr/bin/xcrun", ["notarytool", "history", "--keychain-profile", profile, "--output-format", "json"], timeout: 60)
        guard result.ok else { return nil }
        return parseHistory(result.output)
    }

    nonisolated static func parseHistory(_ json: String) -> (status: String, name: String)? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let history = object["history"] as? [[String: Any]], let first = history.first else { return nil }
        return (first["status"] as? String ?? "", first["name"] as? String ?? "")
    }
}
