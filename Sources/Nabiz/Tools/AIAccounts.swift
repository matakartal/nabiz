// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import CryptoKit
import Foundation
import Security

/// One signed-in account of a provider: where its CLI keeps the sign-in and, when the CLI's files say so, who it is.
/// A second account is the same CLI run with a folder of its own (CLAUDE_CONFIG_DIR, CODEX_HOME, GEMINI_CLI_HOME).
struct AIAccount: Identifiable, Equatable, Sendable {
    let provider: AIProvider
    /// The CLI's own folder; nil for the CLI's default place.
    var folder: String?
    /// Who is signed in (account and organisation, workspace, Google user), from the CLI's own files.
    var identity: String?
    var email: String?
    /// The team or workspace the account belongs to; a personal plan has none.
    var team: String?
    /// Claude: the Keychain item the CLI named after the folder.
    var keychainService: String?
    /// The file that holds the sign-in (Codex, Gemini, and Claude's file fallback).
    var file: String?
    /// When the sign-in was last written: with one person signed in in several folders, the freshest one is read.
    var updated = Date.distantPast

    var id: String { "\(provider.rawValue):" + (identity ?? folder ?? "default") }
    var isDefault: Bool { folder == nil }

    /// "~/.claude-work"
    var folderName: String? { folder.map { ($0 as NSString).abbreviatingWithTildeInPath } }

    /// The Terminal command that signs this account in again (or for the first time), with its own folder.
    var signInCommand: String {
        let env = folder.map { "\(provider.homeVariable)=\(Shell.quote($0)) " } ?? ""
        return env + provider.signInCommand
    }
}

extension AIProvider {
    /// The environment variable that gives the CLI a folder of its own.
    var homeVariable: String {
        switch self {
        case .claude: "CLAUDE_CONFIG_DIR"
        case .codex: "CODEX_HOME"
        case .gemini: "GEMINI_CLI_HOME"
        case .grok: "GROK_HOME"
        }
    }

    var signInCommand: String {
        switch self {
        case .claude: "claude auth login"
        case .codex: "codex login"
        // Gemini CLI asks how to sign in on its first start.
        case .gemini: "gemini"
        // Grok CLI signs in on its first start too.
        case .grok: "grok"
        }
    }

    /// "~/.claude": the default folder; extra accounts live next to it as "~/.claude-work".
    var folderStem: String { ".\(rawValue)" }
}

/// Finds every account the CLIs keep on this Mac. Reads files and Keychain item names only, never a secret,
/// so looking causes no macOS prompt.
enum AIAccounts {
    static func discover(_ providers: [AIProvider], extra: [String: [String]]) -> [AIAccount] {
        providers.flatMap { discover($0, extra: extra[$0.rawValue] ?? []) }
    }

    /// The CLI's default account first, then the others in a stable order. One person signed in in several
    /// folders is listed once: the default copy, otherwise the freshest.
    static func discover(_ provider: AIProvider, extra: [String]) -> [AIAccount] {
        let others = candidates(provider, extra: extra).compactMap { account(provider, folder: $0) }
        var result: [AIAccount] = []
        var seen = Set<String>()
        for account in [account(provider, folder: nil)].compactMap({ $0 }) + others.sorted(by: { $0.updated > $1.updated }) {
            if let identity = account.identity, !seen.insert(identity).inserted { continue }
            result.append(account)
        }
        // Nothing signed in anywhere: keep the default, so the panel can say what is missing.
        guard !result.isEmpty else { return [AIAccount(provider: provider)] }
        return result.filter(\.isDefault) + result.filter { !$0.isDefault }.sorted { ($0.folder ?? "") < ($1.folder ?? "") }
    }

    /// The account signed in in `folder` (nil: the CLI's default place), or nil when nothing is signed in there.
    static func account(_ provider: AIProvider, folder: String?) -> AIAccount? {
        switch provider {
        case .claude: claude(folder)
        case .codex: codex(folder)
        case .gemini: gemini(folder)
        case .grok: grok(folder)
        }
    }

    /// Folders that may hold another sign-in: "~/.claude-*" next to the default one, "~/.config/claude*",
    /// the ones the user added, and Xcode's own Claude agent.
    private static func candidates(_ provider: AIProvider, extra: [String]) -> [String] {
        let home = NSHomeDirectory()
        var paths: [String] = []
        for (dir, stem) in [(home, provider.folderStem), (home + "/.config", provider.rawValue)] {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            where name.hasPrefix(stem) && !(dir == home && name == stem) {
                paths.append(dir + "/" + name)
            }
        }
        if provider == .claude { paths.append(home + "/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig") }
        // Apps that run the CLIs with accounts of their own (Synara: ~/.synara/userdata/provider-homes/claude/<id>/.claude).
        for app in ((try? FileManager.default.contentsOfDirectory(atPath: home)) ?? []) where app.hasPrefix(".synara") {
            let homes = "\(home)/\(app)/userdata/provider-homes/\(provider.rawValue)"
            for instance in (try? FileManager.default.contentsOfDirectory(atPath: homes)) ?? [] {
                paths += ["\(homes)/\(instance)/\(provider.folderStem)", "\(homes)/\(instance)"]
            }
        }
        paths += extra
        var seen = Set<String>()
        return paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { isFolder($0) && seen.insert($0).inserted }
    }

