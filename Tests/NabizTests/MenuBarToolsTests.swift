import Foundation
import Testing
@testable import Nabiz

/// Dev servers, display brightness over DDC and the rules behind them. The hardware parts (a listening server, an
/// external display) are checked in the app; here the naming, filtering and DDC bytes.
@Suite("Dev servers and brightness")
struct MenuBarToolsTests {
    // MARK: Dev servers

    @Test func namesServersTheWayPeopleDo() {
        #expect(DevServers.toolName(["node", "/Users/a/p/node_modules/.bin/vite", "--port", "5173"], fallback: "node") == "vite")
        #expect(DevServers.toolName(["node", "/Users/a/p/node_modules/.pnpm/next@15.1.0/node_modules/next/dist/bin/next", "dev"], fallback: "node") == "next")
        #expect(DevServers.toolName(["node", "/Users/a/p/node_modules/@astrojs/cli/bin.js"], fallback: "node") == "@astrojs/cli")
        #expect(DevServers.toolName(["next-server (v15.1.0)"], fallback: "node") == "next-server")
        #expect(DevServers.toolName(["/usr/bin/python3", "-m", "http.server", "8000"], fallback: "Python") == "http.server")
        #expect(DevServers.toolName(["/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python",
                                     "-m", "http.server", "8765"], fallback: "Python") == "http.server")
        #expect(DevServers.toolName(["python3.12", "manage.py", "runserver"], fallback: "Python") == "manage")
        #expect(DevServers.toolName(["/opt/homebrew/bin/node", "server.mjs"], fallback: "node") == "server")
        #expect(DevServers.toolName(["/Users/a/p/target/debug/sc-api"], fallback: "sc-api") == "sc-api")
        #expect(DevServers.toolName([], fallback: "ruby") == "ruby")
    }

    @Test func onlyRealServerPortsCount() {
        #expect(DevServers.isServerPort(3000))
        #expect(DevServers.isServerPort(5173))
        #expect(DevServers.isServerPort(8787))
        #expect(!DevServers.isServerPort(0))
        // Temporary ports: AI tools and editors open these for their own links.
        #expect(!DevServers.isServerPort(49152))
        #expect(!DevServers.isServerPort(62705))
    }

    @Test func onlyProjectFoldersCount() {
        let home = "/Users/a"
        #expect(DevServers.isProjectFolder("/Users/a/Developer/nabiz", home: home))
        #expect(!DevServers.isProjectFolder("/", home: home))                       // apps opened from Finder
        #expect(!DevServers.isProjectFolder("/Users/a/Library/Containers/com.docker.docker/Data", home: home))
        #expect(!DevServers.isProjectFolder("/Users/a/.cache/x", home: home))
        #expect(!DevServers.isProjectFolder("/Users/ab/project", home: home))
    }

    @Test func spotsTheSecondServerOfAProject() {
        let servers = [
            server(1, port: 3000, folder: "/Users/a/p", project: "/Users/a/p"),
            server(2, port: 3001, folder: "/Users/a/p/apps/web", project: "/Users/a/p"),
            server(3, port: 8787, folder: "/Users/a/q", project: "/Users/a/q"),
        ]
        #expect(DevServers.duplicateProjects(servers) == ["/Users/a/p"])
        #expect(servers[1].subfolder == "apps/web")
        #expect(servers[0].subfolder == nil)
        #expect(servers[1].portsText == ":3001")
        #expect(servers[2].url?.absoluteString == "http://localhost:8787")
    }

    @Test func stopEndsARealServer() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", "0", "--bind", "127.0.0.1"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        usleep(300_000)
        #expect(DevServers.stop(process.processIdentifier))
        process.waitUntilExit()
        #expect(!process.isRunning)
    }

    private func server(_ pid: pid_t, port: UInt16, folder: String, project: String) -> DevServer {
        DevServer(pid: pid, ports: [port], folder: folder, project: project, tool: "vite", started: nil)
    }

    // MARK: DDC

    @Test func buildsSetAndGetMessages() {
        // 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32 = 0x9A
        #expect(DDC.setPacket(code: DDC.brightness, value: 50) == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
        let bytes: [UInt8] = [0x84, 0x03, 0x10, 0x01, 0x2C]
        let check = bytes.reduce(UInt8(0x6E ^ 0x51), ^)
        #expect(DDC.setPacket(code: DDC.brightness, value: 300) == bytes + [check])
        // 0x6E ^ 0x82 ^ 0x01 ^ 0x10 = 0xFD
        #expect(DDC.getPacket(code: DDC.brightness) == [0x82, 0x01, 0x10, 0xFD])
    }

    @Test func readsAReplyAndRejectsABrokenOne() throws {
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0]
        reply[10] = reply.dropLast().reduce(0x50, ^)
        let value = try #require(DDC.parseReply(reply))
        #expect(value.current == 50)
        #expect(value.max == 100)

        var corrupt = reply
        corrupt[9] = 0x33
        #expect(DDC.parseReply(corrupt) == nil)

        var unsupported = reply
        unsupported[3] = 0x01
        unsupported[10] = unsupported.dropLast().reduce(0x50, ^)
        #expect(DDC.parseReply(unsupported) == nil)
        #expect(DDC.parseReply([0x6E]) == nil)
    }

    @Test func matchesADisplayToItsEDID() {
        // Dell: vendor 0x10AC, product 0xA12F written low byte first.
        #expect(DDCService.edidMatches("10AC2FA1-0000-0000-2E1E-0104B53C2278", vendor: 0x10AC, product: 0xA12F))
        #expect(!DDCService.edidMatches("10AC2FA1-0000-0000-2E1E-0104B53C2278", vendor: 0x10AC, product: 0x2FA1))
        #expect(!DDCService.edidMatches("", vendor: 0x10AC, product: 0xA12F))
    }
}
