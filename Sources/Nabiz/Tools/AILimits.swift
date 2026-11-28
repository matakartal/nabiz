// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Observation
import Security

/// One usage window of an AI subscription: "5-hour 22%, resets in 2 h".
struct AILimit: Identifiable, Sendable {
    var id: String
    let label: String
    /// 0...1
    let used: Double
    let resetsAt: Date?
    /// The plan's main window (Claude's overall weekly limit, Codex's weekly one): what the menu bar shows.
    var primary = false
    /// How long the window lasts (5 h, 7 d…), for the pace; nil when the provider doesn't say.
    var period: TimeInterval?
    /// Where the window is heading at the current speed; filled in by the store.
    var pace: PaceReading?

    var remaining: Double { max(0, 1 - used) }

    /// "6% left" or "94%", as the user chose in Settings.
    var displayText: String {
        Prefs.bool(Prefs.aiRemaining)
            ? L("\(Format.percent(remaining)) kaldı", "\(Format.percent(remaining)) left")
            : Format.percent(used)
    }

    /// The short value for the menu bar and closed headers.
    var shortText: String { Format.percent(Prefs.bool(Prefs.aiRemaining) ? remaining : used) }
}

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case claude, codex, gemini

    var id: String { rawValue }

    /// For the menu bar and closed section headers.
    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        }
    }

    var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "ChatGPT · Codex"
        case .gemini: "Gemini"
        }
    }

    /// The settings key that turns this provider on. Every provider is off until the user turns it on.
    var prefKey: String { "ai.\(rawValue)" }

    /// Where the sign-in is read from, shown in Settings.
    var source: String {
        switch self {
        case .claude: L("Claude Code oturumu (Anahtar Zinciri)", "Claude Code sign-in (Keychain)")
        case .codex: "~/.codex/auth.json"
        case .gemini: "~/.gemini/oauth_creds.json"
        }
    }

    /// The only server the sign-in is sent to: the provider's own.
    var server: String {
        switch self {
        case .claude: "api.anthropic.com"
        case .codex: "chatgpt.com"
        case .gemini: "cloudcode-pa.googleapis.com"
        }
    }
}

struct AIStatus: Identifiable, Sendable {
    let account: AIAccount
    var plan: String?
    var limits: [AILimit] = []
    /// Shown instead of limits when they could not be read.
    var problem: String?
    /// The problem is the sign-in itself (missing, expired, rejected): signing in again fixes it.
    var needsSignIn = false
    /// The e-mail, from the CLI's files or else from the provider.
    var email: String?
    /// Who the provider says this is; two folders signed in to the same account are shown once.
    var identity: String?

    init(account: AIAccount) {
        self.account = account
        email = account.email
        identity = account.identity
    }

    var provider: AIProvider { account.provider }
    var id: String { account.id }

    /// The limit to show when there is room for one: the main window, never a per-model one.
    var headline: AILimit? { limits.first(where: \.primary) ?? limits.first }
}

/// Reads subscription limits with the sign-ins the official CLIs already keep on this Mac, for every account found.
/// Tokens never leave the Mac except to their own provider, are never stored by Nabız, and are never refreshed by it.
@MainActor
@Observable
final class AILimitsStore {
    static let shared = AILimitsStore()

    /// One per account shown, each provider's default account first.
    private(set) var statuses: [AIStatus] = []
    /// Every account found for the providers that are on, hidden ones too (Settings lists them).
    private(set) var accounts: [AIAccount] = []
    private(set) var loading = false
    /// Nicknames by account id, and by "dir:<folder>" for an account added in Settings before it was signed in.
    private(set) var nicknames = UserDefaults.standard.dictionary(forKey: Prefs.aiNicknames) as? [String: String] ?? [:]
    /// Accounts the user turned off in Settings.
    private(set) var hidden = Set(UserDefaults.standard.stringArray(forKey: Prefs.aiHiddenAccounts) ?? [])
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var fetchedFor: [String] = []
    @ObservationIgnored private var looking = false
    @ObservationIgnored private var again = false
    /// Showing made-up accounts (`--snapshot … --ai-demo`): nothing is read.
    @ObservationIgnored private var demo = false

    @ObservationIgnored private var history = PaceHistory()

