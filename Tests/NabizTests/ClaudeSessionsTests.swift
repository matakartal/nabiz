// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

/// The Claude Code sessions section: reading Claude Code's session files, telling a live session from a stale file,
/// the order rows show in, the closed header and when a "needs your permission" notification goes out.
@MainActor
@Suite("Claude Code sessions")
struct ClaudeSessionsTests {
    init() {
        Prefs.registerDefaults()
        UserDefaults.standard.set("en", forKey: Prefs.language)
    }

    private let dir = NSHomeDirectory() + "/.claude"

    private func session(_ pid: Int32, _ status: ClaudeSession.Status, at seconds: TimeInterval,
                         name: String? = nil) -> ClaudeSession {
        var session = ClaudeSession(pid: pid, configDir: dir, cwd: "/Users/x/Developer/app")
        session.status = status
        session.name = name
        session.statusUpdatedAt = Date(timeIntervalSince1970: seconds)
        return session
    }

    // MARK: Parsing

    @Test func readsASessionFile() throws {
        let json = """
        {"pid":73352,"sessionId":"61b7","cwd":"/Users/x/Developer/nabiz","startedAt":1795885687949,
         "procStart":"Sat Nov 28 17:08:00 2026","version":"2.1.331","kind":"interactive","entrypoint":"claude-desktop",
         "name":"Ultra paket farkı","nameSource":"user","status":"busy","updatedAt":1795888759484,"statusUpdatedAt":1795888759000}
        """
        let session = try #require(ClaudeSessions.parse(Data(json.utf8), configDir: dir))
        #expect(session.pid == 73352)
        #expect(session.sessionID == "61b7")
        #expect(session.cwd == "/Users/x/Developer/nabiz")
        #expect(session.name == "Ultra paket farkı")
        #expect(session.status == .busy)
        #expect(session.entrypoint == "claude-desktop")
        #expect(session.startedAt == Date(timeIntervalSince1970: 1_795_885_687.949))
        #expect(session.statusUpdatedAt == Date(timeIntervalSince1970: 1_795_888_759))
        #expect(session.procStart == "Sat Nov 28 17:08:00 2026")
        #expect(session.id == dir + "#73352")
    }

    @Test func readsWaitingAndOddFilesSafely() throws {
        let waiting = #"{"pid":5,"cwd":"/tmp/a","status":"waiting","waitingFor":"permission prompt"}"#
        let parsed = try #require(ClaudeSessions.parse(Data(waiting.utf8), configDir: dir))
        #expect(parsed.status == .waiting)
        #expect(parsed.waitsForPermission)
        // An unknown or missing status reads as idle; a blank name as no name.
        let odd = #"{"pid":6,"cwd":"/tmp/b","status":"thinking-hard","name":"  "}"#
        #expect(ClaudeSessions.parse(Data(odd.utf8), configDir: dir)?.status == .idle)
        #expect(ClaudeSessions.parse(Data(odd.utf8), configDir: dir)?.name == nil)
        // The pid can come from the file name when the file leaves it out.
        #expect(ClaudeSessions.parse(Data(#"{"cwd":"/tmp/c"}"#.utf8), configDir: dir, filePID: 42)?.pid == 42)
        // Not a session: broken JSON, no folder, no pid.
        #expect(ClaudeSessions.parse(Data("{\"pid\":7,".utf8), configDir: dir) == nil)
        #expect(ClaudeSessions.parse(Data(#"{"pid":7}"#.utf8), configDir: dir) == nil)
        #expect(ClaudeSessions.parse(Data(#"{"cwd":"/tmp/d"}"#.utf8), configDir: dir) == nil)
        #expect(ClaudeSessions.parse(Data(#"[1,2]"#.utf8), configDir: dir) == nil)
    }

    // MARK: Live or stale

    @Test func tellsTheSameProcessFromAReusedPID() throws {
        let utc = try #require(ClaudeSessions.procStartDates("Sat Nov 28 17:08:00 2026").first)
        // The process started when the file says: the same one, whatever startedAt says.
        #expect(ClaudeSessions.isSameProcess(started: utc, startedAt: nil, procStart: "Sat Nov 28 17:08:00 2026"))
        #expect(ClaudeSessions.isSameProcess(started: utc.addingTimeInterval(1), startedAt: nil, procStart: "Sat Nov 28 17:08:00 2026"))
        // A single-digit day padded the way `ps` prints it.
        let padded = try #require(ClaudeSessions.procStartDates("Sun Nov  1 09:00:00 2026").first)
        #expect(ClaudeSessions.isSameProcess(started: padded, startedAt: nil, procStart: "Sun Nov  1 09:00:00 2026"))
        // The session was written 30 s after its process started: still the same one.
        let started = Date(timeIntervalSince1970: 1_795_800_000)
        #expect(ClaudeSessions.isSameProcess(started: started, startedAt: started.addingTimeInterval(30), procStart: nil))
        // A process that started after the session did has only taken over its pid.
        #expect(!ClaudeSessions.isSameProcess(started: started.addingTimeInterval(3600), startedAt: started, procStart: nil))
        #expect(!ClaudeSessions.isSameProcess(started: utc.addingTimeInterval(3600), startedAt: nil, procStart: "Sat Nov 28 17:08:00 2026"))
        // Nothing to compare with: trust the live process.
        #expect(ClaudeSessions.isSameProcess(started: started, startedAt: nil, procStart: nil))
        #expect(ClaudeSessions.isSameProcess(started: started, startedAt: nil, procStart: "garbled"))
    }

