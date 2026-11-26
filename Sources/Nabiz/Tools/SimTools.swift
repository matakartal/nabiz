// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import Foundation
import Observation

/// Things done to a booted iOS simulator through `simctl`: a clean status bar for App Store shots, dark mode,
/// deep links, screenshots into the markup editor, recordings, test pushes, an app's data folder.
@MainActor
@Observable
final class SimTools {
    static let shared = SimTools()

    struct App: Sendable, Hashable, Identifiable {
        let id: String
        let name: String
    }

    /// The user's own apps on each simulator, read when the panel shows it.
    private(set) var apps: [String: [App]] = [:]
    /// Simulators with a clean status bar.
    private(set) var cleanBar: Set<String> = []
    /// The simulator being recorded, and the recording.
    private(set) var recording: (udid: String, file: URL)?
    @ObservationIgnored private var recorder: Process?

    func loadApps(_ udid: String) {
        guard apps[udid] == nil else { return }
        apps[udid] = []
        Task {
            apps[udid] = await Task.detached(priority: .utility) { Self.userApps(udid) }.value
        }
    }

    func toggleStatusBar(_ udid: String) {
        let clean = !cleanBar.contains(udid)
        if clean { cleanBar.insert(udid) } else { cleanBar.remove(udid) }
        run(clean ? ["status_bar", udid, "override", "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
                     "--cellularMode", "active", "--cellularBars", "4", "--operatorName", "", "--batteryState", "charged", "--batteryLevel", "100"]
                  : ["status_bar", udid, "clear"],
            done: clean ? L("Durum çubuğu: 9:41, tam şarj", "Status bar: 9:41, fully charged") : L("Durum çubuğu eski hâlinde", "Status bar back to normal"))
    }

    func appearance(_ udid: String, dark: Bool) {
        run(["ui", udid, "appearance", dark ? "dark" : "light"], done: dark ? L("Simülatör karanlık modda", "Simulator in dark mode") : L("Simülatör açık modda", "Simulator in light mode"))
    }

    /// Opens the copied link (https://… or a deep link like myapp://…) in the simulator.
    func openCopiedURL(_ udid: String) {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text), url.scheme != nil, !text.contains(" ") else {
            Monitor.panelActions.flash(L("Önce bir bağlantı kopyala", "Copy a link first"))
            return
        }
        run(["openurl", udid, text], done: L("Simülatörde açıldı", "Opened in the simulator"))
    }

    /// A screenshot, opened in the markup editor.
    func screenshot(_ udid: String) {
        let file = Self.folder.appendingPathComponent("Simulator \(Self.stamp()).png")
        Task {
            let ok = await Shell.runAsync("/usr/bin/xcrun", ["simctl", "io", udid, "screenshot", "--type=png", file.path], timeout: 30).ok
            if ok { ShotEditor.show(file: file) } else { Monitor.panelActions.flash(L("Ekran görüntüsü alınamadı", "Couldn't take the screenshot")) }
        }
    }

    func toggleRecording(_ udid: String) {
        if let recorder, let recording {
            recorder.interrupt()
            self.recorder = nil
            self.recording = nil
            let file = recording.file
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                NSWorkspace.shared.activateFileViewerSelecting([file])
                Monitor.panelActions.flash(L("Kayıt kaydedildi", "Recording saved"))
            }
            return
        }
        let file = Self.folder.appendingPathComponent("Simulator \(Self.stamp()).mp4")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "io", udid, "recordVideo", "--codec=h264", "--force", file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        recorder = process
        recording = (udid, file)
        Monitor.panelActions.flash(L("Simülatör kaydediliyor", "Recording the simulator"))
    }

    /// A test notification to the app: the copied JSON payload, or a plain one.
    func push(_ udid: String, app: App) {
        let copied = NSPasteboard.general.string(forType: .string) ?? ""
        let payload = (try? JSONSerialization.jsonObject(with: Data(copied.utf8))) as? [String: Any]
        let body: [String: Any] = payload?["aps"] != nil ? payload! : ["aps": ["alert": ["title": app.name, "body": L("Nabız'dan test bildirimi", "A test notification from Nabız")], "sound": "default"]]
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nabiz-push.json")
        guard let data = try? JSONSerialization.data(withJSONObject: body), (try? data.write(to: file)) != nil else { return }
        run(["push", udid, app.id, file.path], done: payload?["aps"] != nil ? L("Kopyalanan bildirim gönderildi", "Copied payload sent") : L("Test bildirimi gönderildi", "Test notification sent"))
    }

    func openData(_ udid: String, app: App) {
        Task {
            let result = await Shell.runAsync("/usr/bin/xcrun", ["simctl", "get_app_container", udid, app.id, "data"], timeout: 15)
            let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.ok, !path.isEmpty { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        }
    }

    func resetPermissions(_ udid: String, app: App) {
        run(["privacy", udid, "reset", "all", app.id], done: L("\(app.name): izinler sıfırlandı", "\(app.name): permissions reset"))
    }

    func erase(_ udid: String, name: String) {
        let alert = NSAlert()
        alert.messageText = L("\(name) sıfırlansın mı?", "Erase \(name)?")
        alert.informativeText = L("Simülatör kapatılır; uygulamaları ve verileri silinir.", "The simulator shuts down; its apps and data are deleted.")
        alert.addButton(withTitle: L("Sıfırla", "Erase"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            _ = await Shell.runAsync("/usr/bin/xcrun", ["simctl", "shutdown", udid], timeout: 60)
            let ok = await Shell.runAsync("/usr/bin/xcrun", ["simctl", "erase", udid], timeout: 120).ok
            Monitor.panelActions.flash(ok ? L("\(name) sıfırlandı", "Erased \(name)") : L("Sıfırlanamadı", "Couldn't erase it"))
        }
    }

    private func run(_ arguments: [String], done: String) {
        Task {
            let ok = await Shell.runAsync("/usr/bin/xcrun", ["simctl"] + arguments, timeout: 30).ok
            Monitor.panelActions.flash(ok ? done : L("simctl başarısız oldu", "simctl failed"))
        }
    }

    // MARK: Off the main actor

    nonisolated static func userApps(_ udid: String) -> [App] {
        let list = Shell.run("/usr/bin/xcrun", ["simctl", "listapps", udid], timeout: 20)
        guard list.ok else { return [] }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nabiz-apps-\(udid).plist")
        guard (try? Data(list.output.utf8).write(to: file)) != nil,
              let data = try? Data(contentsOf: file),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]] else { return [] }
        try? FileManager.default.removeItem(at: file)
        return parseApps(plist)
    }

    nonisolated static func parseApps(_ plist: [String: [String: Any]]) -> [App] {
        plist.compactMap { id, info -> App? in
            guard info["ApplicationType"] as? String == "User" else { return nil }
            let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? id
            return App(id: id, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static var folder: URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return desktop
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }
}