    // MARK: Claude

    private static func claude(_ folder: String?) -> AIAccount? {
        let home = NSHomeDirectory()
        var account = AIAccount(provider: .claude, folder: folder)
        let config: String
        let services: [String]
        if let folder {
            // Claude Code names the item after the folder exactly as it was given, so try it with and without a slash.
            services = [folder, folder + "/"].map { "Claude Code-credentials-" + hash8($0) }
            config = folder + "/.claude.json"
            account.file = folder + "/.credentials.json"
        } else {
            services = ["Claude Code-credentials"]
            config = home + "/.claude.json"
            account.file = home + "/.claude/.credentials.json"
        }
        for service in services {
            if let date = keychainDate(service) {
                account.keychainService = service
                account.updated = date
                break
            }
        }
        let fileDate = account.file.flatMap(modified)
        guard account.keychainService != nil || fileDate != nil else { return nil }
        account.updated = max(account.updated, fileDate ?? .distantPast)
        if let oauth = json(config)?["oauthAccount"] as? [String: Any] {
            let user = oauth["accountUuid"] as? String ?? ""
            let org = oauth["organizationUuid"] as? String ?? ""
            if !(user + org).isEmpty { account.identity = "\(user)/\(org)" }
            account.email = oauth["emailAddress"] as? String
            let kind = (oauth["organizationType"] as? String ?? "").lowercased()
            if kind.contains("team") || kind.contains("enterprise") { account.team = oauth["organizationName"] as? String }
        }
        return account
    }

    /// The first 8 hex digits of SHA-256, as Claude Code uses them in its Keychain item names.
    static func hash8(_ text: String) -> String {
        SHA256.hash(data: Data(text.precomposedStringWithCanonicalMapping.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// When the newest Keychain item of the service was written, without reading its secret (so no prompt).
    private static func keychainDate(_ service: String) -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]], !items.isEmpty else { return nil }
        return items.compactMap { $0[kSecAttrModificationDate as String] as? Date }.max() ?? .distantPast
    }

    // MARK: Codex

    private static func codex(_ folder: String?) -> AIAccount? {
        let file = (folder ?? NSHomeDirectory() + "/.codex") + "/auth.json"
        guard let tokens = json(file)?["tokens"] as? [String: Any], tokens["access_token"] is String else { return nil }
        var account = AIAccount(provider: .codex, folder: folder, file: file, updated: modified(file) ?? .distantPast)
        let claims = jwtClaims(tokens["id_token"] as? String)
        let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        // A workspace (account) can have several people; the pair is one person in one workspace.
        let workspace = tokens["account_id"] as? String ?? auth?["chatgpt_account_id"] as? String ?? ""
        let user = auth?["chatgpt_user_id"] as? String ?? auth?["user_id"] as? String ?? ""
        if !(workspace + user).isEmpty { account.identity = "\(user)/\(workspace)" }
        account.email = claims["email"] as? String
        return account
    }

    // MARK: Gemini

    private static func gemini(_ folder: String?) -> AIAccount? {
        // GEMINI_CLI_HOME stands in for the home folder, so the sign-in is in its ".gemini" (or the folder itself).
        let dirs = folder.map { [$0 + "/.gemini", $0] } ?? [NSHomeDirectory() + "/.gemini"]
        for dir in dirs {
            let file = dir + "/oauth_creds.json"
            guard let creds = json(file), creds["access_token"] is String else { continue }
            var account = AIAccount(provider: .gemini, folder: folder, file: file, updated: modified(file) ?? .distantPast)
            let claims = jwtClaims(creds["id_token"] as? String)
            account.email = claims["email"] as? String ?? json(dir + "/google_accounts.json")?["active"] as? String
            account.identity = claims["sub"] as? String ?? account.email
            return account
        }
        return nil
    }

    // MARK: Grok

    private static func grok(_ folder: String?) -> AIAccount? {
        let file = (folder ?? NSHomeDirectory() + "/.grok") + "/auth.json"
        guard let all = json(file),
              let entry = all.values.compactMap({ $0 as? [String: Any] }).first(where: { $0["key"] is String })
        else { return nil }
        var account = AIAccount(provider: .grok, folder: folder, file: file, updated: modified(file) ?? .distantPast)
        account.email = entry["email"] as? String
        account.identity = entry["user_id"] as? String ?? account.email
        return account
    }

    // MARK: Helpers

    private static func json(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// The readable part of a sign-in token (who it belongs to); its signature is not needed for that.
    static func jwtClaims(_ token: String?) -> [String: Any] {
        let parts = token?.split(separator: ".") ?? []
        guard parts.count == 3 else { return [:] }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return claims
    }

    private static func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private static func isFolder(_ path: String) -> Bool {
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &folder) && folder.boolValue
    }

    /// "İş hesabı" → "is-hesabi": a folder name from a nickname.
    static func slug(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            .replacingOccurrences(of: "ı", with: "i").lowercased()
        let words = folded.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return words.joined(separator: "-")
    }
}
