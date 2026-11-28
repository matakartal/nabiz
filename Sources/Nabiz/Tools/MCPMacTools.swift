// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Darwin
import ScreenCaptureKit

/// Seeing and arranging the Mac for an AI app: a screenshot, the windows on screen and where they go, a dev server's
/// output, and what's on the clipboard now. Each follows its own switch in Settings → MCP.
@MainActor
extension MCPTools {
    static var macTools: [MCPTool] {
        [
            MCPTool(name: "screenshot", title: "Take a screenshot",
                    description: "A picture of the whole main screen, or of one app's front window (app). Needs macOS's Screen Recording permission for Nabız. Nothing is saved; the picture comes back to you.",
                    group: .screen,
                    properties: ["app": ["type": "string", "description": "An app's name; leave out for the whole screen"],
                                 "width": ["type": "integer", "description": "Longest side in pixels, default 1600", "minimum": 320, "maximum": 3840]],
                    content: { args in
                let png = try await screenshot(app: args["app"] as? String, width: int(args["width"]) ?? 1600)
                return [.image(png, mimeType: "image/png")]
            }),
            MCPTool(name: "window_list", title: "List windows",
                    description: "The windows on screen, front to back: app, title (when macOS shares it), position and size in points from the top-left of the main screen.",
                    group: .commands) { _ in windowList() },
            MCPTool(name: "place_window", title: "Place a window",
                    description: """
                    Moves and sizes a window, with Nabız's window layouts. position: leftHalf, rightHalf, topHalf, bottomHalf, \
                    maximize, almostMaximize, center, leftThird, centerThird, rightThird, nextDisplay; or x, y, width, height as \
                    percent of the screen from the top-left. app: whose window (it comes to the front); leave out for the window in front.
                    """,
                    group: .commands, readOnly: false, destructive: true,
                    properties: ["app": ["type": "string"],
                                 "position": ["type": "string", "enum": WindowAction.allCases.map(\.rawValue)],
                                 "x": ["type": "integer", "minimum": 0, "maximum": 100], "y": ["type": "integer", "minimum": 0, "maximum": 100],
                                 "width": ["type": "integer", "minimum": 1, "maximum": 100], "height": ["type": "integer", "minimum": 1, "maximum": 100]]) { args in
                try await placeWindow(args)
            },
            MCPTool(name: "dev_server_logs", title: "A dev server's output",
                    description: "The newest output of a dev server from dev_servers (by port or pid), when it writes to a log file Nabız can read. A server started in a terminal writes to that terminal instead, which nothing else can read; then this says so.",
                    group: .basic,
                    properties: ["port": ["type": "integer", "minimum": 1, "maximum": 65535], "pid": ["type": "integer"],
                                 "lines": ["type": "integer", "description": "Default 100", "minimum": 1, "maximum": 1000]]) { args in
                try await devServerLogs(args)
            },
            MCPTool(name: "clipboard_read", title: "Read the clipboard",
                    description: "The text on the Mac's clipboard right now (not the history). Items password managers mark as secret are never given.",
                    group: .clipboardNow) { _ in try clipboardNow() },
        ]
    }

    // MARK: Screenshot

