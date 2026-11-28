// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

/// Moving to Applications, and the update script never leaving the person without Nabız.
@MainActor
@Suite("App lifecycle")
struct LifecycleTests {
    init() {
        Prefs.registerDefaults()
        UserDefaults.standard.set("en", forKey: Prefs.language)
    }

    @Test func knowsWhereItRunsFrom() {
        let home = "/Users/someone"
        #expect(AppMover.place(of: "/Volumes/Nabiz/Nabiz.app", home: home) == .diskImage)
        #expect(AppMover.place(of: "/private/var/folders/x/AppTranslocation/ABC/d/Nabiz.app", home: home) == .translocated)
        #expect(AppMover.place(of: "/Users/someone/Downloads/Nabiz.app", home: home) == .downloads)
        #expect(AppMover.place(of: "/Applications/Nabiz.app", home: home) == nil)
        #expect(AppMover.place(of: "/Users/someone/Developer/nabiz/.build/debug/Nabiz", home: home) == nil)
    }

    @Test func crashLinkStaysShortEnoughForGitHub() {
        let short = CrashReporter.reportURL("EXC_BAD_ACCESS at 0x0")
        #expect(short.trimmed == false)
        #expect(short.url?.absoluteString.contains("EXC_BAD_ACCESS") == true)
        // A long report full of characters that grow when encoded.
        let long = String(repeating: "frame #12 {\"ş\": [1, 2]} <ğ> ", count: 2000)
        let made = CrashReporter.reportURL(long)
        #expect(made.trimmed)
        let length = made.url?.absoluteString.utf8.count ?? .max
        #expect(length <= CrashReporter.urlLimit)
        #expect(length > CrashReporter.urlLimit - 200)
    }

    @Test func findsRecordingsOlderThanThirtyDays() {
        let now = Date()
        let entries = [1, 29, 31, 400].map { days in
            RecLibrary.Entry(id: UUID(), created: now.addingTimeInterval(-Double(days) * 86_400), duration: 5, bytes: 100)
        }
        #expect(RecLibrary.older(than: 30, in: entries, now: now).count == 2)
    }

    @Test func resetKeepsTheWelcomeAndWhatsNewSeen() {
        #expect(SettingsReset.kept.contains(Prefs.seenVersion))
        #expect(SettingsReset.kept.contains(Prefs.onboarded))
    }

    /// The script, with `hdiutil` and `open` swapped for stand-ins: a mount that fails, and an app that isn't
    /// signed, both reopen the old app and leave the reason behind.
    @Test(arguments: ["mount", "signature"])
    func installScriptReopensTheOldAppOnFailure(_ failure: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nabiz-update-test-\(UUID().uuidString)")
        let bin = root.appendingPathComponent("bin"), app = root.appendingPathComponent("Old.app")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let opened = root.appendingPathComponent("opened.txt"), log = root.appendingPathComponent("log.txt")
        let attach = failure == "mount" ? "exit 1" : "[ \"$1\" = attach ] && mkdir -p \"$6/Nabiz.app\"; exit 0"
        try "#!/bin/sh\n\(attach)\n".write(to: bin.appendingPathComponent("hdiutil"), atomically: true, encoding: .utf8)
        try "#!/bin/sh\necho \"$1\" > \"\(opened.path)\"\n".write(to: bin.appendingPathComponent("open"), atomically: true, encoding: .utf8)
        for tool in ["hdiutil", "open"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.appendingPathComponent(tool).path)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.environment = ["PATH": bin.path + ":/usr/bin:/bin:/usr/sbin"]
        // A process id that isn't running, so the script doesn't wait.
        process.arguments = ["-c", Updater.installScript, "test", "999999", app.path, root.appendingPathComponent("x.dmg").path,
                             root.appendingPathComponent("mount").path, log.path, Updater.teamID]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 1)
        #expect((try? String(contentsOf: log, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) == failure)
        #expect((try? String(contentsOf: opened, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) == app.path)
        #expect(FileManager.default.fileExists(atPath: app.path))
        #expect(!Updater.failureText(failure).isEmpty)
    }
}
