// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

/// Several accounts of one provider: found in the CLIs' folders, listed once per person, told apart by nickname.
@Suite("AI accounts")
struct AIAccountsTests {
    @Test func folderNamesComeFromNicknames() {
        #expect(AIAccounts.slug("İş") == "is")
        #expect(AIAccounts.slug("Kişisel hesap") == "kisisel-hesap")
        #expect(AIAccounts.slug("  ") == "")
    }

    @Test func keychainNamesMatchClaudeCode() {
        // Claude Code: "Claude Code-credentials-" + the first 8 hex digits of SHA-256 of CLAUDE_CONFIG_DIR.
        #expect(AIAccounts.hash8("/Users/me/.claude-work") == "1e91dd84")
    }

    @Test func signInCommandUsesTheAccountsFolder() {
        #expect(AIAccount(provider: .claude).signInCommand == "claude auth login")
        #expect(AIAccount(provider: .codex, folder: "/Users/me/.codex-work").signInCommand
            == "CODEX_HOME='/Users/me/.codex-work' codex login")
    }

    @Test func oneAccountSignedInTwiceIsListedOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nabiz-accounts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func codex(_ name: String, user: String, workspace: String, email: String) throws -> String {
            let dir = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let claims: [String: Any] = ["email": email,
                                         "https://api.openai.com/auth": ["chatgpt_user_id": user, "chatgpt_account_id": workspace]]
            let payload = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
            let auth: [String: Any] = ["tokens": ["access_token": "x", "id_token": "h.\(payload).s", "account_id": workspace]]
            try JSONSerialization.data(withJSONObject: auth).write(to: dir.appendingPathComponent("auth.json"))
            return dir.path
        }
        let work = try codex("work", user: "u1", workspace: "w1", email: "me@work.test")
        let copy = try codex("copy", user: "u1", workspace: "w1", email: "me@work.test")
        let home = try codex("home", user: "u2", workspace: "w2", email: "me@home.test")
        let empty = root.appendingPathComponent("empty").path
        try FileManager.default.createDirectory(atPath: empty, withIntermediateDirectories: true)

        let base = root.standardizedFileURL.path
        let found = AIAccounts.discover(.codex, extra: [work, copy, home, empty]).filter { $0.folder?.hasPrefix(base) ?? false }
        #expect(found.count == 2)
        #expect(Set(found.compactMap(\.email)) == ["me@work.test", "me@home.test"])
        #expect(AIAccounts.account(.codex, folder: empty) == nil)
    }

    @MainActor @Test func nicknamesTellAccountsApart() {
        var personal = AIAccount(provider: .claude)
        personal.email = "me@home.test"
        var work = AIAccount(provider: .claude, folder: "/Users/me/.claude-work")
        work.identity = "u/o"
        work.email = "me@work.test"
        let store = AILimitsStore.shared
        store.showDemo([AIStatus(account: personal), AIStatus(account: work), AIStatus(account: AIAccount(provider: .codex))],
                       nicknames: [work.id: "Work"])
        #expect(store.label(store.statuses[0]) == "me@home.test")
        #expect(store.label(store.statuses[1]) == "Work")
        #expect(store.title(store.statuses[1]) == "Claude · Work")
        // A provider's only account needs no name.
        #expect(store.label(store.statuses[2]) == nil)
        #expect(store.title(store.statuses[2]) == "Codex")
    }
}
