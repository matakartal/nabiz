// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import Foundation
import Observation

/// One container from `docker ps -a`.
struct DockerContainer: Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let image: String
    let running: Bool
    /// "Up 5 hours (healthy)", "Exited (0) 2 days ago".
    let status: String
    /// Host ports it publishes, lowest first.
    let ports: [UInt16]
    /// Compose (or Supabase CLI) project name, else nil.
    let project: String?
    /// The folder the project was started from.
    let folder: String?
}

/// A compose project (or a lone container) as one panel row.
struct DockerGroup: Sendable, Identifiable, Hashable {
    let name: String
    let containers: [DockerContainer]
    let folder: String?

    var id: String { name }
    var running: Int { containers.filter(\.running).count }
    var ports: [UInt16] { Array(Set(containers.filter(\.running).flatMap(\.ports))).sorted() }
    /// Started from a folder that's gone (renamed or deleted project): usually safe to remove.
    var orphaned: Bool { folder.map { !FileManager.default.fileExists(atPath: $0) } ?? false }
}

enum Docker {
    static let cli = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker"]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? Shell.which("docker")

    /// Every container; nil when Docker isn't running. Blocking.
    static func containers() -> [DockerContainer]? {
        guard let cli else { return nil }
        let result = Shell.run(cli, ["ps", "-a", "--no-trunc", "--format", "{{json .}}"], timeout: 8)
        guard result.ok else { return nil }
        return result.output.split(separator: "\n").compactMap { parse(String($0)) }
    }

    static func run(_ arguments: [String]) -> Bool {
        guard let cli else { return false }
        return Shell.run(cli, arguments, timeout: 60).ok
    }

    // MARK: Rules (pure, tested)

    static func parse(_ line: String) -> DockerContainer? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["ID"] as? String else { return nil }
        let labels = self.labels(json["Labels"] as? String ?? "")
        let project = labels["com.docker.compose.project"] ?? labels["com.supabase.cli.project"]
        let folder = labels["com.docker.compose.project.working_dir"] ?? labels["com.supabase.cli.workdir"]
        return DockerContainer(id: String(id.prefix(12)), name: (json["Names"] as? String ?? id).components(separatedBy: ",").first ?? id,
                               image: json["Image"] as? String ?? "", running: (json["State"] as? String) == "running",
                               status: json["Status"] as? String ?? "", ports: hostPorts(json["Ports"] as? String ?? ""),
                               project: project, folder: folder)
    }

    /// "a=1,b=2" (values may hold "=").
    static func labels(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in text.split(separator: ",") {
            guard let equals = pair.firstIndex(of: "=") else { continue }
            result[String(pair[..<equals])] = String(pair[pair.index(after: equals)...])
        }
        return result
    }

    /// "0.0.0.0:54322->5432/tcp, [::]:54322->5432/tcp, 6379/tcp" → [54322].
    static func hostPorts(_ text: String) -> [UInt16] {
        var ports = Set<UInt16>()
        for part in text.split(separator: ",") {
            guard let arrow = part.range(of: "->") else { continue }
            let host = part[..<arrow.lowerBound]
            guard let colon = host.lastIndex(of: ":") else { continue }
            let range = host[host.index(after: colon)...]
            if let port = UInt16(range) { ports.insert(port) }
            else if let dash = range.firstIndex(of: "-"), let low = UInt16(range[..<dash]) { ports.insert(low) }
        }
        return ports.sorted()
    }

    static func groups(_ containers: [DockerContainer]) -> [DockerGroup] {
        var byProject: [String: [DockerContainer]] = [:]
        var order: [String] = []
        for container in containers {
            let key = container.project ?? container.name
            if byProject[key] == nil { order.append(key) }
            byProject[key, default: []].append(container)
        }
        return order.map { key in
            let list = byProject[key]!.sorted { $0.name < $1.name }
            return DockerGroup(name: key, containers: list, folder: list.compactMap(\.folder).first)
        }
        .sorted { ($0.running == 0 ? 1 : 0, $0.name) < ($1.running == 0 ? 1 : 0, $1.name) }
    }
}

/// Docker's containers for the panel, read while it's open (only when Docker itself is running).
@MainActor
@Observable
final class DockerStore {
    static let shared = DockerStore()
    private(set) var containers: [DockerContainer] = []
    private(set) var busy: Set<String> = []
    @ObservationIgnored private var refreshing = false

    var groups: [DockerGroup] { Docker.groups(containers) }
    var orphaned: [DockerGroup] { groups.filter(\.orphaned) }

    var summary: String {
        let running = containers.filter(\.running).count
        return L("\(running)/\(containers.count) çalışıyor", "\(running)/\(containers.count) running")
    }

    func refresh() {
        guard !refreshing, Docker.cli != nil,
              NSWorkspace.shared.runningApplications.contains(where: { ["com.docker.docker", "dev.kdrag0n.MacVirt"].contains($0.bundleIdentifier ?? "") }) else {
            if !refreshing { containers = [] }
            return
        }
        refreshing = true
        Task {
            containers = await Task.detached(priority: .utility) { Docker.containers() ?? [] }.value
            refreshing = false
        }
    }

    /// Starts or stops every container of the group.
    func toggle(_ group: DockerGroup) {
        let start = group.running == 0
        perform(group.name, start ? ["start"] : ["stop"], ids: group.containers.map(\.id),
                done: start ? L("\(group.name) başlatıldı", "Started \(group.name)") : L("\(group.name) durduruldu", "Stopped \(group.name)"))
    }

    func restart(_ group: DockerGroup) {
        perform(group.name, ["restart"], ids: group.containers.filter(\.running).map(\.id), done: L("\(group.name) yeniden başlatıldı", "Restarted \(group.name)"))
    }

    /// Removes the containers (not their volumes or images) after asking.
    func remove(_ group: DockerGroup) {
        let alert = NSAlert()
        alert.messageText = L("\(group.name) kaldırılsın mı?", "Remove \(group.name)?")
        alert.informativeText = L("\(group.containers.count) konteyner durdurulup silinir. Volume'lar ve imajlar kalır; verileriniz silinmez.",
                                  "\(group.containers.count) containers are stopped and deleted. Volumes and images stay; your data isn't deleted.")
        alert.addButton(withTitle: L("Kaldır", "Remove"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform(group.name, ["rm", "-f"], ids: group.containers.map(\.id), done: L("\(group.name) kaldırıldı", "Removed \(group.name)"))
    }

    func logs(_ container: DockerContainer) {
        guard let cli = Docker.cli else { return }
        TerminalLauncher.open(NSHomeDirectory(), run: "\(Shell.quote(cli)) logs -f --tail 200 \(container.id)", title: "\(container.name) · logs")
    }

    func shell(_ container: DockerContainer) {
        guard let cli = Docker.cli else { return }
        TerminalLauncher.open(NSHomeDirectory(), run: "\(Shell.quote(cli)) exec -it \(container.id) sh -c 'command -v bash >/dev/null && exec bash || exec sh'",
                              title: container.name)
    }

    private func perform(_ key: String, _ command: [String], ids: [String], done: String) {
        guard !ids.isEmpty else { return }
        busy.insert(key)
        Task {
            let ok = await Task.detached(priority: .userInitiated) { Docker.run(command + ids) }.value
            busy.remove(key)
            Monitor.panelActions.flash(ok ? done : L("Docker komutu başarısız oldu", "The Docker command failed"))
            refreshing = false
            refresh()
        }
    }
}
