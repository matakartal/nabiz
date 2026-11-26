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

    @Test func findsMeetingLinks() {
        #expect(CalendarAgenda.meetingURL(nil, "Room 4", "Join: https://us02web.zoom.us/j/123?pwd=x")?.host() == "us02web.zoom.us")
        #expect(CalendarAgenda.meetingURL(URL(string: "https://meet.google.com/abc-defg-hij"), nil, nil) != nil)
        #expect(CalendarAgenda.meetingURL(nil, "https://example.com", "nothing") == nil)
    }
}
