// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

/// The developer tools' rules: ports, projects, Docker, the clean-up's safety rules and the launcher's answers.
@MainActor
@Suite("Developer tools")
struct DevToolsTests {
    init() {
        Prefs.registerDefaults()
        UserDefaults.standard.set("en", forKey: Prefs.language)
    }

    // MARK: Ports

    @Test func readsPortQueries() {
        #expect(Ports.query(":3000") == 3000)
        #expect(Ports.query("port 5173") == 5173)
        #expect(Ports.query("PORT:8080") == 8080)
        #expect(Ports.query(" :54322 ") == 54322)
        #expect(Ports.query("3000") == nil)
        #expect(Ports.query(":heart") == nil)
        #expect(Ports.query(":0") == nil)
        #expect(Ports.query(":70000") == nil)
    }

    @Test func namesPortHoldersPeopleTripOver() {
        #expect(Ports.describe(process: "ControlCenter", executable: nil)?.name == "AirPlay Receiver")
        #expect(Ports.describe(process: "ControlCenter", executable: nil)?.stoppable == false)
        #expect(Ports.describe(process: "com.docker.backend", executable: nil)?.name == "Docker")
        #expect(Ports.describe(process: "x", executable: "/Applications/Docker.app/Contents/MacOS/x")?.stoppable == false)
        #expect(Ports.describe(process: "node", executable: "/opt/homebrew/bin/node") == nil)
        #expect(Ports.wellKnown(5173) == "Vite")
        #expect(Ports.wellKnown(54321) == "Supabase")
        #expect(Ports.wellKnown(12345) == nil)
    }

    @Test func findsAListeningServerAndAFreePort() throws {
        // Below the temporary range (49152+), where servers are counted.
        let start = try #require(Ports.firstFree(from: 18_765))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", String(start), "--bind", "127.0.0.1"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { process.terminate() }
        var port: UInt16?
        for _ in 0..<50 where port == nil {
            usleep(100_000)
            port = ProcInfo.listeningPorts(process.processIdentifier).first
        }
        let found = try #require(port)
        #expect(found == start)
        #expect(ProcInfo.somethingListens(on: found))
        #expect(Ports.all().contains { $0.port == found && $0.pid == process.processIdentifier })
        let free = try #require(Ports.firstFree(from: found))
        #expect(free > found)
    }

    // MARK: Projects

    @Test func readsGitStatus() {
        var project = Project(path: "/x/app")
        Projects.apply(status: """
        # branch.oid abc
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +20 -3
        1 .M N... 100644 100644 100644 a b Sources/a.swift
        ? new.txt
        """, to: &project)
        #expect(project.branch == "main")
        #expect(project.upstream == "origin/main")
        #expect(project.ahead == 20 && project.behind == 3)
        #expect(project.changes == 2)
        #expect(project.statusText == "2 changed · 20 unpushed · 3 behind")

        var detached = Project(path: "/x/b")
        Projects.apply(status: "# branch.head (detached)\n", to: &detached)
        #expect(detached.branch == nil && detached.statusText == "clean")
    }

    @Test func turnsRemotesIntoWebPagesWithoutTokens() {
        #expect(Projects.webURL("git@github.com:me/app.git")?.absoluteString == "https://github.com/me/app")
        #expect(Projects.webURL("https://github.com/me/app.git")?.absoluteString == "https://github.com/me/app")
        #expect(Projects.webURL("https://me:ghp_secret@github.com/me/app.git")?.absoluteString == "https://github.com/me/app")
        #expect(Projects.webURL("ssh://git@github.com/me/app")?.absoluteString == "https://github.com/me/app")
        #expect(Projects.webURL("/local/path") == nil)
        let config = """
        [core]
        \tbare = false
        [remote "upstream"]
        \turl = git@github.com:other/app.git
        [remote "origin"]
        \turl = git@github.com:me/app.git
        """
        #expect(Projects.remote(inConfig: config) == "git@github.com:me/app.git")
    }

    @Test func picksUsefulScriptsAndTheDevCommand() {
        #expect(Projects.usefulScripts(["lint", "postinstall", "dev", "build", "db:push"]) == ["dev", "build", "lint"])
        var project = Project(path: "/x/web")
        project.scripts = ["dev", "build"]
        project.packageManager = "pnpm"
        #expect(project.devCommand == "pnpm dev")
        project.packageManager = nil
        #expect(project.devCommand == "npm run dev")
    }

