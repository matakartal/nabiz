// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import Foundation
import Observation

/// One thing developer tools leave behind that can go, with its size and how it's removed.
struct CleanupItem: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable, CaseIterable {
        case simUnavailable, simNeverUsed, simRuntimes, xcodePreviews, derivedData, buildCopies
        case worktrees, nodeModules, pnpmStore, npmCache, brewCache, playwright, dockerVolumes, dockerImages
        case claudeTranscripts, mergedBranches
    }

    let kind: Kind
    let size: UInt64
    /// Paths (or ids: simulator udids, runtime ids, "repo|branch") the clean-up acts on.
    let targets: [String]
    /// Short list for the row's second line ("pt-takip, finqt · 4 more").
    let detail: String

    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .simUnavailable: L("Kullanılamayan simülatörler", "Unavailable simulators")
        case .simNeverUsed: L("Hiç açılmamış simülatörler", "Simulators never opened")
        case .simRuntimes: L("Fazladan iOS sürümleri", "Extra iOS runtimes")
        case .xcodePreviews: L("Xcode önizleme simülatörleri", "Xcode Previews simulators")
        case .derivedData: "DerivedData"
        case .buildCopies: L("Proje içindeki Xcode build klasörleri", "Xcode build folders inside projects")
        case .worktrees: L("Bitmiş ajan worktree'leri", "Finished agent worktrees")
        case .nodeModules: L("Eski projelerin node_modules'ü", "node_modules of idle projects")
        case .pnpmStore: L("pnpm deposu (kullanılmayanlar)", "pnpm store (unused packages)")
        case .npmCache: L("npm önbelleği", "npm cache")
        case .brewCache: L("Homebrew indirmeleri ve eski sürümler", "Homebrew downloads and old versions")
        case .playwright: L("Eski Playwright tarayıcıları", "Old Playwright browsers")
        case .dockerVolumes: L("Kullanılmayan Docker volume'ları", "Unused Docker volumes")
        case .dockerImages: L("Sahipsiz Docker imajları", "Dangling Docker images")
        case .claudeTranscripts: L("Silinmiş projelerin Claude geçmişi", "Claude history of deleted projects")
        case .mergedBranches: L("Birleştirilmiş yerel dallar", "Merged local branches")
        }
    }

    var explanation: String {
        switch kind {
        case .simUnavailable: L("Yüklü olmayan bir iOS sürümüne bağlı cihazlar; açılamazlar.", "Devices for an iOS version that's no longer installed; they can't start.")
        case .simNeverUsed: L("Hiç açılmamış, boş cihazlar. Xcode gerekince yenisini kurar.", "Empty devices that were never booted. Xcode makes new ones when needed.")
        case .simRuntimes: L("Aynı iOS sürümünün eski build'leri; en yenisi ve en son kullanılan kalır.", "Older builds of the same iOS version; the newest and the last used stay.")
        case .xcodePreviews: L("SwiftUI önizlemelerinin cihazları; Xcode yeniden kurar.", "Devices SwiftUI previews run on; Xcode rebuilds them.")
        case .derivedData: L("Xcode'un derleme önbelleği; ilk derleme biraz uzun sürer.", "Xcode's build cache; the next build takes a little longer.")
        case .buildCopies: L("-derivedDataPath ile proje içine yazılmış derlemeler (ajan ve CI çalışmaları). Yalnızca Build, Logs ve önbellek klasörleri silinir; kaynak kodun yanında olsa bile ona dokunulmaz.",
                             "Builds written into projects with -derivedDataPath (agent and CI runs). Only the Build, Logs and cache folders go; source code next to them is never touched.")
        case .worktrees: L("Ajanların açtığı, değişikliği ve saklanan dosyası (.env gibi) kalmamış, işi ana dala geçmiş worktree'ler. Silmeden hemen önce yeniden kontrol edilir.",
                           "Worktrees agents made, with no changes or kept files (like .env) left, whose work is already on the main branch. Checked again right before removal.")
        case .nodeModules: L("Lockfile'ı olan, kaydedilmemiş değişikliği olmayan ve uzun süredir dokunulmamış projeler; `install` ile geri gelir.",
                             "Projects with a lockfile, no uncommitted changes, untouched for a while; `install` brings them back.")
        case .pnpmStore: L("Hiçbir projenin kullanmadığı paketler (`pnpm store prune`).", "Packages no project uses (`pnpm store prune`).")
        case .npmCache: L("İndirilmiş paket arşivleri; npm gerekince yeniden indirir.", "Downloaded package archives; npm fetches them again when needed.")
        case .brewCache: L("Kurulumdan kalan indirmeler ve paketlerin eski sürümleri (`brew cleanup -s`); sabitlenenler kalır.",
                           "Downloads left from installs and older versions of packages (`brew cleanup -s`); pinned ones stay.")
        case .playwright: L("Her tarayıcının yalnızca en yeni sürümü kalır.", "Only the newest version of each browser stays.")
        case .dockerVolumes: L("Tarama sırasında hiçbir konteynerin bağlı olmadığı, adı listelenen volume'lar; o an hâlâ boşta olanlar silinir. İçlerindeki veriler gider.",
                               "The volumes listed by name that no container used at the scan, if still unused. Their data is deleted.")
        case .dockerImages: L("Etiketi kalmamış ara imajlar (`docker image prune`).", "Untagged leftover images (`docker image prune`).")
        case .claudeTranscripts: L("Klasörü artık olmayan projelerin sohbet kayıtları; Çöp'e taşınır.", "Chat logs of projects whose folder is gone; moved to the Trash.")
        case .mergedBranches: L("Ana dala birleşmiş dallar (`git branch -d`); birleşmemiş olan silinmez.", "Branches already merged into main (`git branch -d`); unmerged ones are never deleted.")
        }
    }

    var symbol: String {
        switch kind {
        case .simUnavailable, .simNeverUsed, .simRuntimes, .xcodePreviews: "iphone"
        case .derivedData, .buildCopies: "hammer"
        case .worktrees, .mergedBranches: "arrow.triangle.branch"
        case .nodeModules, .pnpmStore, .npmCache: "shippingbox"
        case .brewCache: "mug"
        case .playwright: "safari"
        case .dockerVolumes, .dockerImages: "cube"
        case .claudeTranscripts: "text.bubble"
        }
    }

    /// Safe to run unattended (the scheduled clean-up): everything comes back by itself, nothing of the user's is lost.
    var isSafe: Bool {
        switch kind {
        case .xcodePreviews, .buildCopies, .pnpmStore, .npmCache, .brewCache, .playwright, .dockerImages: true
        default: false
        }
    }
}