    /// Records each reading and works out where every window is heading.
    private func withPace(_ status: AIStatus) -> AIStatus {
        var status = status
        let now = Date()
        for index in status.limits.indices {
            let limit = status.limits[index]
            history.record(limit.id, used: limit.used, at: now)
            status.limits[index].pace = PaceModel.read(used: limit.used, resetsAt: limit.resetsAt, period: limit.period,
                                                       recentRate: history.recentRate(limit.id, now: now), now: now)
        }
        return status
    }

    /// Limits on pace to run out before they reset, with their account.
    var burning: [(status: AIStatus, limit: AILimit)] {
        statuses.flatMap { status in
            status.limits.filter { $0.pace?.status == .behind }.map { (status, $0) }
        }
    }

    var enabled: [AIProvider] { AIProvider.allCases.filter { Prefs.bool($0.prefKey) } }

    /// True once the first reading is in (there may be nothing to show when every account is turned off).
    var hasRead: Bool { fetchedAt != nil }

    /// Folders the user added by hand, by provider.
    var folders: [String: [String]] { UserDefaults.standard.dictionary(forKey: Prefs.aiFolders) as? [String: [String]] ?? [:] }

    /// Looks for accounts, then fetches again when the last result is older than `maxAge` seconds or the accounts
    /// changed (a new sign-in, a provider turned on or off).
    func refreshIfNeeded(force: Bool = false, maxAge: TimeInterval = 120) {
        let providers = enabled
        guard !demo else { return }
        guard !providers.isEmpty else {
            statuses = []
            accounts = []
            fetchedFor = []
            return
        }
        guard !loading, !looking else {
            if force { again = true }
            return
        }
        looking = true
        let extra = folders
        Task {
            let found = await Task.detached(priority: .utility) { AIAccounts.discover(providers, extra: extra) }.value
            looking = false
            if found != accounts { accounts = found }
            let wanted = found.filter { !hidden.contains($0.id) }
            if !force, let fetchedAt, Date().timeIntervalSince(fetchedAt) < maxAge, wanted.map(\.id) == fetchedFor {
                runAgainIfAsked()
                return
            }
            await fetch(wanted)
        }
    }

    private func fetch(_ wanted: [AIAccount]) async {
        loading = true
        var results: [AIStatus] = []
        await withTaskGroup(of: AIStatus.self) { group in
            for account in wanted {
                group.addTask { await AIFetch.status(for: account) }
            }
            for await status in group { results.append(status) }
        }
        // The provider can tell that two folders are one account even when their files could not.
        var seen = Set<String>()
        statuses = wanted.compactMap { account in results.first { $0.id == account.id } }
            .filter { status in status.identity.map { seen.insert("\(status.provider.rawValue):\($0)").inserted } ?? true }
            .filter { !hidden.contains($0.id) }
            .map(withPace)
        fetchedFor = wanted.map(\.id)
        fetchedAt = Date()
        loading = false
        runAgainIfAsked()
    }

    private func runAgainIfAsked() {
        guard again else { return }
        again = false
        refreshIfNeeded(force: true)
    }

    // MARK: Accounts

    /// The nickname as typed ("" when there is none).
    func nickname(_ account: AIAccount) -> String {
        nicknames[account.id] ?? account.folder.flatMap { nicknames["dir:" + $0] } ?? ""
    }

    func setNickname(_ name: String, for account: AIAccount) {
        nicknames[account.id] = name.isEmpty ? nil : name
        if let folder = account.folder { nicknames["dir:" + folder] = nil }
        UserDefaults.standard.set(nicknames, forKey: Prefs.aiNicknames)
    }

    /// What tells an account apart in the panel: its nickname, or, when the provider has more than one account
    /// showing, its team or e-mail (the folder when neither is known). nil for a provider's only account.
    func label(_ status: AIStatus) -> String? {
        let nick = nickname(status.account).trimmingCharacters(in: .whitespaces)
        if !nick.isEmpty { return nick }
        guard statuses.count(where: { $0.provider == status.provider }) > 1 else { return nil }
        return status.account.team ?? status.email ?? status.account.folderName
    }

    /// "Claude · Work" for notifications and suggestions; just "Claude" for a provider's only account.
    func title(_ status: AIStatus) -> String {
        label(status).map { "\(status.provider.shortName) · \($0)" } ?? status.provider.shortName
    }

    /// E-mail, team and where the sign-in lives, for tooltips and Settings.
    func details(_ account: AIAccount, email: String? = nil) -> String {
        [email ?? account.email, account.team, account.folderName ?? L("varsayılan oturum", "default sign-in")]
            .compactMap { $0 }.joined(separator: " · ")
    }