    @Test func findsTheAppASessionRunsIn() {
        // Terminal: claude → zsh → login → Terminal.
        #expect(ClaudeSessions.host(entrypoint: "cli", ancestors: [10, 11, 12], apps: [12, 99], claudeApp: nil) == 12)
        // Claude's own sessions open the Claude app, whatever their parents are.
        #expect(ClaudeSessions.host(entrypoint: "claude-desktop", ancestors: [10, 12], apps: [12], claudeApp: 50) == 50)
        #expect(ClaudeSessions.host(entrypoint: "claude-desktop", ancestors: [10, 12], apps: [12], claudeApp: nil) == 12)
        // tmux or a background job: no app to show.
        #expect(ClaudeSessions.host(entrypoint: "cli", ancestors: [10, 11], apps: [99], claudeApp: nil) == nil)
    }

    // MARK: Showing

    @Test func sortsWaitingThenWorkingThenIdleNewestFirst() {
        let list = [session(1, .idle, at: 100), session(2, .busy, at: 50), session(3, .waiting, at: 10),
                    session(4, .idle, at: 300), session(5, .busy, at: 80), session(6, .waiting, at: 20)]
        #expect(ClaudeSessions.sorted(list).map(\.pid) == [6, 3, 5, 2, 4, 1])
    }

    @Test func summarisesTheClosedHeader() {
        let waiting = ClaudeSessions.summary([session(1, .waiting, at: 0), session(2, .waiting, at: 0), session(3, .busy, at: 0)])
        #expect(waiting.text == "2 waiting")
        #expect(waiting.attention)
        let working = ClaudeSessions.summary([session(1, .busy, at: 0), session(2, .idle, at: 0)])
        #expect(working.text == "1 working")
        #expect(!working.attention)
        #expect(ClaudeSessions.summary([session(1, .idle, at: 0), session(2, .idle, at: 0)]).text == "2 idle")
        UserDefaults.standard.set("tr", forKey: Prefs.language)
        defer { UserDefaults.standard.set("en", forKey: Prefs.language) }
        #expect(ClaudeSessions.summary([session(1, .waiting, at: 0)]).text == "1 bekliyor")
    }

    @Test func namesTheProjectAndAccount() {
        #expect(ClaudeSessions.project("/Users/x/Developer/nabiz") == "nabiz")
        #expect(ClaudeSessions.project("/Users/x/Developer/nabiz/.claude/worktrees/agent-a5d7") == "nabiz · agent-a5d7")
        #expect(ClaudeSessions.project("/Users/x/Developer/nabiz/.claude/worktrees/agent-a5d7/Sources") == "nabiz · agent-a5d7")
        #expect(ClaudeSessions.project("/Users/x/Library/Application Support/Claude/scratch-workspaces/a/b/scratch-1") == nil)
        #expect(ClaudeSessions.project(NSHomeDirectory()) == "~")
        var unnamed = session(1, .idle, at: 0)
        unnamed.cwd = "/Users/x/Developer/finqt"
        #expect(ClaudeSessions.title(unnamed) == "finqt")
        #expect(ClaudeSessions.title(session(1, .idle, at: 0, name: "Ultra paket farkı")) == "Ultra paket farkı")
        #expect(ClaudeSessions.folderLabel("/Users/x/.claude-work") == "work")
        #expect(ClaudeSessions.folderLabel("/Users/x/.synara/userdata/provider-homes/claude/instance-1/.claude") == "Synara")
        #expect(ClaudeSessions.folderLabel("/Users/x/.synara-beta/userdata/provider-homes/claude/i/.claude") == "Synara beta")
        #expect(ClaudeSessions.folderLabel("/Users/x/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig") == "Xcode")
        #expect(ClaudeSessions.folderLabel("/Users/x/.config/claude") == "claude")
    }

    @Test func saysWhatEachSessionIsDoing() {
        let now = Date(timeIntervalSince1970: 10_000)
        var waiting = session(1, .waiting, at: 0)
        waiting.waitingFor = "permission prompt"
        #expect(ClaudeSessions.statusText(waiting, now: now) == "Needs you")
        #expect(ClaudeSessions.statusText(session(2, .busy, at: 0), now: now) == "Working")
        #expect(ClaudeSessions.statusText(session(3, .idle, at: 10_000 - 12 * 60), now: now) == "12m ago")
        #expect(ClaudeSessions.entrypointName("claude-desktop") == "Claude")
        #expect(ClaudeSessions.entrypointName("cli") == "Terminal")
        #expect(ClaudeSessions.entrypointName("sdk-cli") == "Agent SDK")
    }

    // MARK: Notifications

    @Test func announcesAWaitOnlyWhenItStarts() {
        let before: [String: ClaudeSession.Status] = [session(1, .busy, at: 0).id: .busy,
                                                      session(2, .waiting, at: 0).id: .waiting,
                                                      session(3, .idle, at: 0).id: .idle]
        let now = [session(1, .waiting, at: 1), session(2, .waiting, at: 1), session(3, .idle, at: 1), session(4, .waiting, at: 1)]
        // 1 started waiting; 2 was already waiting (told once); 4 was never seen before, so it's no change.
        #expect(ClaudeSessions.newlyWaiting(before: before, now: now).map(\.pid) == [1])
        #expect(ClaudeSessions.newlyWaiting(before: [:], now: now).isEmpty)
    }
}
