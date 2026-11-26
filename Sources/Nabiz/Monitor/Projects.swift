// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import Foundation
import Observation

/// A git repository in the user's project folders, with what needs attention: changes not committed, commits not pushed.
struct Project: Sendable, Identifiable, Hashable {
    let path: String
    var branch: String?
    var upstream: String?
    var ahead = 0
    var behind = 0
    /// Files changed, staged or new.
    var changes = 0
    /// Last commit or checkout here (the HEAD reflog's time).
    var lastActivity: Date?
    var remote: URL?
    /// A linked worktree (its `.git` is a file).
    var isWorktree = false
    var stack: [Stack] = []
    /// "pnpm" / "npm" / "yarn" / "bun", from the lockfile.
    var packageManager: String?
    /// package.json scripts worth one click, in this order: dev, start, build, test.
    var scripts: [String] = []
    /// An .xcworkspace, .xcodeproj or Package.swift to open in Xcode.
    var xcode: String?

    enum Stack: String, Sendable, Hashable { case node, swift, xcode, rust, python, go, cloudflare, capacitor, docker }

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    /// "finqt-apps/pinpaw" for nested repos.
    var displayName: String {
        for root in DevCaches.roots where path.hasPrefix(root + "/") { return String(path.dropFirst(root.count + 1)) }
        return name
    }
    var needsAttention: Bool { changes > 0 || ahead > 0 }
    var unpushedWithoutUpstream: Bool { upstream == nil && branch != nil }
    var devCommand: String? {
        guard let script = scripts.first(where: { ["dev", "start"].contains($0) }) else { return nil }
        let runner = packageManager ?? "npm"
        return runner == "npm" ? "npm run \(script)" : "\(runner) \(script)"
    }

    /// "16 değişiklik · 20 gönderilmedi"
    var statusText: String {
        var parts: [String] = []
        if changes > 0 { parts.append(L("\(changes) değişiklik", "\(changes) changed")) }
        if ahead > 0 { parts.append(L("\(ahead) gönderilmedi", "\(ahead) unpushed")) }
        if behind > 0 { parts.append(L("\(behind) geride", "\(behind) behind")) }
        if parts.isEmpty { parts.append(L("temiz", "clean")) }
        return parts.joined(separator: " · ")
    }
}

enum Projects {
    /// Every repository under the project folders, three levels deep; hidden folders (agent worktrees in
    /// `.claude/worktrees`) and dependency folders are skipped. Blocking.
    static func find(maxDepth: Int = 3) -> [String] {
        let fm = FileManager.default
        var found: [String] = []
        let skip: Set<String> = ["node_modules", "Pods", "DerivedData", "build", "dist", "target", "vendor", "Library"]
        for root in DevCaches.roots {
            var stack: [(String, Int)] = [(root, 0)]
            while let (path, depth) = stack.popLast() {
                if path != root, fm.fileExists(atPath: path + "/.git") { found.append(path); continue }
                guard depth < maxDepth, let children = try? fm.contentsOfDirectory(atPath: path) else { continue }
                for name in children where !name.hasPrefix(".") && !skip.contains(name) {
                    var isDirectory: ObjCBool = false
                    let child = path + "/" + name
                    if fm.fileExists(atPath: child, isDirectory: &isDirectory), isDirectory.boolValue { stack.append((child, depth + 1)) }
                }
            }
        }
        return found.sorted()
    }

    /// Branch, changes and sync from `git status`, plus what's in the folder. Blocking (one git process).
    static func read(_ path: String) -> Project {
        var project = Project(path: path)
        let status = Shell.run("git", ["--no-optional-locks", "status", "--porcelain=v2", "--branch"], in: path, timeout: 15)
        if status.ok { apply(status: status.output, to: &project) }
        let gitDir = gitDirectory(path)
        project.isWorktree = gitDir.map { $0 != path + "/.git" } ?? false
        if let gitDir {
            let logs = (try? FileManager.default.attributesOfItem(atPath: gitDir + "/logs/HEAD"))?[.modificationDate] as? Date
            project.lastActivity = logs
            project.remote = remoteURL(config: commonDirectory(gitDir) + "/config")
        }
        describe(path, into: &project)
        return project
    }

    // MARK: Rules (pure, tested)