    func isShown(_ account: AIAccount) -> Bool { !hidden.contains(account.id) }

    func setShown(_ shown: Bool, _ account: AIAccount) {
        if shown { hidden.remove(account.id) } else { hidden.insert(account.id) }
        UserDefaults.standard.set(hidden.sorted(), forKey: Prefs.aiHiddenAccounts)
        statuses.removeAll { hidden.contains($0.id) }
        fetchedFor.removeAll { hidden.contains($0) }
        if shown { refreshIfNeeded(force: true) }
    }

    /// Opens Terminal with the provider's own sign-in for this account (its folder, if it has one).
    func signIn(_ account: AIAccount) {
        TerminalLauncher.open(NSHomeDirectory(), run: account.signInCommand,
                              title: L("\(account.provider.shortName) girişi", "\(account.provider.shortName) sign-in"))
    }

    /// A second (third…) account: the CLI signs in with a folder of its own next to the default one
    /// ("~/.claude-work"), so the default sign-in stays as it is. The account shows up once the sign-in is done.
    func addAccount(_ provider: AIProvider, nickname: String) {
        let name = nickname.trimmingCharacters(in: .whitespaces)
        let slug = AIAccounts.slug(name)
        let base = NSHomeDirectory() + "/" + provider.folderStem + "-" + (slug.isEmpty ? "2" : slug)
        var folder = base
        var number = 2
        // A folder that already holds a sign-in belongs to another account; an empty one (a sign-in that was
        // left halfway) is used again.
        while AIAccounts.account(provider, folder: folder) != nil {
            folder = base + "-\(number)"
            number += 1
        }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        if !name.isEmpty {
            nicknames["dir:" + folder] = name
            UserDefaults.standard.set(nicknames, forKey: Prefs.aiNicknames)
        }
        UserDefaults.standard.set(true, forKey: provider.prefKey)
        signIn(AIAccount(provider: provider, folder: folder))
    }

    /// A CLI folder the user picked by hand. Returns its provider, or nil when no sign-in is there.
    func addFolder(_ path: String) -> AIProvider? {
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        guard let provider = AIProvider.allCases.first(where: { AIAccounts.account($0, folder: path) != nil }) else { return nil }
        var all = folders
        if !(all[provider.rawValue] ?? []).contains(path) { all[provider.rawValue, default: []].append(path) }
        UserDefaults.standard.set(all, forKey: Prefs.aiFolders)
        UserDefaults.standard.set(true, forKey: provider.prefKey)
        refreshIfNeeded(force: true)
        return provider
    }

    /// Made-up accounts for `--snapshot` layout checks.
    func showDemo(_ demo: [AIStatus], nicknames demoNicknames: [String: String]) {
        self.demo = true
        statuses = demo.map(withPace)
        accounts = demo.map(\.account)
        nicknames = demoNicknames
        fetchedAt = Date()
    }
}

// MARK: - Fetching

private enum AIFetch {
    static func status(for account: AIAccount) async -> AIStatus {
        var status = switch account.provider {
        case .claude: await claude(account)
        case .codex: await codex(account)
        case .gemini: await gemini(account)
        }
        // Every account keeps its own pace history; the default one keeps the ids it always had.
        if !account.isDefault {
            for index in status.limits.indices { status.limits[index].id = "\(account.id)|\(status.limits[index].id)" }
        }
        return status
    }

    /// Signing in again is the fix: the CLI's own place, or this account's folder.
    private static func expired(_ status: inout AIStatus, tr: String, en: String) {
        status.needsSignIn = true
        status.problem = status.account.isDefault
            ? L("Oturum süresi doldu, \(tr) bir kez aç", "Sign-in expired, open \(en) once")
            : L("Oturum süresi doldu, bu hesapla yeniden giriş yap", "Sign-in expired, sign in with this account again")
    }

    // MARK: Claude

