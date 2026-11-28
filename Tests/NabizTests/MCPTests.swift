// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

/// The MCP protocol layer, without a socket.
@MainActor
@Suite("MCP")
struct MCPTests {
    init() {
        Prefs.registerDefaults()
        UserDefaults.standard.set("en", forKey: Prefs.language)
    }

    private func call(_ object: [String: Any]) async -> [String: Any]? {
        let data = try! JSONSerialization.data(withJSONObject: object)
        guard let reply = await MCPProtocol.handle(data) else { return nil }
        return try? JSONSerialization.jsonObject(with: reply) as? [String: Any]
    }

    @Test func initializeAnswersWithToolsCapability() async {
        let reply = await call(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                "params": ["protocolVersion": "2025-06-18", "clientInfo": ["name": "test", "version": "1"]]])
        let result = reply?["result"] as? [String: Any]
        #expect(result?["protocolVersion"] as? String == "2025-06-18")
        #expect((result?["capabilities"] as? [String: Any])?["tools"] != nil)
        #expect((result?["serverInfo"] as? [String: Any])?["name"] as? String == "nabiz")
    }

    @Test func unknownVersionFallsBackToLatest() async {
        let reply = await call(["jsonrpc": "2.0", "id": "a", "method": "initialize", "params": ["protocolVersion": "1999-01-01"]])
        #expect((reply?["result"] as? [String: Any])?["protocolVersion"] as? String == MCPProtocol.versions[0])
        #expect(reply?["id"] as? String == "a")
    }

    @Test func notificationsGetNoReply() async {
        #expect(await call(["jsonrpc": "2.0", "method": "notifications/initialized"]) == nil)
    }

    @Test func toolsFollowSettings() async {
        UserDefaults.standard.set(false, forKey: Prefs.mcpClipboard)
        UserDefaults.standard.set(true, forKey: Prefs.mcpNotes)
        let reply = await call(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let tools = ((reply?["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        let names = tools.compactMap { $0["name"] as? String }
        #expect(names.contains("system_status"))
        #expect(names.contains("notes_search"))
        #expect(!names.contains("clipboard_history"))
        #expect(tools.allSatisfy { ($0["inputSchema"] as? [String: Any])?["type"] as? String == "object" })
    }

    @Test func calculateTool() async {
        let reply = await call(["jsonrpc": "2.0", "id": 3, "method": "tools/call",
                                "params": ["name": "calculate", "arguments": ["expression": "12*4"]]])
        let result = reply?["result"] as? [String: Any]
        let text = ((result?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        #expect(result?["isError"] as? Bool == false)
        #expect(text.contains("48"))
    }

    @Test func toolErrorsAreResultsAndUnknownToolsAreProtocolErrors() async {
        let missing = await call(["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "calculate", "arguments": [:]]])
        #expect((missing?["result"] as? [String: Any])?["isError"] as? Bool == true)
        let unknown = await call(["jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": ["name": "nope"]])
        #expect((unknown?["error"] as? [String: Any])?["code"] as? Int == -32602)
        let method = await call(["jsonrpc": "2.0", "id": 6, "method": "nope"])
        #expect((method?["error"] as? [String: Any])?["code"] as? Int == -32601)
    }

    @Test func unsafeCommandsAreRefused() async {
        UserDefaults.standard.set(true, forKey: Prefs.mcpCommands)
        let reply = await call(["jsonrpc": "2.0", "id": 7, "method": "tools/call",
                                "params": ["name": "run_command", "arguments": ["id": "sys:shutDown"]]])
        #expect((reply?["result"] as? [String: Any])?["isError"] as? Bool == true)
    }

    @Test func toolListCanChange() async {
        let reply = await call(["jsonrpc": "2.0", "id": 8, "method": "initialize", "params": [:]])
        let tools = ((reply?["result"] as? [String: Any])?["capabilities"] as? [String: Any])?["tools"] as? [String: Any]
        #expect(tools?["listChanged"] as? Bool == true)
    }

    @Test func turnedOffToolsSaySo() async {
        UserDefaults.standard.set(false, forKey: Prefs.mcpClipboardNow)
        let reply = await call(["jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": ["name": "clipboard_read"]])
        let result = reply?["result"] as? [String: Any]
        let text = ((result?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        #expect(reply?["error"] == nil)
        #expect(result?["isError"] as? Bool == true)
        #expect(text.contains("turned off in Settings → MCP"))
    }

    @Test func pingIsAnsweredWithoutWaiting() throws {
        let ping = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 10, "method": "ping"])
        let reply = MCPProtocol.quickReply(ping).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(reply?["id"] as? Int == 10 && reply?["result"] != nil)
        let other = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 11, "method": "tools/list"])
        #expect(MCPProtocol.quickReply(other) == nil)
    }

    @Test func annotationsSayWhatToolsDo() {
        let tools = Dictionary(uniqueKeysWithValues: MCPTools.all.map { ($0.name, $0.descriptor["annotations"] as? [String: Any] ?? [:]) })
        for name in ["stop_dev_server", "run_command", "focus_mode", "set_volume", "open_app", "place_window", "recording_edit"] {
            #expect(tools[name]?["destructiveHint"] as? Bool == true, "\(name)")
            #expect(tools[name]?["readOnlyHint"] as? Bool == false, "\(name)")
        }
        for name in ["system_status", "window_list", "screenshot", "clipboard_read", "dev_server_logs", "recording_frame"] {
            #expect(tools[name]?["readOnlyHint"] as? Bool == true, "\(name)")
            #expect(tools[name]?["destructiveHint"] as? Bool == false, "\(name)")
        }
        #expect(tools["market_prices"]?["openWorldHint"] as? Bool == true)
    }

    @Test func imagesComeBackAsImageContent() {
        let result = MCPProtocol.toolResult([.image(Data([1, 2, 3]), mimeType: "image/png"), .text("/tmp/a.png")], isError: false)
        let content = result["content"] as? [[String: Any]] ?? []
        #expect(content.first?["type"] as? String == "image")
        #expect(content.first?["data"] as? String == Data([1, 2, 3]).base64EncodedString())
        #expect(content.first?["mimeType"] as? String == "image/png")
        #expect(content.last?["text"] as? String == "/tmp/a.png")
    }

    @Test func commandsAreAllowedByList() {
        #expect(MCPTools.access("win:leftHalf") == .allowed)
        #expect(MCPTools.access("cmd:timer-5") == .allowed)
        #expect(MCPTools.access("script:/Users/x/a.sh") == .scripts)
        #expect(MCPTools.access("shortcut:Morning") == .scripts)
        #expect(MCPTools.access("sys:sleep") == .scripts && MCPTools.access("sys:lock") == .scripts)
        #expect(MCPTools.access("sys:emptyTrash") == .never && MCPTools.access("sys:shutDown") == .never)
        // Something added later stays out until it's listed.
        #expect(MCPTools.access("sys:somethingNew") == .never && MCPTools.access("tool:cleanup") == .never)
        UserDefaults.standard.set(false, forKey: Prefs.mcpScripts)
        #expect(!MCPTools.mayRun("shortcut:Morning"))
        UserDefaults.standard.set(true, forKey: Prefs.mcpScripts)
        #expect(MCPTools.mayRun("shortcut:Morning"))
        UserDefaults.standard.set(false, forKey: Prefs.mcpScripts)
    }

    @Test func findsMeetingLinks() {
        #expect(CalendarAgenda.meetingURL(nil, "Room 4", "Join: https://us02web.zoom.us/j/123?pwd=x")?.host() == "us02web.zoom.us")
        #expect(CalendarAgenda.meetingURL(URL(string: "https://meet.google.com/abc-defg-hij"), nil, nil) != nil)
        #expect(CalendarAgenda.meetingURL(nil, "https://example.com", "nothing") == nil)
    }
}