enum DevCleanup {
    // MARK: Scan

    /// Everything, biggest first. Blocking; takes a few seconds to a minute (sizing node_modules).
    static func scan() -> [CleanupItem] {
        let home = NSHomeDirectory()
        let projects = Projects.find()
        var items: [CleanupItem] = []
        let lock = NSLock()
        let jobs: [() -> [CleanupItem]] = [
            { simulators() },
            { xcode(home: home) },
            { buildCopies(projects: projects) },
            { worktrees(projects: projects) },
            { nodeModules(projects: projects) },
            { packageCaches(home: home) },
            { playwright(home: home) },
            { docker() },
            { claudeTranscripts(home: home) },
            { mergedBranches(projects: projects) },
        ]
        DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
            let found = jobs[index]()
            lock.lock(); items += found; lock.unlock()
        }
        return items.filter { $0.size > 0 || $0.kind == .mergedBranches && !$0.targets.isEmpty }.sorted { $0.size > $1.size }
    }

    private static func simulators() -> [CleanupItem] {
        var items: [CleanupItem] = []
        let devices = Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"], timeout: 30)
        if devices.ok, let json = try? JSONSerialization.jsonObject(with: Data(devices.output.utf8)) as? [String: Any],
           let byRuntime = json["devices"] as? [String: [[String: Any]]] {
            var unavailable: [(String, UInt64)] = []
            var neverUsed: [(String, String, UInt64)] = []
            for (_, list) in byRuntime {
                for device in list {
                    guard let udid = device["udid"] as? String else { continue }
                    let size = (device["dataPathSize"] as? NSNumber)?.uint64Value ?? 0
                    if (device["isAvailable"] as? Bool) == false { unavailable.append((udid, size)) }
                    else if isNeverUsed(state: device["state"] as? String, lastBooted: device["lastBootedAt"] as? String, dataSize: size) {
                        neverUsed.append((udid, device["name"] as? String ?? udid, size))
                    }
                }
            }
            if !unavailable.isEmpty {
                items.append(CleanupItem(kind: .simUnavailable, size: unavailable.reduce(0) { $0 + $1.1 }, targets: unavailable.map(\.0),
                                         detail: L("\(unavailable.count) cihaz", "\(unavailable.count) devices")))
            }
            if !neverUsed.isEmpty {
                items.append(CleanupItem(kind: .simNeverUsed, size: neverUsed.reduce(0) { $0 + $1.2 }, targets: neverUsed.map(\.0),
                                         detail: summary(neverUsed.map(\.1))))
            }
        }
        let runtimes = Shell.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"], timeout: 30)
        if runtimes.ok, let json = try? JSONSerialization.jsonObject(with: Data(runtimes.output.utf8)) as? [String: [String: Any]] {
            let list = json.values.compactMap { value -> Runtime? in
                guard let id = value["identifier"] as? String, let version = value["version"] as? String,
                      (value["deletable"] as? Bool) != false else { return nil }
                return Runtime(id: id, platform: value["platformIdentifier"] as? String ?? "", version: version,
                               build: value["build"] as? String ?? "", size: (value["sizeBytes"] as? NSNumber)?.uint64Value ?? 0,
                               lastUsed: (value["lastUsedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) })
            }
            let extra = extraRuntimes(list)
            if !extra.isEmpty {
                items.append(CleanupItem(kind: .simRuntimes, size: extra.reduce(0) { $0 + $1.size }, targets: extra.map(\.id),
                                         detail: extra.map { "iOS \($0.version) (\($0.build))" }.joined(separator: ", ")))
            }
        }
        return items
    }

    private static func xcode(home: String) -> [CleanupItem] {
        var items: [CleanupItem] = []
        let previews = home + "/Library/Developer/Xcode/UserData/Previews"
        let previewSize = sizes([previews]).first ?? 0
        if previewSize > 50 << 20 { items.append(CleanupItem(kind: .xcodePreviews, size: previewSize, targets: [previews], detail: "")) }
        let derived = home + "/Library/Developer/Xcode/DerivedData"
        let folders = ((try? FileManager.default.contentsOfDirectory(atPath: derived)) ?? []).filter { $0 != "ModuleCache.noindex" }.map { derived + "/" + $0 }
        let derivedSize = sizes(folders).reduce(0, +)
        if derivedSize > 0 {
            let names = folders.map { (($0 as NSString).lastPathComponent).components(separatedBy: "-").dropLast().joined(separator: "-") }
            items.append(CleanupItem(kind: .derivedData, size: derivedSize, targets: [derived], detail: summary(names)))
        }
        return items
    }

    /// Xcode build folders written into projects: a folder holding Build/Intermediates.noindex (or a DerivedData copy).
    private static func buildCopies(projects: [String]) -> [CleanupItem] {
        let fm = FileManager.default
        var found: [String] = []
        for project in projects {
            var stack: [(String, Int)] = [(project, 0)]
            while let (path, depth) = stack.popLast() {
                guard let children = try? fm.contentsOfDirectory(atPath: path) else { continue }
                for name in children where !name.hasPrefix(".") && name != "node_modules" && name != "Pods" {
                    let child = path + "/" + name
                    if isXcodeBuildFolder(child) {
                        // A build writing into it right now (an agent's xcodebuild) is left alone.
                        if !buildBusy(child) { found.append(child) }
                        continue
                    }
                    var isDirectory: ObjCBool = false
                    if depth < 3, fm.fileExists(atPath: child, isDirectory: &isDirectory), isDirectory.boolValue { stack.append((child, depth + 1)) }
                }
            }
        }
        // Only the build parts are counted (and removed), never what sits next to them.
        let sized = zip(found, found.map { sizes(buildParts(of: $0)).reduce(0, +) }).filter { $0.1 > 100 << 20 }
        guard !sized.isEmpty else { return [] }
        return [CleanupItem(kind: .buildCopies, size: sized.reduce(0) { $0 + $1.1 }, targets: sized.map(\.0),
                            detail: summary(sized.map { short($0.0) }))]
    }

    /// What `-derivedDataPath` writes; only these go, so a project folder holding a build is never removed itself.
    static let buildPartNames = ["Build", "Logs", "Index.noindex", "ModuleCache.noindex", "SourcePackages",
                                 "CompilationCache.noindex", "SDKStatCaches.noindex", "TextIndex"]

    static func buildParts(of folder: String) -> [String] {
        buildPartNames.map { folder + "/" + $0 }.filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Written to in the last hour anywhere a build writes (not only the top level), or Xcode is building.
    private static func buildBusy(_ path: String) -> Bool {
        let fm = FileManager.default
        let places = [path, path + "/Build", path + "/Build/Products", path + "/Build/Intermediates.noindex", path + "/Logs",
                      path + "/Logs/Build", path + "/Index.noindex"].filter { fm.fileExists(atPath: $0) }
        return places.contains { modified($0, within: 3600) }
    }

    /// Xcode or a command-line build is running: build folders and DerivedData wait.
    static var xcodeBuilding: Bool {
        let names: Set<String> = ["xcodebuild", "XCBBuildService", "SWBBuildService"]
        return ProcInfo.allPIDs().contains { pid in ProcInfo.bsdInfo(pid).map { names.contains(ProcInfo.name($0)) } ?? false }
    }

    /// Working folders of this user's processes: an agent, an editor's shell or a dev server sitting there.
    static func busyFolders() -> [String] {
        ProcInfo.allPIDs().compactMap { pid -> String? in
            guard let info = ProcInfo.bsdInfo(pid), info.pbi_uid == getuid() else { return nil }
            return ProcInfo.workingFolder(pid)
        }
    }

    static func isBusy(_ path: String, busy: [String]) -> Bool { busy.contains { $0 == path || $0.hasPrefix(path + "/") } }

    static func isXcodeBuildFolder(_ path: String) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: path + "/Build/Intermediates.noindex") || fm.fileExists(atPath: path + "/Build/Products")
            && fm.fileExists(atPath: path + "/Logs/Build") || fm.fileExists(atPath: path + "/info.plist") && fm.fileExists(atPath: path + "/Index.noindex")
    }

    /// `.claude/worktrees/*` (and any linked worktree) with nothing uncommitted whose HEAD is already in the main branch.
    private static func worktrees(projects: [String]) -> [CleanupItem] {
        // A worktree a running agent, editor or server sits in is in use, however clean it looks.
        let busy = busyFolders()
        var done: [(project: String, path: String)] = []
        for project in projects {
            let list = Shell.run("git", ["worktree", "list", "--porcelain"], in: project, timeout: 15)
            guard list.ok else { continue }
            let paths = list.output.split(separator: "\n").filter { $0.hasPrefix("worktree ") }.map { String($0.dropFirst(9)) }.filter { $0 != project }
            guard !paths.isEmpty, let main = defaultBranch(project) else { continue }
            for path in paths where worktreeIsDone(path, main: main, busy: busy) { done.append((project, path)) }
        }
        guard !done.isEmpty else { return [] }
        return [CleanupItem(kind: .worktrees, size: sizes(done.map(\.path)).reduce(0, +), targets: done.map { "\($0.project)|\($0.path)" },
                            detail: summary(done.map { short($0.path) }))]
    }

    /// Only worktrees agents make; one a person made for a hotfix is theirs to remove.
    static func isAgentWorktree(_ path: String) -> Bool {
        ["/.claude/worktrees/", "/.codex/", "/.cursor/", "/.conductor/", "/worktrees/"].contains { path.contains($0) }
    }

    /// Ignored files that rebuild themselves; any other ignored file (.env, a local database, keys) keeps the worktree.
    static let regenerable: Set<String> = ["node_modules", ".next", ".turbo", ".svelte-kit", ".nuxt", ".expo", ".build", "build",
                                           "DerivedData", ".swiftpm", ".DS_Store", ".gradle", "target", "__pycache__", ".pytest_cache",
                                           ".venv", ".cache", ".parcel-cache", "coverage", ".eslintcache", "tsconfig.tsbuildinfo"]

    /// `git status --porcelain --ignored`: nothing changed or untracked, and only regenerable ignored files.
    static func onlyRegenerable(_ status: String) -> Bool {
        status.split(separator: "\n").allSatisfy { line in
            guard line.hasPrefix("!! ") else { return false }
            let path = line.dropFirst(3).trimmingCharacters(in: CharacterSet(charactersIn: "\"/"))
            return path.split(separator: "/").last.map { regenerable.contains(String($0)) } ?? false
        }
    }

    /// Checked at the scan and again right before removal: an agent may have started in it since.
    static func worktreeIsDone(_ path: String, main: String, busy: [String]) -> Bool {
        guard FileManager.default.fileExists(atPath: path), isAgentWorktree(path), !isBusy(path, busy: busy), !recentlyUsed(path) else { return false }
        let status = Shell.run("git", ["--no-optional-locks", "status", "--porcelain", "--ignored"], in: path, timeout: 15)
        guard status.ok, onlyRegenerable(status.output) else { return false }
        return Shell.run("git", ["merge-base", "--is-ancestor", "HEAD", main], in: path, timeout: 15).status == 0
    }

    /// Anything in its top level changed in the last day: an agent may have just made it.
    private static func recentlyUsed(_ path: String) -> Bool { modified(path, within: 86_400) }

    private static func modified(_ path: String, within seconds: TimeInterval) -> Bool {
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: path)) ?? []) + ["."]
        let newest = names.compactMap { (try? fm.attributesOfItem(atPath: path + "/" + $0))?[.modificationDate] as? Date }.max()
        return newest.map { Date().timeIntervalSince($0) < seconds } ?? true
    }

    private static func nodeModules(projects: [String]) -> [CleanupItem] {
        let fm = FileManager.default
        let days = max(Prefs.int(Prefs.devStaleDays), 7)
        let busy = busyFolders()
        var targets: [String] = []
        var names: [String] = []
        for project in projects {
            guard projectIdle(project, days: days, busy: busy) else { continue }
            // The project and its workspace packages one level down (apps/*, packages/*).
            var folders = [project]
            for group in ["apps", "packages", "services"] {
                folders += ((try? fm.contentsOfDirectory(atPath: project + "/" + group)) ?? []).map { project + "/" + group + "/" + $0 }
            }
            guard hasLockfile(project) else { continue }
            var found = false
            for folder in folders {
                for name in ["node_modules", ".next", ".turbo", ".svelte-kit", ".nuxt", ".expo"] where fm.fileExists(atPath: folder + "/" + name) {
                    targets.append(project + "|" + folder + "/" + name)
                    found = true
                }
            }
            if found { names.append(short(project)) }
        }
        guard !targets.isEmpty else { return [] }
        let paths = targets.compactMap { $0.split(separator: "|", maxSplits: 1).last.map(String.init) }
        return [CleanupItem(kind: .nodeModules, size: sizes(paths).reduce(0, +), targets: targets, detail: summary(names))]
    }

    private static func packageCaches(home: String) -> [CleanupItem] {
        var items: [CleanupItem] = []
        if Shell.which("pnpm") != nil {
            let store = Shell.run("pnpm", ["store", "path"], timeout: 15).output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !store.isEmpty, FileManager.default.fileExists(atPath: store) {
                // Only part of it goes; show the store's size as the upper bound.
                items.append(CleanupItem(kind: .pnpmStore, size: sizes([store]).first ?? 0, targets: [store], detail: ""))
            }
        }
        let npm = home + "/.npm/_cacache"
        if Shell.which("npm") != nil, let size = sizes([npm]).first, size > 100 << 20 {
            items.append(CleanupItem(kind: .npmCache, size: size, targets: [npm], detail: ""))
        }
        let brew = home + "/Library/Caches/Homebrew"
        if Shell.which("brew") != nil, let size = sizes([brew]).first, size > 100 << 20 {
            items.append(CleanupItem(kind: .brewCache, size: size, targets: [brew], detail: ""))
        }
        return items
    }

    private static func playwright(home: String) -> [CleanupItem] {
        let root = home + "/Library/Caches/ms-playwright"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        let old = oldPlaywright(names).map { root + "/" + $0 }
        guard !old.isEmpty else { return [] }
        return [CleanupItem(kind: .playwright, size: sizes(old).reduce(0, +), targets: old, detail: summary(old.map { ($0 as NSString).lastPathComponent }))]
    }

    private static func docker() -> [CleanupItem] {
        guard let cli = Docker.cli,
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.docker.docker" }) else { return [] }
        let df = Shell.run(cli, ["system", "df", "--format", "{{json .}}"], timeout: 30)
        guard df.ok else { return [] }
        var items: [CleanupItem] = []
        for line in df.output.split(separator: "\n") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String],
                  let type = json["Type"], let reclaimable = json["Reclaimable"].flatMap(dockerBytes), reclaimable > 50 << 20 else { continue }
            if type == "Local Volumes" {
                let names = dangling(cli)
                if !names.isEmpty {
                    items.append(CleanupItem(kind: .dockerVolumes, size: reclaimable, targets: names, detail: summary(names)))
                }
            } else if type == "Images" {
                let dangling = Shell.run(cli, ["images", "-q", "--filter", "dangling=true"], timeout: 15).output.split(separator: "\n").count
                if dangling > 0 { items.append(CleanupItem(kind: .dockerImages, size: reclaimable, targets: [], detail: L("\(dangling) imaj", "\(dangling) images"))) }
            }
        }
        return items
    }

    private static func dangling(_ cli: String) -> [String] {
        Shell.run(cli, ["volume", "ls", "-q", "--filter", "dangling=true"], timeout: 15).output
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func claudeTranscripts(home: String) -> [CleanupItem] {
        let root = home + "/.claude/projects"
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        // Gone only when the name doesn't lead to a folder and the chats' own working folder is missing too.
        let gone = folders.compactMap { name -> (path: String, cwd: String)? in
            guard name.hasPrefix("-"), resolveClaudeFolder(name) == nil, let cwd = recordedFolder(root + "/" + name),
                  !FileManager.default.fileExists(atPath: cwd) else { return nil }
            return (root + "/" + name, cwd)
        }
        guard !gone.isEmpty else { return [] }
        return [CleanupItem(kind: .claudeTranscripts, size: sizes(gone.map(\.path)).reduce(0, +), targets: gone.map(\.path),
                            detail: summary(gone.map { short($0.cwd) }))]
    }

    private static func mergedBranches(projects: [String]) -> [CleanupItem] {
        var targets: [String] = []
        var names: [String] = []
        for project in projects {
            guard let main = defaultBranch(project) else { continue }
            let merged = Shell.run("git", ["branch", "--merged", main, "--format", "%(refname:short)%09%(HEAD)%09%(worktreepath)"], in: project, timeout: 15)
            guard merged.ok else { continue }
            let branches = deletableBranches(merged.output, main: main)
            if !branches.isEmpty { names.append("\(short(project)) \(branches.count)") }
            targets += branches.map { "\(project)|\($0)" }
        }
        guard !targets.isEmpty else { return [] }
        return [CleanupItem(kind: .mergedBranches, size: 0, targets: targets, detail: summary(names))]
    }

    /// The "cwd" a Claude Code transcript in this folder recorded.
    private static func recordedFolder(_ folder: String) -> String? {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".jsonl") }
        for file in files.prefix(3) {
            guard let handle = FileHandle(forReadingAtPath: folder + "/" + file) else { continue }
            let data = handle.readData(ofLength: 256 * 1024)
            try? handle.close()
            let text = String(decoding: data, as: UTF8.self)
            if let range = text.range(of: "\"cwd\":\""), let end = text[range.upperBound...].firstIndex(of: "\"") {
                return String(text[range.upperBound..<end])
            }
        }
        return nil
    }

    // MARK: Clean

    struct Outcome: Sendable {
        var freed: UInt64
        /// Targets left alone because they changed or came into use since the scan, or the tool refused.
        var skipped = 0
    }

    /// Runs one clean-up, checking each target again first. Blocking.
    @discardableResult
    static func clean(_ item: CleanupItem) -> Outcome {
        let fm = FileManager.default
        var skipped = 0
        switch item.kind {
        case .simUnavailable:
            // Only the devices the scan listed, and only if still unavailable (not every device an Xcode switch hides).
            let devices = Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"], timeout: 30)
            let still: Set<String> = {
                guard devices.ok, let json = try? JSONSerialization.jsonObject(with: Data(devices.output.utf8)) as? [String: Any],
                      let byRuntime = json["devices"] as? [String: [[String: Any]]] else { return [] }
                return Set(byRuntime.values.flatMap { $0 }.filter { ($0["isAvailable"] as? Bool) == false }.compactMap { $0["udid"] as? String })
            }()
            for udid in item.targets {
                if still.contains(udid), Shell.run("/usr/bin/xcrun", ["simctl", "delete", udid], timeout: 60).ok { continue }
                skipped += 1
            }
        case .simNeverUsed:
            for udid in item.targets { Shell.run("/usr/bin/xcrun", ["simctl", "delete", udid], timeout: 60) }
        case .simRuntimes:
            for id in item.targets { Shell.run("/usr/bin/xcrun", ["simctl", "runtime", "delete", id], timeout: 300) }
        case .xcodePreviews:
            Shell.run("/usr/bin/xcrun", ["simctl", "--set", "previews", "delete", "all"], timeout: 120)
        case .derivedData:
            if xcodeBuilding { skipped = item.targets.count } else { for path in item.targets { removeChildren(of: path) } }
        case .buildCopies:
            let building = xcodeBuilding
            for path in item.targets {
                guard !building, isXcodeBuildFolder(path), !buildBusy(path) else { skipped += 1; continue }
                for part in buildParts(of: path) { try? fm.removeItem(atPath: part) }
                // A folder that held nothing but the build goes too; one with anything else stays.
                let rest = ((try? fm.contentsOfDirectory(atPath: path)) ?? []).filter { !["info.plist", ".ds_store"].contains($0.lowercased()) }
                if rest.isEmpty { try? fm.removeItem(atPath: path) }
            }
        case .worktrees:
            let busy = busyFolders()
            for target in item.targets {
                let parts = target.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2, let main = defaultBranch(parts[0]), worktreeIsDone(parts[1], main: main, busy: busy),
                      Shell.run("git", ["worktree", "remove", parts[1]], in: parts[0], timeout: 60).ok else { skipped += 1; continue }
            }
        case .nodeModules:
            let allowed: Set<String> = ["node_modules", ".next", ".turbo", ".svelte-kit", ".nuxt", ".expo"]
            let days = max(Prefs.int(Prefs.devStaleDays), 7)
            let busy = busyFolders()
            var idle: [String: Bool] = [:]
            for target in item.targets {
                let parts = target.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2, allowed.contains((parts[1] as NSString).lastPathComponent), parts[1].hasPrefix(parts[0] + "/") else { skipped += 1; continue }
                let ok = idle[parts[0]] ?? projectIdle(parts[0], days: days, busy: busy)
                idle[parts[0]] = ok
                if ok { try? fm.removeItem(atPath: parts[1]) } else { skipped += 1 }
            }
        case .pnpmStore: Shell.run("pnpm", ["store", "prune"], timeout: 600)
        case .npmCache: Shell.run("npm", ["cache", "clean", "--force"], timeout: 600)
        case .brewCache: Shell.run("brew", ["cleanup", "-s", "--prune=all"], timeout: 600)
        case .playwright:
            for path in item.targets where path.contains("/ms-playwright/") { try? fm.removeItem(atPath: path) }
        case .dockerVolumes:
            // By name, and only the listed ones still unused now; never a prune of whatever is loose at this moment.
            guard let cli = Docker.cli else { skipped = item.targets.count; break }
            let now = Set(dangling(cli))
            for name in item.targets {
                if now.contains(name), Shell.run(cli, ["volume", "rm", name], timeout: 120).ok { continue }
                skipped += 1
            }
        case .dockerImages:
            if let cli = Docker.cli { Shell.run(cli, ["image", "prune", "-f"], timeout: 300) }
        case .claudeTranscripts:
            for path in item.targets where path.contains("/.claude/projects/") {
                try? fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            }
        case .mergedBranches:
            var stillMerged: [String: Set<String>] = [:]
            for target in item.targets {
                let parts = target.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { skipped += 1; continue }
                // Still in main and checked out nowhere, as decided now (`-d` alone only checks the upstream).
                if stillMerged[parts[0]] == nil {
                    let main = defaultBranch(parts[0])
                    let merged = main.map { Shell.run("git", ["branch", "--merged", $0, "--format", "%(refname:short)%09%(HEAD)%09%(worktreepath)"],
                                                      in: parts[0], timeout: 15) }
                    stillMerged[parts[0]] = merged.flatMap { $0.ok ? Set(deletableBranches($0.output, main: main ?? "")) : nil } ?? []
                }
                guard stillMerged[parts[0]]?.contains(parts[1]) == true,
                      Shell.run("git", ["branch", "-d", parts[1]], in: parts[0], timeout: 15).ok else { skipped += 1; continue }
            }
        }
        return Outcome(freed: skipped == 0 ? item.size : item.size / 2, skipped: skipped)
    }

    // MARK: Rules (pure, tested)

    struct Runtime: Equatable {
        let id: String
        var platform = ""
        let version: String
        let build: String
        let size: UInt64
        let lastUsed: Date?
    }

    /// Runtimes of a version installed more than once: all but the newest build and the last used one.
    static func extraRuntimes(_ runtimes: [Runtime]) -> [Runtime] {
        Dictionary(grouping: runtimes) { "\($0.platform) \($0.version)" }.values.flatMap { group -> [Runtime] in
            guard group.count > 1 else { return [] }
            let newest = group.max { $0.build.compare($1.build, options: .numeric) == .orderedAscending }
            let used = group.filter { $0.lastUsed != nil }.max { $0.lastUsed! < $1.lastUsed! }
            return group.filter { $0.id != newest?.id && $0.id != used?.id }
        }
        .sorted { $0.size > $1.size }
    }

    /// Never booted, shut down and about as big as a fresh device (~20 MB).
    static func isNeverUsed(state: String?, lastBooted: String?, dataSize: UInt64) -> Bool {
        state == "Shutdown" && lastBooted == nil && dataSize < 40 << 20
    }

    /// Of "chromium-1248", "chromium-1254", "webkit-2370": the older numbers of each browser.
    static func oldPlaywright(_ names: [String]) -> [String] {
        var newest: [String: Int] = [:]
        var parsed: [(String, String, Int)] = []
        for name in names {
            guard let dash = name.lastIndex(of: "-"), let number = Int(name[name.index(after: dash)...]) else { continue }
            let browser = String(name[..<dash])
            parsed.append((name, browser, number))
            newest[browser] = max(newest[browser] ?? 0, number)
        }
        return parsed.filter { $0.2 < newest[$0.1]! }.map(\.0).sorted()
    }

    /// `git branch --merged` lines ("name\t*\tpath"): not main/master/develop, not checked out here or in a worktree.
    static func deletableBranches(_ output: String, main: String) -> [String] {
        let keep: Set<String> = [main, "main", "master", "develop", "dev", "staging", "production", "release"]
        return output.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let name = fields.first, !name.isEmpty, !keep.contains(name), !name.hasPrefix("(") else { return nil }
            if fields.count > 1, fields[1] == "*" { return nil }
            if fields.count > 2, !fields[2].isEmpty { return nil }
            return name
        }
    }

    /// "10.48GB (84%)" → bytes.
    static func dockerBytes(_ text: String) -> UInt64? {
        let value = text.split(separator: " ").first.map(String.init) ?? text
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for (unit, scale) in units where value.hasSuffix(unit) {
            guard let number = Double(value.dropLast(unit.count)) else { return nil }
            return UInt64(number * scale)
        }
        return nil
    }

    /// "-Users-me-Developer-pt-takip--claude-worktrees-x" → the folder it stands for, if it still exists. Claude Code
    /// writes every character that isn't a letter or digit as "-", so each "-" is tried as "/", "." or itself.
    static func resolveClaudeFolder(_ name: String, root: String = "/") -> String? {
        guard name.hasPrefix("-") else { return nil }
        return resolve(String(name.dropFirst()), in: root)
    }

    private static func resolve(_ rest: String, in folder: String) -> String? {
        if rest.isEmpty { return folder }
        guard let children = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return nil }
        for child in children {
            let encoded = String(child.map { $0.isLetter && $0.isASCII || $0.isNumber ? $0 : "-" })
            guard rest == encoded || rest.hasPrefix(encoded + "-") else { continue }
            let path = (folder as NSString).appendingPathComponent(child)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let remaining = rest == encoded ? "" : String(rest.dropFirst(encoded.count + 1))
            if let found = resolve(remaining, in: path) { return found }
        }
        return nil
    }

    // MARK: Helpers

    /// Sizes of several paths with one `du` (C, much faster than walking in Swift). Missing paths are 0.
    static func sizes(_ paths: [String]) -> [UInt64] {
        guard !paths.isEmpty else { return [] }
        var result: [String: UInt64] = [:]
        for chunk in stride(from: 0, to: paths.count, by: 200).map({ Array(paths[$0..<min($0 + 200, paths.count)]) }) {
            let existing = chunk.filter { FileManager.default.fileExists(atPath: $0) }
            guard !existing.isEmpty else { continue }
            let du = Shell.run("/usr/bin/du", ["-sk"] + existing, timeout: 300)
            for line in du.output.split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 1)
                if parts.count == 2, let kb = UInt64(parts[0]) { result[String(parts[1])] = kb * 1024 }
            }
        }
        return paths.map { result[$0] ?? 0 }
    }

    private static func removeChildren(of folder: String) {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] {
            try? FileManager.default.removeItem(atPath: folder + "/" + name)
        }
    }

    private static func defaultBranch(_ project: String) -> String? {
        let head = Shell.run("git", ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: project, timeout: 10)
        if head.ok {
            let name = head.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if let slash = name.firstIndex(of: "/") { return String(name[name.index(after: slash)...]) }
        }
        for name in ["main", "master"] where Shell.run("git", ["rev-parse", "--verify", "--quiet", name], in: project, timeout: 10).ok {
            return name
        }
        return nil
    }

    /// Untouched for `days`, nothing uncommitted, and no process working in it (a dev server needs its modules).
    static func projectIdle(_ project: String, days: Int, busy: [String]) -> Bool {
        guard !isBusy(project, busy: busy), let last = lastTouched(project), Date().timeIntervalSince(last) > Double(days) * 86_400 else { return false }
        let status = Shell.run("git", ["--no-optional-locks", "status", "--porcelain"], in: project, timeout: 15)
        return !status.ok || status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The newest change: git's own files (wherever the git dir is, worktrees too), package.json and the source
    /// folders' top levels, so weeks of uncommitted editing count as use.
    private static func lastTouched(_ project: String) -> Date? {
        let fm = FileManager.default
        var paths = [project + "/package.json"]
        let gitDir = Shell.run("git", ["rev-parse", "--absolute-git-dir"], in: project, timeout: 10)
        if gitDir.ok {
            let dir = gitDir.output.trimmingCharacters(in: .whitespacesAndNewlines)
            paths += [dir + "/logs/HEAD", dir + "/index", dir + "/HEAD"]
        }
        for folder in ["", "/src", "/app", "/pages", "/lib", "/components", "/server", "/apps", "/packages"] {
            let dir = project + folder
            for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where !name.hasPrefix(".") && name != "node_modules" {
                paths.append(dir + "/" + name)
            }
        }
        return paths.compactMap { (try? fm.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }.max()
    }

    private static func hasLockfile(_ project: String) -> Bool {
        ["pnpm-lock.yaml", "package-lock.json", "yarn.lock", "bun.lockb", "bun.lock"].contains { FileManager.default.fileExists(atPath: project + "/" + $0) }
    }

    private static func short(_ path: String) -> String {
        for root in DevCaches.roots where path.hasPrefix(root + "/") { return String(path.dropFirst(root.count + 1)) }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    /// "a, b, c · 4 more"
    static func summary(_ names: [String]) -> String {
        let unique = Array(NSOrderedSet(array: names.filter { !$0.isEmpty })) as? [String] ?? names
        let shown = unique.prefix(3).joined(separator: ", ")
        return unique.count > 3 ? shown + L(" · \(unique.count - 3) daha", " · \(unique.count - 3) more") : shown
    }
}

/// The last scan, kept for the Settings page and the panel's suggestion.
@MainActor
@Observable
final class DevCleanupStore {
    static let shared = DevCleanupStore()
    private(set) var items: [CleanupItem] = []
    private(set) var scanning = false
    private(set) var scannedAt: Date?
    private(set) var cleaning: Set<CleanupItem.Kind> = []

    var total: UInt64 { items.reduce(0) { $0 + $1.size } }
    var safeTotal: UInt64 { items.filter(\.isSafe).reduce(0) { $0 + $1.size } }

    init() {
        let saved = UserDefaults.standard.double(forKey: "devCleanup.total")
        if saved > 0 { lastTotal = UInt64(saved) }
        let at = UserDefaults.standard.double(forKey: "devCleanup.at")
        if at > 0 { lastScan = Date(timeIntervalSince1970: at) }
    }

    /// From the last scan, even before this launch scanned: what the panel suggestion reads.
    private(set) var lastTotal: UInt64 = 0
    private(set) var lastScan: Date?

    func scan() {
        guard !scanning else { return }
        scanning = true
        Task {
            let found = await Task.detached(priority: .utility) { DevCleanup.scan() }.value
            items = found
            scannedAt = Date()
            scanning = false
            lastTotal = total
            lastScan = scannedAt
            UserDefaults.standard.set(Double(total), forKey: "devCleanup.total")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "devCleanup.at")
        }
    }

    /// Scans in the background when the last one is older than 12 hours (for the suggestion).
    func scanIfStale() {
        guard !scanning, lastScan.map({ Date().timeIntervalSince($0) > 12 * 3600 }) ?? true else { return }
        scan()
    }

    func clean(_ item: CleanupItem, ask: Bool = true) {
        if ask {
            let alert = NSAlert()
            alert.messageText = L("\(item.title) temizlensin mi?", "Clean \(item.title)?")
            alert.informativeText = item.explanation + (item.size > 0 ? "\n\n" + L("Yaklaşık \(Format.bytes(item.size)) boşalır.", "About \(Format.bytes(item.size)) is freed.") : "")
            alert.addButton(withTitle: L("Temizle", "Clean"))
            alert.addButton(withTitle: L("Vazgeç", "Cancel"))
            if !item.isSafe { alert.buttons.first?.hasDestructiveAction = true }
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        cleaning.insert(item.kind)
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { DevCleanup.clean(item) }.value
            cleaning.remove(item.kind)
            items.removeAll { $0.kind == item.kind }
            lastTotal = total
            UserDefaults.standard.set(Double(total), forKey: "devCleanup.total")
            Monitor.panelActions.flash(outcome.skipped == 0 ? L("\(item.title): temizlendi", "\(item.title): cleaned")
                : L("\(item.title): \(outcome.skipped) tanesi kullanımda ya da değişmiş, bırakıldı", "\(item.title): \(outcome.skipped) in use or changed, left alone"))
            if outcome.skipped > 0 { scan() }
        }
    }

    /// Everything safe, without asking (the scheduled task and "Clean the safe ones").
    func cleanSafe(notify: Bool) {
        Task {
            if items.isEmpty || scannedAt.map({ Date().timeIntervalSince($0) > 600 }) ?? true {
                items = await Task.detached(priority: .utility) { DevCleanup.scan() }.value
                scannedAt = Date()
            }
            let safe = items.filter(\.isSafe)
            guard !safe.isEmpty else { return }
            for item in safe { cleaning.insert(item.kind) }
            let freed = await Task.detached(priority: .utility) { safe.reduce(UInt64(0)) { $0 + DevCleanup.clean($1).freed } }.value
            for item in safe { cleaning.remove(item.kind) }
            items.removeAll(where: \.isSafe)
            lastTotal = total
            UserDefaults.standard.set(Double(total), forKey: "devCleanup.total")
            let message = L("Geliştirici temizliği: ~\(Format.bytes(freed)) boşaldı", "Developer clean-up: ~\(Format.bytes(freed)) freed")
            if notify { Notifier.shared.post(id: "devCleanup", title: "Nabız", body: message) } else { Monitor.panelActions.flash(message) }
        }
    }
}