    static func claude(_ account: AIAccount) async -> AIStatus {
        var status = AIStatus(account: account)
        let credentials = account.isDefault
            ? claudeCredentials(service: "Claude Code-credentials", file: NSHomeDirectory() + "/.claude/.credentials.json")
            : claudeCredentials(service: account.keychainService, file: account.file)
        guard let oauth = credentials.oauth, let token = oauth["accessToken"] as? String else {
            status.problem = credentials.error ?? L("Claude Code oturumu bulunamadı", "No Claude Code sign-in found")
            status.needsSignIn = credentials.error == nil
            return status
        }
        if let expires = number(oauth["expiresAt"]), expires / 1000 < Date().timeIntervalSince1970 {
            expired(&status, tr: "Claude Code'u", en: "Claude Code")
            return status
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let json = await load(request, into: &status) else { return status }

        // { "five_hour": { "utilization": 22.0, "resets_at": "…" }, "seven_day": {…}, "seven_day_opus": {…} }
        // Newer responses list every window in "limits", including per-model ones (e.g. a model's own weekly cap).
        if let limits = json["limits"] as? [[String: Any]], !limits.isEmpty {
            if let five = json["five_hour"] as? [String: Any], let percent = number(five["utilization"]) {
                status.limits.append(AILimit(id: "claude.five_hour", label: windowLabel("five_hour"), used: percent / 100,
                                             resetsAt: date(five["resets_at"]), period: 5 * 3600))
            }
            for (index, limit) in limits.enumerated() {
                guard let percent = number(limit["percent"]) else { continue }
                let model = ((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                let group = limit["group"] as? String ?? ""
                let label = model ?? (group == "weekly" ? windowLabel("seven_day") : group.replacingOccurrences(of: "_", with: " ").capitalized)
                let overall = model == nil && (limit["kind"] as? String ?? "").hasSuffix("_all") && group == "weekly"
                status.limits.append(AILimit(id: "claude.limit.\(index)", label: label, used: percent / 100,
                                             resetsAt: date(limit["resets_at"]), primary: overall,
                                             period: group == "weekly" ? 7 * 86_400 : nil))
            }
            await claudeProfile(token: token, into: &status)
            return status
        }

        let order = ["five_hour", "seven_day"]
        let keys = json.keys.sorted { (order.firstIndex(of: $0) ?? 9, $0) < (order.firstIndex(of: $1) ?? 9, $1) }
        for key in keys where key != "extra_usage" || ((json[key] as? [String: Any])?["is_enabled"] as? Bool ?? false) {
            guard let window = json[key] as? [String: Any], let percent = number(window["utilization"]) else { continue }
            status.limits.append(AILimit(id: "claude.\(key)", label: windowLabel(key), used: percent / 100,
                                         resetsAt: date(window["resets_at"]), primary: key == "seven_day",
                                         period: key == "five_hour" ? 5 * 3600 : key.hasPrefix("seven_day") ? 7 * 86_400 : nil))
        }
        if status.limits.isEmpty { status.problem = L("Limit bilgisi yok", "No limit data") }
        await claudeProfile(token: token, into: &status)
        return status
    }

    /// The plan as Anthropic's server reports it now, and who the account is. The token's own "subscriptionType"
    /// can be out of date (it is set when the CLI signs in), so it is never used; with no server answer the plan is
    /// simply not shown.
    private static func claudeProfile(token: String, into status: inout AIStatus) async {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/profile")!, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        var ignored = AIStatus(account: status.account)
        guard let json = await load(request, into: &ignored) else { return }
        let person = json["account"] as? [String: Any]
        let organization = json["organization"] as? [String: Any]
        if status.email == nil { status.email = person?["email_address"] as? String ?? person?["email"] as? String }
        if status.identity == nil, let user = person?["uuid"] as? String {
            status.identity = "\(user)/\(organization?["uuid"] as? String ?? "")"
        }
        status.plan = claudePlan(json)
    }

    private static func claudePlan(_ json: [String: Any]) -> String? {
        var words: [String] = []
        for scope in ["organization", "account"] {
            guard let dict = json[scope] as? [String: Any] else { continue }
            for (key, value) in dict where ["type", "tier", "plan", "subscription", "has_"].contains(where: key.contains) {
                if let text = value as? String { words.append(text.lowercased()) }
                if let flag = value as? Bool, flag { words.append(key.lowercased()) }
            }
        }
        let all = words.joined(separator: " ")
        if all.contains("ultra") { return "Ultra" }
        if all.contains("max_20x") || all.contains("max20") { return "Max 20x" }
        if all.contains("max_5x") || all.contains("max5") { return "Max 5x" }
        if all.contains("max") { return "Max" }
        if all.contains("enterprise") { return "Enterprise" }
        if all.contains("team") { return "Team" }
        if all.contains("pro") { return "Pro" }
        return nil
    }

    /// Claude Code keeps its sign-in in the login Keychain on macOS (and in ~/.claude/.credentials.json elsewhere).
    /// The Keychain read goes through the Security framework, so macOS shows its standard
    /// "Nabız wants to use your confidential information" prompt; choose Always Allow to keep it quiet.
    private static func claudeCredentials(service: String?, file: String?) -> (oauth: [String: Any]?, error: String?) {
        var error: String?
        guard let service else {
            return (file.flatMap { oauth(from: FileManager.default.contents(atPath: $0)) }, nil)
        }
        // There can be several items (old installs left one under account "unknown"). Try the newest first,
        // the one under this Mac user's name before any other.
        var listQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var listed: CFTypeRef?
        _ = SecItemCopyMatching(listQuery as CFDictionary, &listed)
        listQuery.removeAll()
        let accounts = ((listed as? [[String: Any]]) ?? [])
            .sorted {
                let mine0 = ($0[kSecAttrAccount as String] as? String) == NSUserName()
                let mine1 = ($1[kSecAttrAccount as String] as? String) == NSUserName()
                if mine0 != mine1 { return mine0 }
                return ($0[kSecAttrModificationDate as String] as? Date ?? .distantPast)
                    > ($1[kSecAttrModificationDate as String] as? Date ?? .distantPast)
            }
            .compactMap { $0[kSecAttrAccount as String] as? String }

        for account in accounts {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            let result = SecItemCopyMatching(query as CFDictionary, &item)
            if result == errSecSuccess, let oauth = oauth(from: item as? Data) { return (oauth, nil) }
            if result != errSecSuccess && result != errSecItemNotFound {
                let message = SecCopyErrorMessageString(result, nil) as String? ?? "OSStatus \(result)"
                error = L("Anahtar Zinciri: \(message)", "Keychain: \(message)")
            }
        }
        if let file, let oauth = oauth(from: FileManager.default.contents(atPath: file)) { return (oauth, nil) }
        return (nil, error)
    }

    private static func oauth(from data: Data?) -> [String: Any]? {
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["claudeAiOauth"] as? [String: Any]
    }

    private static func windowLabel(_ key: String) -> String {
        switch key {
        case "five_hour": return L("5 saat", "5-hour")
        case "seven_day": return L("Haftalık", "Weekly")
        case "extra_usage": return L("Ek kullanım", "Extra usage")
        default:
            let model = key.replacingOccurrences(of: "seven_day_", with: "").replacingOccurrences(of: "_", with: " ").capitalized
            return key.hasPrefix("seven_day_") ? model : key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: Codex / ChatGPT

    static func codex(_ account: AIAccount) async -> AIStatus {
        var status = AIStatus(account: account)
        guard let data = FileManager.default.contents(atPath: account.file ?? NSHomeDirectory() + "/.codex/auth.json"),
              let auth = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = auth["tokens"] as? [String: Any], let token = tokens["access_token"] as? String
        else {
            status.problem = L("Codex oturumu bulunamadı", "No Codex sign-in found")
            status.needsSignIn = true
            return status
        }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "User-Agent")
        if let account = tokens["account_id"] as? String { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        guard let json = await load(request, into: &status) else { return status }

        status.plan = (json["plan_type"] as? String)?.capitalized
        // Every object that carries "used_percent" is a window (primary = short, secondary = weekly).
        var windows: [(path: String, window: [String: Any])] = []
        collect(json, path: "", into: &windows)
        for (path, window) in windows.sorted(by: { seconds($0.window) < seconds($1.window) }) {
            guard let percent = number(window["used_percent"]) else { continue }
            var reset = date(window["reset_at"]) ?? date(window["resets_at"])
            if reset == nil, let after = number(window["reset_after_seconds"]) ?? number(window["resets_in_seconds"]) {
                reset = Date().addingTimeInterval(after)
            }
            status.limits.append(AILimit(id: "codex.\(path)", label: durationLabel(seconds(window)), used: percent / 100, resetsAt: reset,
                                         period: seconds(window) > 0 ? seconds(window) : nil))
        }
        if let last = status.limits.indices.last { status.limits[last].primary = true }
        if status.limits.isEmpty { status.problem = L("Limit bilgisi yok", "No limit data") }
        return status
    }

    private static func collect(_ value: Any, path: String, into windows: inout [(path: String, window: [String: Any])]) {
        if let dict = value as? [String: Any] {
            if dict["used_percent"] != nil {
                windows.append((path, dict))
                return
            }
            for (key, child) in dict { collect(child, path: path.isEmpty ? key : "\(path).\(key)", into: &windows) }
        } else if let list = value as? [Any] {
            for (index, child) in list.enumerated() { collect(child, path: "\(path).\(index)", into: &windows) }
        }
    }

    private static func seconds(_ window: [String: Any]) -> Double {
        number(window["limit_window_seconds"]) ?? number(window["window_minutes"]).map { $0 * 60 } ?? 0
    }

    private static func durationLabel(_ seconds: Double) -> String {
        switch seconds {
        case 0: return L("Limit", "Limit")
        case ..<86_400: return L("\(Int((seconds / 3600).rounded())) saat", "\(Int((seconds / 3600).rounded()))-hour")
        case 518_400...: return L("Haftalık", "Weekly")
        default: return L("\(Int((seconds / 86_400).rounded())) gün", "\(Int((seconds / 86_400).rounded()))-day")
        }
    }

    // MARK: Gemini

    static func gemini(_ account: AIAccount) async -> AIStatus {
        var status = AIStatus(account: account)
        guard let data = FileManager.default.contents(atPath: account.file ?? NSHomeDirectory() + "/.gemini/oauth_creds.json"),
              let creds = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = creds["access_token"] as? String
        else {
            status.problem = L("Gemini CLI oturumu bulunamadı", "No Gemini CLI sign-in found")
            status.needsSignIn = true
            return status
        }
        if let expires = number(creds["expiry_date"]), expires / 1000 < Date().timeIntervalSince1970 {
            expired(&status, tr: "Gemini CLI'yi", en: "Gemini CLI")
            return status
        }
        let base = "https://cloudcode-pa.googleapis.com/v1internal:"
        func post(_ method: String, _ body: [String: Any]) -> URLRequest {
            var request = URLRequest(url: URL(string: base + method)!, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            return request
        }
        let metadata = ["ideType": "IDE_UNSPECIFIED", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"]
        guard let assist = await load(post("loadCodeAssist", ["metadata": metadata]), into: &status) else { return status }
        status.plan = (assist["currentTier"] as? [String: Any])?["name"] as? String
        let project = (assist["cloudaicompanionProject"] as? String)
            ?? ((assist["cloudaicompanionProject"] as? [String: Any])?["id"] as? String)
        var body: [String: Any] = [:]
        if let project { body["project"] = project }
        guard let quota = await load(post("retrieveUserQuota", body), into: &status) else { return status }

        // { "buckets": [ { "modelId": "gemini-2.5-pro", "remainingFraction": 0.93, "resetTime": "…" } ] }
        var byModel: [String: AILimit] = [:]
        for bucket in quota["buckets"] as? [[String: Any]] ?? [] {
            guard let model = bucket["modelId"] as? String, let remaining = number(bucket["remainingFraction"]) else { continue }
            let limit = AILimit(id: "gemini.\(model)", label: modelLabel(model), used: 1 - remaining, resetsAt: date(bucket["resetTime"]),
                                period: 86_400)
            if (byModel[model]?.used ?? -1) < limit.used { byModel[model] = limit }
        }
        status.limits = byModel.values.sorted { $0.label < $1.label }
        if status.limits.isEmpty { status.problem = L("Limit bilgisi yok", "No limit data") }
        return status
    }

    /// "gemini-2.5-pro" → "2.5 Pro".
    private static func modelLabel(_ id: String) -> String {
        id.replacingOccurrences(of: "gemini-", with: "").split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    // MARK: Helpers

    /// Loads a JSON object, or fills `status.problem` with why it could not.
    private static func load(_ request: URLRequest, into status: inout AIStatus) async -> [String: Any]? {
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            status.problem = L("Bağlanılamadı", "Could not connect")
            return nil
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            status.needsSignIn = code == 401 || code == 403
            status.problem = code == 401 || code == 403
                ? L("Oturum geçersiz, CLI'yi bir kez aç", "Sign-in rejected, open the CLI once")
                : L("Okunamadı (HTTP \(code))", "Could not read (HTTP \(code))")
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            status.problem = L("Beklenmeyen cevap", "Unexpected response")
            return nil
        }
        return json
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: n.doubleValue
        case let s as String: Double(s)
        default: nil
        }
    }

    /// ISO 8601 (with or without fractional seconds) or epoch seconds.
    private static func date(_ value: Any?) -> Date? {
        if let seconds = number(value), seconds > 1_000_000_000 {
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
        }
        guard let text = value as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