    private static func screenshot(app: String?, width: Int) async throws -> Data {
        guard CGPreflightScreenCaptureAccess() else {
            throw MCPToolError("Nabız doesn't have the Screen Recording permission. The user can allow it in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen Nabız.")
        }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw MCPToolError("macOS didn't allow the screenshot: \(error.localizedDescription)")
        }
        let filter: SCContentFilter
        var size: CGSize
        if let app, !app.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let (_, frame, number) = frontWindow(of: app),
                  let window = content.windows.first(where: { $0.windowID == number }) else {
                throw MCPToolError("No window of \(app) is on screen. Call window_list for what is.")
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            size = frame.size
        } else {
            guard let screen = NSScreen.screens.first,
                  let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == number }) else {
                throw MCPToolError("Couldn't find the screen.")
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
            size = screen.frame.size
        }
        let scale = min(CGFloat(min(max(width, 320), 3840)) / max(size.width, size.height, 1), 2)
        size = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let config = SCStreamConfiguration()
        config.width = max(Int(size.width), 1)
        config.height = max(Int(size.height), 1)
        config.showsCursor = false
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw MCPToolError("The screenshot failed: \(error.localizedDescription)")
        }
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw MCPToolError("Couldn't make the picture.")
        }
        return png
    }

    // MARK: Windows

    private static func windowList() -> String {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let own = ProcessInfo.processInfo.processIdentifier
        return json(list.compactMap { info -> [String: Any]? in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let owner = info[kCGWindowOwnerName as String] as? String,
                  (info[kCGWindowOwnerPID as String] as? Int).map({ pid_t($0) != own }) ?? true,
                  let boundsInfo = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary), bounds.width > 40, bounds.height > 40
            else { return nil }
            var item: [String: Any] = ["app": owner, "x": Int(bounds.minX), "y": Int(bounds.minY),
                                       "width": Int(bounds.width), "height": Int(bounds.height)]
            if let title = info[kCGWindowName as String] as? String, !title.isEmpty { item["title"] = title }
            return item
        })
    }

    private static func placeWindow(_ args: [String: Any]) async throws -> String {
        guard Paster.isTrusted else {
            throw MCPToolError("Nabız needs the Accessibility permission to move windows. The user can allow it in System Settings → Privacy & Security → Accessibility.")
        }
        var bundle: String?
        var appName = "the window in front"
        if let name = args["app"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            let wanted = name.lowercased()
            let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            guard let app = apps.first(where: { $0.localizedName?.lowercased() == wanted })
                    ?? apps.first(where: { $0.localizedName?.lowercased().contains(wanted) == true }) else {
                throw MCPToolError("\(name) isn't running. Open it with open_app first.")
            }
            bundle = app.bundleIdentifier
            appName = app.localizedName ?? name
            app.activate()
            // Let it come to the front before its window is moved.
            try? await Task.sleep(for: .milliseconds(300))
        }
        if let raw = args["position"] as? String {
            guard let action = WindowAction(rawValue: raw) else { throw MCPToolError("Unknown position \(raw).") }
            action.run()
            return "Placed \(appName): \(action.rawValue)."
        }
        guard let x = int(args["x"]), let y = int(args["y"]), let width = int(args["width"]), let height = int(args["height"]) else {
            throw MCPToolError("Give a position, or x, y, width and height in percent.")
        }
        WindowLayouts.shared.apply(WindowLayout(name: "MCP", x: x, y: y, width: width, height: height, app: bundle))
        return "Placed \(appName) at \(x)%, \(y)%, \(width)% × \(height)%."
    }

    // MARK: Dev server output

    private static func devServerLogs(_ args: [String: Any]) async throws -> String {
        let port = int(args["port"]), pid = int(args["pid"])
        guard port != nil || pid != nil else { throw MCPToolError("Give the server's port or pid.") }
        let lines = min(max(int(args["lines"]) ?? 100, 1), 1000)
        let servers = await Task.detached(priority: .userInitiated) { DevServers.running() }.value
        guard let server = servers.first(where: { s in pid.map { Int(s.pid) == $0 } ?? s.ports.contains { Int($0) == port } }) else {
            throw MCPToolError("No dev server there. Call dev_servers for the list.")
        }
        let found = await Task.detached(priority: .userInitiated) { () -> (String, String)? in
            for fd in [Int32(1), 2] {
                guard let path = outputFile(pid: server.pid, fd: fd), let text = tail(path, lines: lines) else { continue }
                return (path, text)
            }
            return nil
        }.value
        guard let (path, text) = found else {
            return "\(server.tool) in \(server.projectName) writes to the terminal it was started in, which Nabız can't read. "
                + "To see its output here, start it with its output going to a file (for example: npm run dev > dev.log 2>&1)."
        }
        return "From \(path):\n\n\(text)"
    }

    /// Where a process's stdout (1) or stderr (2) goes, when that's a plain file.
    nonisolated static func outputFile(pid: pid_t, fd: Int32) -> String? {
        var info = vnode_fdinfowithpath()
        let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
        guard proc_pidfdinfo(pid, fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvip.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        var status = stat()
        guard !path.isEmpty, !path.hasPrefix("/dev/"), stat(path, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else { return nil }
        return path
    }

    /// The last lines of a file, reading at most its last 256 KB.
    nonisolated static func tail(_ path: String, lines: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: end > 262_144 ? end - 262_144 : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        // Colour codes are noise to an AI.
        let plain = text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        let kept = plain.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
        return kept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(empty so far)" : kept
    }

    // MARK: Clipboard

    private static func clipboardNow() throws -> String {
        let board = NSPasteboard.general
        let marks = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]
        if board.types?.contains(where: { marks.contains($0.rawValue) }) == true {
            throw MCPToolError("What's on the clipboard is marked secret (from a password manager), so it isn't shared.")
        }
        guard let text = board.string(forType: .string), !text.isEmpty else {
            if let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
                return files.map(\.path).joined(separator: "\n")
            }
            return "The clipboard holds no text."
        }
        return String(text.prefix(20_000))
    }
}
