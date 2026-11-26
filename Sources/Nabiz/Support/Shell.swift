// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Foundation

/// Runs developer tools (git, xcrun, docker, brew) with the login shell's PATH, off the main actor.
enum Shell {
    struct Result: Sendable {
        let status: Int32
        let output: String
        var ok: Bool { status == 0 }
    }

    /// The login shell's PATH (Homebrew, ~/.local, npm globals live there, not in an app's PATH). Read once.
    static let path: String = {
        let fallback = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(NSHomeDirectory())/.local/bin"
        let found = run("/bin/zsh", ["-lc", "print -r -- $PATH"], usePath: false, timeout: 5)
        let login = found.ok ? found.output.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return login.isEmpty ? fallback : login + ":" + fallback
    }()

    /// The full path of a command on the login PATH, or nil when it isn't installed.
    static func which(_ command: String) -> String? {
        if command.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: command) ? command : nil }
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(command)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Blocking. `executable` is a path or a command name on the login PATH. Stops it after `timeout` seconds.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String], in folder: String? = nil, usePath: Bool = true,
                    timeout: TimeInterval = 30, stderr: Bool = false) -> Result {
        let resolved = executable.hasPrefix("/") ? executable : (which(executable) ?? "/usr/bin/env")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = resolved == "/usr/bin/env" ? [executable] + arguments : arguments
        if let folder { process.currentDirectoryURL = URL(fileURLWithPath: folder) }
        var environment = ProcessInfo.processInfo.environment
        if usePath { environment["PATH"] = path }
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = stderr ? pipe : FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return Result(status: -1, output: "") }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// Async form for the main actor.
    static func runAsync(_ executable: String, _ arguments: [String], in folder: String? = nil, timeout: TimeInterval = 30,
                         stderr: Bool = false) async -> Result {
        await Task.detached(priority: .userInitiated) { run(executable, arguments, in: folder, timeout: timeout, stderr: stderr) }.value
    }

    /// Single-quoted for zsh.
    static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

/// Opens Terminal in a folder, optionally running a command there, without asking for Automation permission:
/// a small `.command` file that Terminal runs and then leaves a shell open.
@MainActor
enum TerminalLauncher {
    static func open(_ folder: String, run command: String? = nil, title: String? = nil) {
        guard let command else {
            NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: terminalURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NabizTerminal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(UUID().uuidString.prefix(8)).command")
        var script = "#!/bin/zsh -l\n"
        if let title { script += "printf '\\e]0;%s\\a' \(Shell.quote(title))\n" }
        script += "cd \(Shell.quote(folder)) || exit 1\nrm -f \(Shell.quote(file.path))\n\(command)\nexec zsh -l\n"
        guard (try? script.write(to: file, atomically: true, encoding: .utf8)) != nil else { return }
        chmod(file.path, 0o700)
        NSWorkspace.shared.open([file], withApplicationAt: terminalURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private static var terminalURL: URL {
        // Terminal runs a .command file as a script; other terminals open it as text.
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
    }
}
