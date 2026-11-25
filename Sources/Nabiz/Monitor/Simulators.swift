import Foundation

struct Simulator: Sendable, Identifiable {
    let id: String
    let name: String
    let runtime: String
}

/// Booted iOS simulators through `xcrun simctl`. Blocking; call off the main actor.
enum Simulators {
    static func booted() -> [Simulator] {
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

    static func shutdown(_ udid: String) { _ = run(["simctl", "shutdown", udid]) }
    static func shutdownAll() { _ = run(["simctl", "shutdown", "all"]) }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-27-2" → "iOS 27.2"
    static func runtimeName(_ key: String) -> String {
        guard let tail = key.split(separator: ".").last else { return key }
        let parts = tail.split(separator: "-")
        guard let platform = parts.first else { return String(tail) }
        return parts.count > 1 ? "\(platform) \(parts.dropFirst().joined(separator: "."))" : String(platform)
    }

    private static func run(_ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
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
