// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import Darwin
import Foundation
import Observation

/// Who holds a TCP port on this Mac: any of the user's processes (not only project dev servers), named the way a
/// person would know it ("Docker", "AirPlay Receiver", "vite in pt-takip").
struct PortUse: Sendable, Identifiable, Hashable {
    let port: UInt16
    /// nil when a system process holds it (macOS doesn't show us which).
    let pid: pid_t?
    /// "vite", "Docker", "AirPlay Receiver".
    let name: String
    /// What it is, when that isn't obvious: "Control Center's AirPlay Receiver; turn it off in Settings → General → AirDrop & Handoff".
    let note: String?
    let folder: String?
    let project: String?
    let started: Date?
    let everyInterface: Bool
    /// The user's own process, so it can be stopped from here.
    let stoppable: Bool

    var id: String { "\(port)-\(pid ?? 0)" }
    var projectName: String? { project.map { ($0 as NSString).lastPathComponent } }
    var url: URL? { URL(string: "http://localhost:\(port)") }
}

enum Ports {
    /// Everything of the user's listening on TCP below the temporary range, lowest port first. Blocking.
    static func all() -> [PortUse] {
        let me = getpid()
        let uid = getuid()
        let home = NSHomeDirectory()
        var uses: [PortUse] = []
        for pid in ProcInfo.allPIDs() where pid != me {
            guard let info = ProcInfo.bsdInfo(pid), info.pbi_uid == uid else { continue }
            let process = ProcInfo.name(info)
            let executable = ProcInfo.executable(pid)
            let known = describe(process: process, executable: executable)
            // Docker publishes on any port (Supabase uses 54321…); everyone else's high ports are temporary links.
            let sockets = ProcInfo.listeningSockets(pid).filter { DevServers.isServerPort($0.port) || known?.name == "Docker" }
            guard !sockets.isEmpty else { continue }
            let folder = ProcInfo.workingFolder(pid)
            let inProject = folder.map { DevServers.isProjectFolder($0, home: home) } ?? false
            let tool = DevServers.toolName(ProcInfo.arguments(pid), fallback: process)
            for socket in sockets {
                uses.append(PortUse(port: socket.port, pid: pid, name: known?.name ?? tool, note: known?.note ?? (inProject ? nil : wellKnown(socket.port)),
                                    folder: inProject ? folder : nil,
                                    project: inProject ? folder.map { DevServers.projectRoot(of: $0, home: home) } : nil,
                                    started: ProcInfo.started(info), everyInterface: socket.everyInterface,
                                    stoppable: known?.stoppable ?? true))
            }
        }
        return uses.sorted { ($0.port, $0.pid ?? 0) < ($1.port, $1.pid ?? 0) }
    }

    /// Who holds this one port; a system process we can't see shows as one row without a pid.
    static func lookup(_ port: UInt16) -> [PortUse] {
        let found = all().filter { $0.port == port }
        if !found.isEmpty { return found }
        guard ProcInfo.somethingListens(on: port) else { return [] }
        return [PortUse(port: port, pid: nil, name: L("Sistem süreci", "A system process"),
                        note: wellKnown(port) ?? L("macOS'un kendi süreci; buradan durdurulamaz.", "Part of macOS; it can't be stopped from here."),
                        folder: nil, project: nil, started: nil, everyInterface: false, stoppable: false)]
    }

    /// Stops the process holding the port (the user's own only): a dev server with its `pnpm dev` wrapper.
    @discardableResult
    static func free(_ use: PortUse) -> Bool {
        guard let pid = use.pid, use.stoppable, let info = ProcInfo.bsdInfo(pid), info.pbi_uid == getuid() else { return false }
        return DevServers.stop(pid)
    }

    /// The next port from `start` that nothing listens on (for "which port is free?").
    static func firstFree(from start: UInt16) -> UInt16? {
        var port = start
        while port < 49152 {
            if !ProcInfo.somethingListens(on: port) && !isBound(port) { return port }
            port += 1
        }
        return nil
    }