    // MARK: Docker

    @Test func readsDockerContainers() throws {
        let line = #"{"ID":"628533881b43abcdef","Image":"postgres:17","Names":"supabase_db_shop","State":"running","Status":"Up 5 hours","Ports":"0.0.0.0:54322->5432/tcp, [::]:54322->5432/tcp","Labels":"com.supabase.cli.project=shop,com.supabase.cli.workdir=/Users/a/my-app,a=b=c"}"#
        let container = try #require(Docker.parse(line))
        #expect(container.id == "628533881b43")
        #expect(container.running)
        #expect(container.ports == [54322])
        #expect(container.project == "shop")
        #expect(container.folder == "/Users/a/my-app")
        #expect(Docker.labels("a=b=c,d=e") == ["a": "b=c", "d": "e"])
        #expect(Docker.hostPorts("127.0.0.1:5432->5432/tcp, 6379/tcp, 0.0.0.0:8000-8002->8000-8002/tcp") == [5432, 8000])

        let lone = DockerContainer(id: "1", name: "redis", image: "redis", running: false, status: "Exited", ports: [], project: nil, folder: nil)
        let groups = Docker.groups([container, lone])
        #expect(groups.map(\.name) == ["shop", "redis"])
        let gone = DockerGroup(name: "x", containers: [lone], folder: "/nowhere/\(UUID())")
        #expect(gone.orphaned)
    }

    // MARK: Clean-up safety

    @Test func keepsTheNewestAndTheLastUsedRuntime() {
        let now = Date()
        let runtimes = [
            DevCleanup.Runtime(id: "a", platform: "ios", version: "27.2", build: "24B91016s", size: 8, lastUsed: nil),
            DevCleanup.Runtime(id: "b", platform: "ios", version: "27.2", build: "24B91011", size: 8, lastUsed: now.addingTimeInterval(-15 * 86_400)),
            DevCleanup.Runtime(id: "c", platform: "ios", version: "27.2", build: "24B8117", size: 8, lastUsed: now),
            DevCleanup.Runtime(id: "d", platform: "ios", version: "18.2", build: "22C150", size: 8, lastUsed: now),
        ]
        #expect(DevCleanup.extraRuntimes(runtimes).map(\.id) == ["b"])
    }

    @Test func onlyPicksSimulatorsThatWereNeverUsed() {
        #expect(DevCleanup.isNeverUsed(state: "Shutdown", lastBooted: nil, dataSize: 18 << 20))
        #expect(!DevCleanup.isNeverUsed(state: "Booted", lastBooted: nil, dataSize: 18 << 20))
        #expect(!DevCleanup.isNeverUsed(state: "Shutdown", lastBooted: "2026-01-01T00:00:00Z", dataSize: 18 << 20))
        #expect(!DevCleanup.isNeverUsed(state: "Shutdown", lastBooted: nil, dataSize: 2 << 30))
    }

    @Test func keepsTheNewestPlaywrightBrowsers() {
        let names = ["chromium-1248", "chromium-1254", "chromium_headless_shell-1248", "chromium_headless_shell-1254", "ffmpeg-1013", "webkit-2370", ".links"]
        #expect(DevCleanup.oldPlaywright(names) == ["chromium-1248", "chromium_headless_shell-1248"])
    }

    @Test func neverDeletesMainOrACheckedOutBranch() {
        let output = "main\t \t\nfeature/done\t \t\nwip\t*\t\nagent\t \t/Users/a/p/.claude/worktrees/x\nmaster\t \t\n(HEAD detached at 1a2b)\t \t\n"
        #expect(DevCleanup.deletableBranches(output, main: "main") == ["feature/done"])
    }

    @Test func readsDockerSizes() {
        #expect(DevCleanup.dockerBytes("10.48GB (84%)") == 10_480_000_000)
        #expect(DevCleanup.dockerBytes("565.2kB (1%)") == 565_200)
        #expect(DevCleanup.dockerBytes("0B") == 0)
        #expect(DevCleanup.dockerBytes("lots") == nil)
    }

    @Test func recognisesXcodeBuildFoldersOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nabiz-build-\(UUID())").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/build/Build/Intermediates.noindex", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: root + "/dist/assets", withIntermediateDirectories: true)
        #expect(DevCleanup.isXcodeBuildFolder(root + "/build"))
        #expect(!DevCleanup.isXcodeBuildFolder(root + "/dist"))
    }

    @Test func findsTheFolderAClaudeProjectStandsFor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nabiz-claude-\(UUID())").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/Developer/my-app/.claude/worktrees/x", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: root + "/my.app", withIntermediateDirectories: true)
        #expect(DevCleanup.resolveClaudeFolder("-Developer-my-app", root: root) == root + "/Developer/my-app")
        #expect(DevCleanup.resolveClaudeFolder("-Developer-my-app--claude-worktrees-x", root: root) == root + "/Developer/my-app/.claude/worktrees/x")
        #expect(DevCleanup.resolveClaudeFolder("-my-app", root: root) == root + "/my.app")
        #expect(DevCleanup.resolveClaudeFolder("-Developer-gone", root: root) == nil)
    }

    @Test func onlyCachesAreSafeUnattended() {
        let safe = CleanupItem.Kind.allCases.filter { CleanupItem(kind: $0, size: 0, targets: [], detail: "").isSafe }
        #expect(!safe.contains(.worktrees) && !safe.contains(.dockerVolumes) && !safe.contains(.claudeTranscripts)
                && !safe.contains(.mergedBranches) && !safe.contains(.nodeModules) && !safe.contains(.simRuntimes))
    }

    // MARK: Launcher answers

    @Test func decodesJWTs() throws {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjE5MDAwMDAwMDB9.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let jwt = try #require(DevUtils.jwt("Bearer " + token))
        #expect(jwt.algorithm == "HS256")
        #expect(jwt.subject == "1234567890")
        #expect(jwt.expires == Date(timeIntervalSince1970: 1_900_000_000))
        #expect(jwt.payload.contains("\"name\" : \"John Doe\""))
        #expect(DevUtils.jwt("not.a.token") == nil)
    }

    @Test func readsUnixTimes() {
        #expect(DevUtils.epoch("1732636800") == Date(timeIntervalSince1970: 1_732_636_800))
        #expect(DevUtils.epoch("1732636800123") == Date(timeIntervalSince1970: 1_732_636_800.123))
        #expect(DevUtils.epoch("12345") == nil)
        #expect(DevUtils.epoch("9999999999") == nil)
        #expect(DevUtils.iso8601(Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00Z")
    }

    @Test func hashesAndIds() {
        #expect(DevUtils.hash("abc", .md5) == "900150983cd24fb0d6963f7d28e17f72")
        #expect(DevUtils.hash("abc", .sha1) == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(DevUtils.hash("abc", .sha256) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let ulid = DevUtils.ulid(date: Date(timeIntervalSince1970: 1_469_918_176.385))
        #expect(ulid.count == 26 && ulid.hasPrefix("01ARYZ6S41"))
        #expect(DevUtils.nanoid().count == 21)
    }

    @Test func changesIdentifierCase() {
        #expect(DevUtils.words("helloWorld_fooBar-baz 42x") == ["hello", "world", "foo", "bar", "baz", "42x"])
        #expect(DevUtils.convert("hello world", to: .camel) == "helloWorld")
        #expect(DevUtils.convert("HelloWorld", to: .snake) == "hello_world")
        #expect(DevUtils.convert("hello_world", to: .kebab) == "hello-world")
        #expect(DevUtils.convert("hello-world", to: .pascal) == "HelloWorld")
        #expect(DevUtils.convert("helloWorld", to: .constant) == "HELLO_WORLD")
    }

    @Test func convertsColours() throws {
        let green = try #require(DevUtils.color("#1db954"))
        #expect(green == DevUtils.RGB(red: 29, green: 185, blue: 84))
        #expect(DevUtils.color("#fff") == DevUtils.RGB(red: 255, green: 255, blue: 255))
        #expect(DevUtils.color("rgb(29, 185, 84)") == green)
        #expect(DevUtils.color("rgba(0,0,0,0.5)")?.alpha == 0.5)
        #expect(DevUtils.color("1db954") == nil)
        let formats = Dictionary(uniqueKeysWithValues: DevUtils.formats(green).map { ($0.title, $0.value) })
        #expect(formats["HEX"] == "#1DB954")
        #expect(formats["HSL"] == "hsl(141, 73%, 42%)")
        #expect(formats["SwiftUI"] == "Color(red: 0.114, green: 0.725, blue: 0.329)")
        #expect(formats["Compose"] == "Color(0xFF1DB954)")
    }

    @Test func explainsCron() {
        #expect(DevUtils.cron("*/5 * * * *") == "Every 5 minutes")
        #expect(DevUtils.cron("0 9 * * 1-5") == "At 09:00, on weekdays")
        #expect(DevUtils.cron("30 3 1 * *") == "At 03:30, on day 1 of the month")
        #expect(DevUtils.cron("0 * * * *") == "Every hour at minute 0")
        #expect(DevUtils.cron("0 9 1 1 1") == nil)
        #expect(DevUtils.cron("hello world foo bar baz") == nil)
    }

    @Test func knowsHTTPCodes() {
        #expect(DevUtils.httpStatus(429) == "Too Many Requests")
        #expect(DevUtils.httpStatus(299) == nil)
    }

    @Test func launcherAnswersDeveloperQueries() {
        let model = LauncherModel()
        #expect(model.devSections("#1db954").first?.id == "color")
        #expect(model.devSections("1732636800").first?.id == "epoch")
        #expect(model.devSections("sha256 abc").first?.items.first?.title == DevUtils.hash("abc", .sha256))
        #expect(model.devSections("http 404").first?.items.first?.title == "404 Not Found")
        #expect(model.devSections("hello").isEmpty)
    }

    // MARK: Notarization and simulators

    @Test func readsNotaryHistory() {
        let json = #"{"history":[{"createdDate":"2026-11-26T10:00:00Z","id":"1","name":"Nabiz.zip","status":"Accepted"},{"id":"0","name":"old.zip","status":"Invalid"}],"message":"ok"}"#
        let latest = NotaryWatch.parseHistory(json)
        #expect(latest?.status == "Accepted" && latest?.name == "Nabiz.zip")
        #expect(NotaryWatch.value(after: "--keychain-profile", in: ["notarytool", "submit", "a.zip", "--keychain-profile", "nabiz", "--wait"]) == "nabiz")
    }

    @Test func listsOnlyTheUsersOwnSimulatorApps() {
        let apps = SimTools.parseApps([
            "com.example.beta": ["ApplicationType": "User", "CFBundleDisplayName": "Beta"],
            "com.apple.mobilesafari": ["ApplicationType": "System", "CFBundleDisplayName": "Safari"],
            "com.me.a": ["ApplicationType": "User", "CFBundleName": "Alpha"],
        ])
        #expect(apps.map(\.name) == ["Alpha", "Beta"])
    }

    @Test func cleanUpLeavesWhatCannotComeBack() throws {
        // A worktree keeps its .env or a local database; only rebuildable leftovers may be ignored.
        #expect(DevCleanup.onlyRegenerable(""))
        #expect(DevCleanup.onlyRegenerable("!! node_modules/\n!! apps/web/.next/\n!! .DS_Store"))
        #expect(!DevCleanup.onlyRegenerable("!! .env"))
        #expect(!DevCleanup.onlyRegenerable("!! node_modules/\n!! dev.sqlite"))
        #expect(!DevCleanup.onlyRegenerable("?? notes.md"))
        #expect(!DevCleanup.onlyRegenerable(" M Sources/App.swift"))
        // Only agents' worktrees; a person's hotfix worktree is theirs.
        #expect(DevCleanup.isAgentWorktree("/Users/me/Developer/app/.claude/worktrees/fix-1"))
        #expect(!DevCleanup.isAgentWorktree("/Users/me/Developer/app-hotfix"))
        // A project folder holding a build: only the build parts go.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nabiz-build-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: folder) }
        for sub in ["Build/Intermediates.noindex", "Logs/Build", "Sources"] {
            try FileManager.default.createDirectory(atPath: folder + "/" + sub, withIntermediateDirectories: true)
        }
        #expect(DevCleanup.isXcodeBuildFolder(folder))
        #expect(Set(DevCleanup.buildParts(of: folder).map { ($0 as NSString).lastPathComponent }) == ["Build", "Logs"])
    }
}
