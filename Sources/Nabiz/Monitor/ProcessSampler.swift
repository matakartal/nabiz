// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import Darwin

struct ProcessGroup: Sendable, Identifiable {
    enum Kind: Sendable {
        /// A regular app: can be quit.
        case app
        /// Every process an iOS simulator runs: shut down through simctl.
        case simulators
        /// Claude Code session processes: archive them in Claude, never kill them here.
        case claudeCode
        /// Docker and other virtual machines.
        case virtualMachine
        /// A command-line process.
        case tool
    }

    let id: String
    let name: String
    let kind: Kind
    /// The .app whose icon represents the group (and which "Quit" terminates for `.app`).
    let bundlePath: String?
    var memory: UInt64 = 0
    /// Share of the whole machine, 0...1.
    var cpu: Double = 0
    var count: Int = 0
}

/// Groups the current user's processes by app. Other users' processes (root daemons) are not readable without
/// privileges and are skipped. Memory is the physical footprint, the number Activity Monitor shows.
actor ProcessSampler {
    private var lastCPU: [pid_t: UInt64] = [:]
    private var lastTime: UInt64 = 0
    private var paths: [pid_t: String] = [:]
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(info.denom, 1)))
    }()
    private let cores = Double(ProcessInfo.processInfo.activeProcessorCount)

    func sample() -> [ProcessGroup] {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = lastTime == 0 ? 0 : Double(now - lastTime)
        var groups: [String: ProcessGroup] = [:]
        var seenCPU: [pid_t: UInt64] = [:]
        var seenPaths: [pid_t: String] = [:]

        for pid in allPIDs() where pid > 0 {
            var usage = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard ok == 0, let path = paths[pid] ?? Self.path(of: pid) else { continue }
            seenPaths[pid] = path

            let cpuNanos = (usage.ri_user_time + usage.ri_system_time) * timebase.numer / timebase.denom
            seenCPU[pid] = cpuNanos
            var share = 0.0
            if elapsed > 0, let previous = lastCPU[pid], cpuNanos >= previous {
                share = Double(cpuNanos - previous) / elapsed / cores
            }

            let info = Self.classify(path)
            var group = groups[info.id] ?? ProcessGroup(id: info.id, name: info.name, kind: info.kind, bundlePath: info.bundlePath)
            group.memory += usage.ri_phys_footprint
            group.cpu += share
            group.count += 1
            groups[info.id] = group
        }

        lastCPU = seenCPU
        paths = seenPaths
        lastTime = now
        return Array(groups.values)
    }

    private func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return Array(pids.prefix(Int(max(found, 0))))
    }

    private static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Found by bundle id, so a renamed Xcode (Xcode-beta.app) or an app outside /Applications still resolves.
    static let simulatorApp = appPath("com.apple.iphonesimulator") ?? developerSimulatorApp()
    static let claudeApp = appPath("com.anthropic.claudefordesktop")
    static let dockerApp = appPath("com.docker.docker")

    /// Simulator.app is often missing from LaunchServices; it lives inside the selected Xcode.
    private static func developerSimulatorApp() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let developer = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let path = developer + "/Applications/Simulator.app"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private static func appPath(_ bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
    }

    static func classify(_ path: String) -> (id: String, name: String, kind: ProcessGroup.Kind, bundlePath: String?) {
        let fm = FileManager.default
        if path.contains("/claude-code/") {
            return ("claude-code", "Claude Code", .claudeCode, claudeApp)
        }
        if path.contains("/CoreSimulator/") || path.contains("SimulatorRuntime") || path.contains("/Simulator.app/")
            || path.contains("/Android/sdk/emulator/") {
            return ("simulators", L("Simülatörler", "Simulators"), .simulators, simulatorApp)
        }
        if path.contains("Virtualization.framework") || path.contains("/Docker.app/") || path.contains("com.docker.") {
            return ("vm", dockerApp == nil ? L("Sanal makineler", "Virtual machines") : "Docker", .virtualMachine, dockerApp)
        }
        // The outermost bundle: helpers inside "Google Chrome.app/…/Helper.app" count as Chrome.
        if let range = path.range(of: ".app/") {
            let bundle = String(path[..<range.lowerBound]) + ".app"
            var name = fm.displayName(atPath: bundle)
            if name.hasSuffix(".app") { name.removeLast(4) }
            return (bundle, name, .app, bundle)
        }
        let executable = (path as NSString).lastPathComponent
        return ("tool:" + executable, executable, .tool, nil)
    }
}