    /// Parses `git status --porcelain=v2 --branch`.
    static func apply(status: String, to project: inout Project) {
        var changes = 0
        for line in status.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("# branch.head ") {
                let head = String(line.dropFirst(14))
                project.branch = head == "(detached)" ? nil : head
            } else if line.hasPrefix("# branch.upstream ") {
                project.upstream = String(line.dropFirst(18))
            } else if line.hasPrefix("# branch.ab ") {
                let parts = line.dropFirst(12).split(separator: " ")
                if parts.count == 2 {
                    project.ahead = Int(parts[0].dropFirst()) ?? 0
                    project.behind = Int(parts[1].dropFirst()) ?? 0
                }
            } else if !line.hasPrefix("#") {
                changes += 1
            }
        }
        project.changes = changes
    }

    /// "git@github.com:o/r.git", "https://github.com/o/r.git", "ssh://git@github.com/o/r" → https://github.com/o/r.
    static func webURL(_ remote: String) -> URL? {
        var text = remote.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix(".git") { text = String(text.dropLast(4)) }
        if text.hasPrefix("git@") {
            text = String(text.dropFirst(4))
            guard let colon = text.firstIndex(of: ":") else { return nil }
            text = "https://" + text[..<colon] + "/" + text[text.index(after: colon)...]
        } else if text.hasPrefix("ssh://") {
            text = "https://" + text.dropFirst(6).replacingOccurrences(of: "git@", with: "")
        } else if text.hasPrefix("http://") || text.hasPrefix("https://") {
            // Drop a user:token@ part, never show it.
            if let at = text.firstIndex(of: "@"), let scheme = text.range(of: "://"), at > scheme.upperBound {
                text = String(text[..<scheme.upperBound]) + text[text.index(after: at)...]
            }
        } else {
            return nil
        }
        return URL(string: text)
    }

    /// The url of [remote "origin"] (else the first remote) in a git config file.
    static func remote(inConfig config: String) -> String? {
        var section = ""
        var urls: [(String, String)] = []
        for raw in config.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { section = line; continue }
            if section.hasPrefix("[remote "), line.hasPrefix("url") {
                if let equals = line.firstIndex(of: "=") {
                    urls.append((section, line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)))
                }
            }
        }
        return urls.first { $0.0 == "[remote \"origin\"]" }?.1 ?? urls.first?.1
    }

    /// Scripts worth a click, in a fixed order.
    static func usefulScripts(_ names: [String]) -> [String] {
        ["dev", "start", "build", "test", "lint", "typecheck", "deploy"].filter(names.contains)
    }

    // MARK: Folder

    private static func gitDirectory(_ path: String) -> String? {
        let dotGit = path + "/.git"
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return dotGit }
        guard let text = try? String(contentsOfFile: dotGit, encoding: .utf8), text.hasPrefix("gitdir:") else { return nil }
        let dir = text.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
        return dir.hasPrefix("/") ? dir : (path as NSString).appendingPathComponent(dir)
    }

    /// A worktree's git dir is `<main>/.git/worktrees/<name>`; its config is the main one's.
    private static func commonDirectory(_ gitDir: String) -> String {
        if let common = try? String(contentsOfFile: gitDir + "/commondir", encoding: .utf8) {
            let dir = common.trimmingCharacters(in: .whitespacesAndNewlines)
            return ((dir.hasPrefix("/") ? dir : (gitDir as NSString).appendingPathComponent(dir)) as NSString).standardizingPath
        }
        return gitDir
    }

    private static func remoteURL(config path: String) -> URL? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), let remote = remote(inConfig: text) else { return nil }
        return webURL(remote)
    }

    private static func describe(_ path: String, into project: inout Project) {
        let fm = FileManager.default
        let names = Set((try? fm.contentsOfDirectory(atPath: path)) ?? [])
        func has(_ name: String) -> Bool { names.contains(name) }
        if has("package.json") {
            project.stack.append(.node)
            if let data = fm.contents(atPath: path + "/package.json"),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let scripts = json["scripts"] as? [String: Any] {
                project.scripts = usefulScripts(Array(scripts.keys))
            }
        }
        if has("pnpm-lock.yaml") || has("pnpm-workspace.yaml") { project.packageManager = "pnpm" }
        else if has("bun.lockb") || has("bun.lock") { project.packageManager = "bun" }
        else if has("yarn.lock") { project.packageManager = "yarn" }
        else if has("package-lock.json") { project.packageManager = "npm" }
        if let workspace = names.sorted().first(where: { $0.hasSuffix(".xcworkspace") }) ?? names.sorted().first(where: { $0.hasSuffix(".xcodeproj") }) {
            project.stack.append(.xcode)
            project.xcode = path + "/" + workspace
        } else if has("project.yml"), let ios = ["ios", "iOS", "App"].first(where: has) {
            project.xcode = path + "/" + ios
        }
        if has("Package.swift") {
            project.stack.append(.swift)
            if project.xcode == nil { project.xcode = path + "/Package.swift" }
        }
        if has("Cargo.toml") { project.stack.append(.rust) }
        if has("pyproject.toml") || has("requirements.txt") { project.stack.append(.python) }
        if has("go.mod") { project.stack.append(.go) }
        if has("wrangler.toml") || has("wrangler.jsonc") || has("wrangler.json") { project.stack.append(.cloudflare) }
        if has("capacitor.config.ts") || has("capacitor.config.json") { project.stack.append(.capacitor) }
        if has("docker-compose.yml") || has("compose.yml") || has("compose.yaml") || has("docker-compose.yaml") { project.stack.append(.docker) }
    }
}

