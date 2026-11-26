// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation

struct Simulator: Sendable, Identifiable {
    let id: String
    let name: String
    let runtime: String
}

/// Booted iOS simulators (through `xcrun simctl`) and running Android emulators (through `adb`, when the Android SDK
/// is installed). Blocking; call off the main actor.
enum Simulators {
    static func booted() -> [Simulator] {
        apple() + android()
    }

    private static func apple() -> [Simulator] {
        guard let data = run(["simctl", "list", "devices", "booted", "-j"]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]]
        else { return [] }

        return devices.flatMap { runtimeKey, list in
            list.compactMap { device -> Simulator? in
                guard device["state"] as? String == "Booted",
                      let udid = device["udid"] as? String,
                      let name = device["name"] as? String
                else { return nil }
                return Simulator(id: udid, name: name, runtime: runtimeName(runtimeKey))
            }
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func shutdown(_ id: String) {
        if id.hasPrefix(androidPrefix) {
            _ = adb(["-s", String(id.dropFirst(androidPrefix.count)), "emu", "kill"])
        } else {
            _ = run(["simctl", "shutdown", id])
        }
    }

    static func shutdownAll() {
        _ = run(["simctl", "shutdown", "all"])
        for emulator in android() { shutdown(emulator.id) }
    }

    // MARK: Android

    private static let androidPrefix = "android:"

    /// `adb` from ANDROID_HOME, ANDROID_SDK_ROOT or the Android Studio default.
    private static let adbPath: String? = {
        let env = ProcessInfo.processInfo.environment
        let homes = [env["ANDROID_HOME"], env["ANDROID_SDK_ROOT"], NSHomeDirectory() + "/Library/Android/sdk"].compactMap { $0 }
        return homes.map { $0 + "/platform-tools/adb" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// "emulator-5554  device" lines, each named by its AVD ("Pixel_8_API_35" → "Pixel 8 API 35").
    private static func android() -> [Simulator] {
        guard adbPath != nil, let data = adb(["devices"]) else { return [] }
        let serials = String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2, parts[0].hasPrefix("emulator-"), parts[1] == "device" else { return nil }
            return String(parts[0])
        }
        return serials.map { serial in
            let name = adb(["-s", serial, "emu", "avd", "name"])
                .map { String(decoding: $0, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? serial }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: " ") } ?? serial
            return Simulator(id: androidPrefix + serial, name: name, runtime: "Android")
        }
    }

    private static func adb(_ arguments: [String]) -> Data? {
        guard let adbPath else { return nil }
        return run(arguments, tool: adbPath)
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-27-2" → "iOS 27.2"
    static func runtimeName(_ key: String) -> String {
        guard let tail = key.split(separator: ".").last else { return key }
        let parts = tail.split(separator: "-")
        guard let platform = parts.first else { return String(tail) }
        return parts.count > 1 ? "\(platform) \(parts.dropFirst().joined(separator: "."))" : String(platform)
    }

    private static func run(_ arguments: [String], tool: String = "/usr/bin/xcrun") -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
