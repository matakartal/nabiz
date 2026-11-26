// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import Darwin

/// Lets AI apps (Claude Code, Claude Desktop, Cursor…) use Nabız through the Model Context Protocol.
///
/// The app listens on a Unix socket that only this user can open. AI apps start `Nabiz --mcp`, a small bridge that
/// passes their stdin and stdout to that socket, so every tool runs inside the app with its live data and permissions.
/// Nothing listens while MCP is off in Settings.
enum MCPSocket {
    static var path: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Nabiz/mcp.sock").path
    }

    /// A connected socket, or -1.
    nonisolated static func connect() -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        guard var address = address(path) else { close(fd); return -1 }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { close(fd); return -1 }
        noSigPipe(fd)
        return fd
    }

    nonisolated static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }

    /// Writing to a closed socket must fail, not kill the process.
    nonisolated static func noSigPipe(_ fd: Int32) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Writes every byte, retrying after interruptions; false once the other side is gone.
    @discardableResult
    nonisolated static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return true }
            var left = raw.count
            while left > 0 {
                let written = write(fd, pointer, left)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                left -= written
                pointer = pointer.advanced(by: written)
            }
            return true
        }
    }
}

// MARK: Server (inside the app)

@MainActor
@Observable
final class MCPServer {
    static let shared = MCPServer()

    private(set) var running = false
    /// The last AI app that connected ("claude-code", "claude-ai"…), and the last tool it used.
    private(set) var lastClient: String?
    private(set) var lastCall: (tool: String, at: Date)?
    @ObservationIgnored private var source: DispatchSourceRead?

    /// Starts or stops with the setting.
    func update() {
        if Prefs.bool(Prefs.mcpEnabled) { start() } else { stop() }
    }

    func start() {
        guard source == nil else { return }
        let path = MCPSocket.path
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var address = MCPSocket.address(path) else { return }
        // Only this user may open it.
        let mask = umask(0o077)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(mask)
        guard bound == 0, Darwin.listen(fd, 8) == 0 else { close(fd); return }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        source = Self.makeListener(fd, path: path)
        running = true
    }

    func stop() {
        source?.cancel()
        source = nil
        running = false
    }

    func noteClient(_ name: String) { lastClient = name }
    func noteCall(_ tool: String) { lastCall = (tool, Date()) }

    nonisolated private static func makeListener(_ fd: Int32, path: String) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "nabiz.mcp.accept"))
        source.setEventHandler {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                MCPConnection(fd: client).start()
            }
        }
        source.setCancelHandler {
            close(fd)
            unlink(path)
        }
        source.resume()
        return source
    }
}

/// One AI app's session: newline-separated JSON-RPC in both directions.
final class MCPConnection: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var closed = false

    init(fd: Int32) { self.fd = fd }

    func start() {
        MCPSocket.noSigPipe(fd)
        // Blocking reads on its own thread; the listening socket is non-blocking, this one isn't.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        Thread.detachNewThread { self.readLoop() }
    }

    private func readLoop() {
        // Only processes of this same user.
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { finish(); return }
        // Requests are answered one after another, in order; the socket closes only after the last answer went out.
        let (lines, input) = AsyncStream<Data>.makeStream()
        Task { @MainActor in
            for await line in lines {
                if let reply = await MCPProtocol.handle(line) { self.send(reply) }
            }
            self.finish()
        }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { break }
            buffer.append(contentsOf: chunk[0..<count])
            // A runaway message without a newline: give up on this client.
            if buffer.count > 8 << 20 { break }
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
                guard !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D }) else { continue }
                input.yield(line)
            }
        }
        input.finish()
    }

    private func send(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        MCPSocket.writeAll(fd, data + Data([0x0A]))
    }

    private func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        close(fd)
    }
}

// MARK: Protocol

@MainActor
enum MCPProtocol {
    static let versions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    static func handle(_ data: Data) async -> Data? {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        // Notifications (no id) and the client's own answers need no reply.
        guard let method = message["method"] as? String, let id = message["id"], !(id is NSNull) else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        let result: Any
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? versions[0]
            if let client = (params["clientInfo"] as? [String: Any])?["name"] as? String { MCPServer.shared.noteClient(client) }
            result = [
                "protocolVersion": versions.contains(asked) ? asked : versions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "nabiz", "title": "Nabız", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"],
                "instructions": """
                Nabız is the user's macOS menu bar app. Use it to read this Mac's live state (CPU, memory, disk, battery, \
                the busiest apps), the user's AI subscription limits, calendar, markets and exchange rates, their notes and \
                snippets, and to act on the Mac: open apps, place windows, set the volume, start timers or focus mode, \
                and post a notification when a long task is done.
                """,
            ] as [String: Any]
        case "ping":
            result = [String: Any]()
        case "tools/list":
            result = ["tools": MCPTools.available.map(\.descriptor)]
        case "tools/call":
            guard let name = params["name"] as? String, let tool = MCPTools.available.first(where: { $0.name == name }) else {
                return error(id, -32602, "Unknown tool: \(params["name"] as? String ?? "")")
            }
            MCPServer.shared.noteCall(name)
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try await tool.run(arguments)
                result = ["content": [["type": "text", "text": text]], "isError": false] as [String: Any]
            } catch {
                let message = (error as? MCPToolError)?.message ?? error.localizedDescription
                result = ["content": [["type": "text", "text": message]], "isError": true] as [String: Any]
            }
        case "resources/list":
            result = ["resources": [Any]()]
        case "prompts/list":
            result = ["prompts": [Any]()]
        default:
            return error(id, -32601, "Method not found: \(method)")
        }
        return encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func error(_ id: Any, _ code: Int, _ message: String) -> Data? {
        encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    static func encode(_ object: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }
}