/// The user's repositories, read in the background: when the launcher or panel opens, at most once a minute.
@MainActor
@Observable
final class ProjectStore {
    static let shared = ProjectStore()
    private(set) var projects: [Project] = []
    private(set) var loaded = false
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var last = Date.distantPast

    /// Most recently active first.
    var recent: [Project] { projects.sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) } }

    func refresh(force: Bool = false) {
        guard !refreshing, force || Date().timeIntervalSince(last) > 60 else { return }
        refreshing = true
        Task {
            let found = await Task.detached(priority: .utility) { () -> [Project] in
                let paths = Projects.find()
                // A few git processes at once: 24 repos read in about a second.
                return await withTaskGroup(of: Project.self) { group in
                    var results: [Project] = []
                    var index = 0
                    for _ in 0..<min(4, paths.count) {
                        let path = paths[index]; index += 1
                        group.addTask { Projects.read(path) }
                    }
                    while let project = await group.next() {
                        results.append(project)
                        if index < paths.count {
                            let path = paths[index]; index += 1
                            group.addTask { Projects.read(path) }
                        }
                    }
                    return results
                }
            }.value
            projects = found
            loaded = true
            last = Date()
            refreshing = false
        }
    }

    func project(_ path: String) -> Project? { projects.first { $0.path == path } }
}

/// What can be done with a project, shared by the panel, the launcher and ⌘K.
@MainActor
enum ProjectActions {
    struct Editor: Sendable {
        let name: String
        let bundleID: String
    }

    static let editors: [Editor] = [
        Editor(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92"),
        Editor(name: "VS Code", bundleID: "com.microsoft.VSCode"),
        Editor(name: "Zed", bundleID: "dev.zed.Zed"),
        Editor(name: "Windsurf", bundleID: "com.exafunction.windsurf"),
        Editor(name: "Sublime Text", bundleID: "com.sublimetext.4"),
        Editor(name: "Nova", bundleID: "com.panic.Nova"),
    ]

    static var installedEditors: [Editor] { editors.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil } }

    /// The editor the user picked in Settings, else the first one installed.
    static var preferredEditor: Editor? {
        let chosen = Prefs.string(Prefs.devEditor)
        return installedEditors.first { $0.bundleID == chosen } ?? installedEditors.first
    }

    static func openInEditor(_ project: Project, editor: Editor? = nil) {
        guard let editor = editor ?? preferredEditor,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleID) else {
            NSWorkspace.shared.open(URL(fileURLWithPath: project.path))
            return
        }
        NSWorkspace.shared.open([URL(fileURLWithPath: project.path)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func openInXcode(_ project: Project) {
        guard let xcode = project.xcode,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: xcode)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func terminal(_ project: Project) { TerminalLauncher.open(project.path) }

    /// Claude Code (or Codex, Settings → Developer) in Terminal, in the project.
    static var agentName: String { Prefs.string(Prefs.devAgent) == "codex" ? "Codex" : "Claude Code" }

    static func agent(_ project: Project) {
        TerminalLauncher.open(project.path, run: Prefs.string(Prefs.devAgent) == "codex" ? "codex" : "claude", title: project.name)
    }

    static func runScript(_ project: Project, _ script: String) {
        let runner = project.packageManager ?? "npm"
        let command = runner == "npm" ? "npm run \(script)" : "\(runner) \(script)"
        TerminalLauncher.open(project.path, run: command, title: "\(project.name) · \(script)")
    }

    static func startDev(_ project: Project) {
        // Reuse a server that's already running instead of a second one on the next port.
        if let running = PortCache.shared.servers.first(where: { $0.project == project.path }), let url = running.url {
            NSWorkspace.shared.open(url)
            Monitor.panelActions.flash(L("Zaten açık: \(running.portsText)", "Already running: \(running.portsText)"))
            return
        }
        guard let command = project.devCommand else { return }
        TerminalLauncher.open(project.path, run: command, title: "\(project.name) · dev")
    }

    static func github(_ project: Project, pulls: Bool = false) {
        guard let remote = project.remote else { return }
        NSWorkspace.shared.open(pulls ? remote.appendingPathComponent("pulls") : remote)
    }

    static func reveal(_ project: Project) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.path)])
    }

    static func copyPath(_ project: Project) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(project.path, forType: .string)
        Monitor.panelActions.flash(L("Yol kopyalandı", "Path copied"))
    }
}