    private static func isBound(_ port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return true }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = INADDR_ANY
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return result != 0
    }

    // MARK: Rules (pure, tested)

    /// "3000", ":3000", "port 3000", "port:3000" → 3000.
    static func query(_ text: String) -> UInt16? {
        var rest = text.trimmingCharacters(in: .whitespaces).lowercased()
        for prefix in ["port:", "port ", ":"] where rest.hasPrefix(prefix) {
            rest = String(rest.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            guard let port = UInt16(rest), port > 0 else { return nil }
            return port
        }
        return nil
    }

    /// Apps whose ports people trip over, by process name or executable.
    static func describe(process: String, executable: String?) -> (name: String, note: String?, stoppable: Bool)? {
        let path = executable ?? ""
        switch process {
        case "ControlCenter":
            return ("AirPlay Receiver", L("Denetim Merkezi'nin AirPlay alıcısı. Kapatmak için: Ayarlar → Genel → AirDrop ve Handoff → AirPlay Alıcısı.",
                                          "Control Center's AirPlay Receiver. Turn it off in Settings → General → AirDrop & Handoff → AirPlay Receiver."), false)
        case "rapportd": return ("Handoff", L("macOS'un Handoff/Continuity servisi.", "macOS Handoff/Continuity."), false)
        case "com.docker.backend", "com.docker.vpnkit", "vpnkit-bridge", "com.docker.krun", "docker-proxy":
            return ("Docker", L("Bir Docker konteynerinin portu; konteyneri durdur.", "A Docker container's port; stop the container."), false)
        case "OrbStack Helper", "orbstack-helper": return ("OrbStack", L("Bir OrbStack konteynerinin portu.", "An OrbStack container's port."), false)
        case "adb": return ("adb", L("Android Debug Bridge sunucusu.", "Android Debug Bridge server."), true)
        default: break
        }
        if path.contains("/Docker.app/") { return ("Docker", L("Bir Docker konteynerinin portu; konteyneri durdur.", "A Docker container's port; stop the container."), false) }
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/libexec/") || path.hasPrefix("/usr/sbin/") {
            return (process, L("macOS'un kendi süreci.", "Part of macOS."), false)
        }
        return nil
    }

    /// What usually runs on a port, to explain a busy one.
    static func wellKnown(_ port: UInt16) -> String? {
        switch port {
        case 3000: "Next, Remix, Rails, Express"
        case 3001...3010: L("İkinci bir Next/Node sunucusu", "A second Next/Node server")
        case 4200: "Angular"
        case 4321: "Astro"
        case 5000: L("AirPlay Alıcısı (macOS) ya da Flask", "AirPlay Receiver (macOS) or Flask")
        case 5173, 5174: "Vite"
        case 5432: "PostgreSQL"
        case 54321...54329: "Supabase"
        case 6379: "Redis"
        case 7000: L("AirPlay Alıcısı (macOS)", "AirPlay Receiver (macOS)")
        case 8000: "Django, python -m http.server"
        case 8080: L("Genel web sunucusu", "Generic web server")
        case 8787: "Wrangler (Cloudflare)"
        case 8081: "Metro (React Native)"
        case 9000: "MinIO, PHP-FPM"
        case 9229: L("Node hata ayıklayıcı", "Node debugger")
        case 27017: "MongoDB"
        case 3306: "MySQL"
        default: nil
        }
    }
}

/// The ports, read in the background so the launcher (rebuilt on every keystroke) never scans on the main thread.
@MainActor
@Observable
final class PortCache {
    static let shared = PortCache()
    private(set) var uses: [PortUse] = []
    private(set) var servers: [DevServer] = []
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var last = Date.distantPast

    /// Rescans unless it did within the last second.
    func refresh() {
        guard !refreshing, Date().timeIntervalSince(last) > 1 else { return }
        refreshing = true
        Task {
            let (uses, servers) = await Task.detached(priority: .userInitiated) { (Ports.all(), DevServers.running()) }.value
            self.uses = uses
            self.servers = servers
            last = Date()
            refreshing = false
        }
    }

    func forget(pid: pid_t) {
        uses.removeAll { $0.pid == pid }
        servers.removeAll { $0.pid == pid }
    }
}