// MARK: Bridge (`Nabiz --mcp`, started by the AI app)

enum MCPBridge {
    /// Connects stdin/stdout to the running app, starting it first if needed. Never returns.
    nonisolated static func run() -> Never {
        signal(SIGPIPE, SIG_IGN)
        var fd = MCPSocket.connect()
        if fd < 0 {
            let bundleID = Bundle.main.bundleIdentifier ?? "app.nabiz.menubar"
            let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
            if !isRunning {
                // In the background, without taking focus from the AI app.
                let open = Process()
                open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                open.arguments = Bundle.main.bundlePath.hasSuffix(".app") ? ["-g", Bundle.main.bundlePath] : ["-g", "-b", bundleID]
                try? open.run()
            }
            // Give a starting app up to 15 s; a running one with MCP off won't open the socket at all.
            let tries = isRunning ? 4 : 60
            for _ in 0..<tries {
                usleep(250_000)
                fd = MCPSocket.connect()
                if fd >= 0 { break }
            }
        }
        guard fd >= 0 else {
            FileHandle.standardError.write(Data("Nabız MCP is off. Turn it on in Nabız → Settings → MCP.\n".utf8))
            exit(1)
        }
        let socket = fd
        // App → AI app.
        Thread.detachNewThread {
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = read(socket, &chunk, chunk.count)
                if count < 0 && errno == EINTR { continue }
                guard count > 0, MCPSocket.writeAll(STDOUT_FILENO, Data(chunk[0..<count])) else { exit(0) }
            }
        }
        // AI app → app; when the AI app closes stdin, the session is over.
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(STDIN_FILENO, &chunk, chunk.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0, MCPSocket.writeAll(socket, Data(chunk[0..<count])) else { break }
        }
        shutdown(socket, SHUT_WR)
        // The app closes the socket once the last answer is out, which ends the reading thread and the process.
        sleep(30)
        exit(0)
    }
}

// MARK: Setup for AI apps

@MainActor
enum MCPSetup {
    /// The command an AI app runs.
    static var command: String { Bundle.main.executablePath ?? "/Applications/Nabiz.app/Contents/MacOS/Nabiz" }

    static var claudeCodeCommand: String { "claude mcp add --scope user nabiz -- \"\(command)\" --mcp" }

    static var desktopJSON: String {
        let object: [String: Any] = ["mcpServers": ["nabiz": ["command": command, "args": ["--mcp"]]]]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The `claude` CLI, where its installers put it.
    static var claudeCLI: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                "\(home)/.npm-global/bin/claude", "\(home)/.bun/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Registers Nabız with Claude Code for every project (`claude mcp add --scope user`).
    static func addToClaudeCode() async -> String {
        guard let cli = claudeCLI else {
            return L("Claude Code bulunamadı. Komutu kopyalayıp Terminal'de çalıştır.", "Claude Code wasn't found. Copy the command and run it in Terminal.")
        }
        let command = command
        let result = await Task.detached(priority: .userInitiated) { () -> (Int32, String) in
            let remove = Process()
            remove.executableURL = URL(fileURLWithPath: cli)
            remove.arguments = ["mcp", "remove", "--scope", "user", "nabiz"]
            remove.standardOutput = FileHandle.nullDevice
            remove.standardError = FileHandle.nullDevice
            try? remove.run()
            remove.waitUntilExit()
            let add = Process()
            add.executableURL = URL(fileURLWithPath: cli)
            add.arguments = ["mcp", "add", "--scope", "user", "nabiz", "--", command, "--mcp"]
            let pipe = Pipe()
            add.standardOutput = pipe
            add.standardError = pipe
            do { try add.run() } catch { return (1, error.localizedDescription) }
            add.waitUntilExit()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return (add.terminationStatus, output)
        }.value
        return result.0 == 0
            ? L("Claude Code'a eklendi. Yeni bir Claude Code oturumunda Nabız araçları hazır.", "Added to Claude Code. Nabız's tools are ready in a new Claude Code session.")
            : L("Eklenemedi: ", "Couldn't add it: ") + result.1.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Adds Nabız to Claude Desktop's config, keeping everything else (and a backup of the old file).
    static func addToClaudeDesktop() -> String {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude")
        let file = folder.appendingPathComponent("claude_desktop_config.json")
        guard FileManager.default.fileExists(atPath: folder.path) else {
            return L("Claude Desktop kurulu görünmüyor.", "Claude Desktop doesn't seem to be installed.")
        }
        var config: [String: Any] = [:]
        if let data = try? Data(contentsOf: file), !data.isEmpty {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return L("Claude Desktop ayar dosyası okunamadı; JSON'u kopyalayıp elle ekle.", "Claude Desktop's config couldn't be read; copy the JSON and add it by hand.")
            }
            config = parsed
            try? data.write(to: folder.appendingPathComponent("claude_desktop_config.json.nabiz-backup"))
        }
        var servers = config["mcpServers"] as? [String: Any] ?? [:]
        servers["nabiz"] = ["command": command, "args": ["--mcp"]]
        config["mcpServers"] = servers
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]),
              (try? data.write(to: file, options: .atomic)) != nil else {
            return L("Yazılamadı.", "Couldn't write it.")
        }
        return L("Claude Desktop'a eklendi. Claude Desktop'tan çıkıp yeniden aç.", "Added to Claude Desktop. Quit and reopen Claude Desktop.")
    }
}
