// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Darwin
import Foundation

/// A program of the user's listening on a local port from a project folder: `vite`, `next dev`, `python -m http.server`.
struct DevServer: Sendable, Identifiable, Hashable {
    let pid: pid_t
    /// Listening ports, lowest first.
    let ports: [UInt16]
    /// The folder it was started in.
    let folder: String
    /// The project it belongs to: the nearest folder above `folder` with a `.git`, else `folder`.
    let project: String
    /// What runs it, as a person would name it ("vite", "next", "http.server").
    let tool: String
    let started: Date?
    /// Listens on every interface, so a phone on the same Wi-Fi can open it (Vite and Next only do with `--host`).
    var reachableOnNetwork = false

    var id: pid_t { pid }
    var projectName: String { (project as NSString).lastPathComponent }
    /// "apps/web" when it runs below the project's root, else nil.
    var subfolder: String? {
        guard folder != project, folder.hasPrefix(project + "/") else { return nil }
        return String(folder.dropFirst(project.count + 1))
    }
    var portsText: String { ports.map { ":\($0)" }.joined(separator: " ") }
    var url: URL? { ports.first.flatMap { URL(string: "http://localhost:\($0)") } }
}

/// Finds dev servers through libproc (no `lsof`, a few milliseconds) and stops them. Blocking; call off the main actor.
///
/// A dev server is a process of this user that listens on TCP and was started from a folder in the home folder:
/// apps opened from Finder start in "/" and Docker's own helpers in ~/Library, so they never show. Ports from 49152
/// up are the system's temporary ones (AI tools and editors take them for their own links), so they don't count.
enum DevServers {
    static func running() -> [DevServer] {
        let me = getpid()
        let uid = getuid()
        let home = NSHomeDirectory()
        var servers: [DevServer] = []
        for pid in ProcInfo.allPIDs() where pid != me {
            guard let info = ProcInfo.bsdInfo(pid), info.pbi_uid == uid else { continue }
            let sockets = ProcInfo.listeningSockets(pid).filter { isServerPort($0.port) }
            let ports = sockets.map(\.port)
            guard !ports.isEmpty, let folder = ProcInfo.workingFolder(pid), isProjectFolder(folder, home: home) else { continue }
            servers.append(DevServer(pid: pid, ports: ports, folder: folder, project: projectRoot(of: folder, home: home),
                                     tool: toolName(ProcInfo.arguments(pid), fallback: ProcInfo.name(info)),
                                     started: ProcInfo.started(info),
                                     reachableOnNetwork: sockets.first?.everyInterface ?? false))
        }
        return servers.sorted { ($0.projectName.lowercased(), $0.ports.first ?? 0) < ($1.projectName.lowercased(), $1.ports.first ?? 0) }
    }

    /// Projects with more than one server running: the second one is usually forgotten.
    static func duplicateProjects(_ servers: [DevServer]) -> Set<String> {
        Set(Dictionary(grouping: servers, by: \.project).filter { $0.value.count > 1 }.keys)
    }

    /// Asks the server (and the `npm run` / `pnpm dev` wrapper that only exists for it) to quit, then forces it after
    /// two seconds. A wrapper that runs other things too (turbo, concurrently) is left alone. True when it's gone.
    @discardableResult
    static func stop(_ pid: pid_t) -> Bool {
        let chain = wrapperChain(pid)
        for process in chain { kill(process, SIGTERM) }
        for _ in 0..<20 {
            if !ProcInfo.isAlive(pid) { break }
            usleep(100_000)
        }
        for process in chain where ProcInfo.isAlive(process) { kill(process, SIGKILL) }
        usleep(100_000)
        return !ProcInfo.isAlive(pid)
    }

    // MARK: Rules (pure, tested)

    static func isServerPort(_ port: UInt16) -> Bool { port > 0 && port < 49152 }

    static func isProjectFolder(_ folder: String, home: String) -> Bool {
        folder.hasPrefix(home + "/") && !folder.hasPrefix(home + "/Library/") && !folder.hasPrefix(home + "/.")
    }

    /// The command line, named the way a person would: a package under node_modules by its package name,
    /// `python -m x` by x, a script by its file name, anything else by its program name.
    static func toolName(_ arguments: [String], fallback: String) -> String {
        guard let first = arguments.first else { return fallback }
        if let package = arguments.lazy.compactMap(nodePackage).first { return package }
        let program = programName(first)
        let interpreters = ["node", "bun", "deno", "ruby", "php", "java", "perl"]
        // Apple's own Python runs as ".../Python.framework/.../Python".
        if program.lowercased().hasPrefix("python") || interpreters.contains(program.lowercased()) {
            let rest = arguments.dropFirst()
            if let module = rest.firstIndex(of: "-m").map({ rest.index(after: $0) }), module < rest.endIndex {
                return rest[module]
            }
            if let script = rest.first(where: { !$0.hasPrefix("-") }) {
                return stripExtension((script as NSString).lastPathComponent)
            }
        }
        return program.isEmpty ? fallback : program
    }

    /// ".../node_modules/.pnpm/next@15/node_modules/next/dist/bin/next" → "next"; "@scope/pkg" keeps its scope.
    static func nodePackage(_ argument: String) -> String? {
        guard let range = argument.range(of: "/node_modules/", options: .backwards) else { return nil }
        let parts = argument[range.upperBound...].split(separator: "/").map(String.init)
        guard var name = parts.first else { return nil }
        if name == ".bin" { return parts.count > 1 ? parts[1] : nil }
        if name.hasPrefix("@"), parts.count > 1 { name += "/" + parts[1] }
        return name
    }

    /// "/usr/local/bin/node" → "node"; a process title like "next-server (v15.1.0)" → "next-server".
    static func programName(_ argument: String) -> String {
        let base = (argument as NSString).lastPathComponent
        return String(base.split(separator: " ").first ?? Substring(base))
    }

    private static func stripExtension(_ name: String) -> String {
        for ext in [".js", ".mjs", ".cjs", ".ts", ".mts", ".py", ".rb"] where name.hasSuffix(ext) {
            return String(name.dropLast(ext.count))
        }
        return name
    }

    // MARK: Processes

    private static let wrappers: Set<String> = ["node", "npm", "npx", "pnpm", "yarn", "bun", "deno", "tsx"]

    /// The server, then each parent that is a package runner with no other child (pnpm → node → vite).
    private static func wrapperChain(_ pid: pid_t) -> [pid_t] {
        var chain = [pid]
        var current = pid
        while let info = ProcInfo.bsdInfo(current) {
            let parent = pid_t(info.pbi_ppid)
            guard parent > 1, let parentInfo = ProcInfo.bsdInfo(parent), parentInfo.pbi_uid == getuid(),
                  wrappers.contains(ProcInfo.name(parentInfo)), ProcInfo.childCount(parent) == 1 else { break }
            chain.append(parent)
            current = parent
        }
        return chain
    }

    static func projectRoot(of folder: String, home: String) -> String {
        var current = folder
        while current.count > home.count {
            if FileManager.default.fileExists(atPath: current + "/.git") { return current }
            current = (current as NSString).deletingLastPathComponent
        }
        return folder
    }
}
