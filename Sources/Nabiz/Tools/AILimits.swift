// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import Foundation
import Observation
import Security

/// One usage window of an AI subscription: "5-hour 22%, resets in 2 h".
struct AILimit: Identifiable, Sendable {
    let id: String
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
    let provider: AIProvider
    var plan: String?
    var limits: [AILimit] = []
    /// Shown instead of limits when they could not be read.
    var problem: String?
    var id: String { provider.rawValue }

    /// The limit to show when there is room for one: the main window, never a per-model one.
    var headline: AILimit? { limits.first(where: \.primary) ?? limits.first }
}

/// Reads subscription limits with the sign-ins the official CLIs already keep on this Mac.
/// Tokens never leave the Mac except to their own provider, are never stored by Nabız, and are never refreshed by it.
@MainActor
@Observable
final class AILimitsStore {
    static let shared = AILimitsStore()

    private(set) var statuses: [AIStatus] = []
    private(set) var loading = false
    @ObservationIgnored private var fetchedAt: Date?

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

    /// Limits on pace to run out before they reset, with their provider.
    var burning: [(provider: AIProvider, limit: AILimit)] {
        statuses.flatMap { status in
            status.limits.filter { $0.pace?.status == .behind }.map { (status.provider, $0) }
        }
    }

    var enabled: [AIProvider] { AIProvider.allCases.filter { Prefs.bool($0.prefKey) } }

    /// Fetches again when the last result is older than `maxAge` seconds (or the enabled providers changed).
    func refreshIfNeeded(force: Bool = false, maxAge: TimeInterval = 120) {
        let providers = enabled
        guard !loading, !providers.isEmpty else {
            if providers.isEmpty { statuses = [] }
            return
        }
        if !force, let fetchedAt, Date().timeIntervalSince(fetchedAt) < maxAge,
           Set(statuses.map(\.provider)) == Set(providers) { return }
        loading = true
        Task {
            var results: [AIStatus] = []
            await withTaskGroup(of: AIStatus.self) { group in
                for provider in providers {
                    group.addTask { await AIFetch.status(for: provider) }
                }
                for await status in group { results.append(status) }
            }
            statuses = providers.compactMap { provider in results.first { $0.provider == provider } }.map(withPace)
            fetchedAt = Date()
            loading = false
        }
    }
}

// MARK: - Fetching

private enum AIFetch {
    static func status(for provider: AIProvider) async -> AIStatus {
        switch provider {
        case .claude: await claude()
        case .codex: await codex()
        case .gemini: await gemini()
        }
    }

    // MARK: Claude

    static func claude() async -> AIStatus {
        var status = AIStatus(provider: .claude)
        let credentials = claudeCredentials()
        guard let oauth = credentials.oauth, let token = oauth["accessToken"] as? String else {
            status.problem = credentials.error ?? L("Claude Code oturumu bulunamadı", "No Claude Code sign-in found")
            return status
        }
        if let expires = number(oauth["expiresAt"]), expires / 1000 < Date().timeIntervalSince1970 {
            status.problem = L("Oturum süresi doldu, Claude Code'u bir kez aç", "Sign-in expired, open Claude Code once")
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
            status.plan = await claudePlan(token: token)
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
        status.plan = await claudePlan(token: token)
        return status
    }

    /// The plan as Anthropic's server reports it now. The token's own "subscriptionType" can be out of date
    /// (it is set when the CLI signs in), so it is never used; with no server answer the plan is simply not shown.
    private static func claudePlan(token: String) async -> String? {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/profile")!, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        var ignored = AIStatus(provider: .claude)
        guard let json = await load(request, into: &ignored) else { return nil }
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
    private static func claudeCredentials() -> (oauth: [String: Any]?, error: String?) {
        let service = "Claude Code-credentials"
        var error: String?
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
        if let oauth = oauth(from: FileManager.default.contents(atPath: NSHomeDirectory() + "/.claude/.credentials.json")) {
            return (oauth, nil)
        }
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

    static func codex() async -> AIStatus {
        var status = AIStatus(provider: .codex)
        guard let data = FileManager.default.contents(atPath: NSHomeDirectory() + "/.codex/auth.json"),
              let auth = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = auth["tokens"] as? [String: Any], let token = tokens["access_token"] as? String
        else {
            status.problem = L("Codex oturumu bulunamadı", "No Codex sign-in found")
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

    static func gemini() async -> AIStatus {
        var status = AIStatus(provider: .gemini)
        guard let data = FileManager.default.contents(atPath: NSHomeDirectory() + "/.gemini/oauth_creds.json"),
              let creds = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = creds["access_token"] as? String
        else {
            status.problem = L("Gemini CLI oturumu bulunamadı", "No Gemini CLI sign-in found")
            return status
        }
        if let expires = number(creds["expiry_date"]), expires / 1000 < Date().timeIntervalSince1970 {
            status.problem = L("Oturum süresi doldu, Gemini CLI'yi bir kez aç", "Sign-in expired, open Gemini CLI once")
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
