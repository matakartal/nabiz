// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import NaturalLanguage
import AppKit
import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Who answers. The CLIs use the subscription you are already signed in to on this Mac (Claude Code, Codex,
/// Gemini CLI); Nabız only runs them, it never reads or sends their sign-in. The on-device model is Apple's,
/// free, offline and private.
enum AIEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto, claude, codex, grok, gemini, onDevice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: L("Otomatik", "Automatic")
        case .claude: "Claude"
        case .codex: "Codex"
        case .grok: "Grok"
        case .gemini: "Gemini"
        case .onDevice: L("Apple (cihaz içi)", "Apple (on-device)")
        }
    }

    /// Claude and Codex look at attached images themselves; the others get the text read from them.
    var seesImages: Bool { self == .claude || self == .codex }
    /// Claude, Codex and Grok can search the web themselves.
    var searchesWeb: Bool { self == .claude || self == .codex || self == .grok }

    /// For "Ask Claude…".
    var shortName: String { self == .onDevice ? "Apple" : title }

    /// The command it runs; nil for Apple's model.
    var command: String? {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .grok: "grok"
        case .gemini: "gemini"
        case .auto, .onDevice: nil
        }
    }

    static var chosen: AIEngine { AIEngine(rawValue: Prefs.string(Prefs.aiEngine)) ?? .auto }
    /// Real engines, best first: "Automatic" takes the first one that works here.
    static let order: [AIEngine] = [.claude, .codex, .grok, .gemini, .onDevice]

    /// The model picked for this engine in Settings ("" = the engine's own default).
    var chosenModel: String { UserDefaults.standard.string(forKey: "ai.model.\(rawValue)") ?? "" }

    func setChosenModel(_ model: String) { UserDefaults.standard.set(model, forKey: "ai.model.\(rawValue)") }
}

/// One reasoning level an engine offers ("medium"), as its own app shows it.
struct AIEffortLevel: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    var detail = ""
    var recommended = false
    /// "3.5× or more usage".
    var warning: String?
}

extension AIEngine {
    /// The level picked for this engine ("" = the engine's own default).
    var chosenEffort: String { UserDefaults.standard.string(forKey: "ai.effort.\(rawValue)") ?? "" }

    func setChosenEffort(_ level: String) { UserDefaults.standard.set(level, forKey: "ai.effort.\(rawValue)") }
}

/// One model an engine offers; an empty id means "the CLI's default".
struct AIModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    var detail = ""
}

/// Finds the CLIs and their models once, with your login shell's PATH (Homebrew, npm and ~/.local live there,
/// not in an app's PATH).
@MainActor
@Observable
final class AIEngines {
    static let shared = AIEngines()
    private(set) var paths: [AIEngine: String] = [:]
    private(set) var searched = false
    private(set) var codexModels: [AIModelOption] = []
    private(set) var geminiModels: [AIModelOption] = []
    private(set) var grokModels: [AIModelOption] = []
    private(set) var grokDefault = ""
    /// Codex's reasoning levels and recommended one, by model.
    private(set) var codexEfforts: [String: (levels: [AIEffortLevel], recommended: String)] = [:]
    /// The model in ~/.codex/config.toml, used when you keep Codex's default.
    private(set) var codexDefault = ""
    @ObservationIgnored private(set) var shellPath = ""
    @ObservationIgnored private var searching = false

    func refreshIfNeeded(force: Bool = false) {
        guard (!searched || force) && !searching else { return }
        searching = true
        Task {
            let found = await Task.detached(priority: .utility) { () -> Found in
                let path = Self.loginPath()
                var found = Found(path: path)
                for engine in AIEngine.order {
                    guard let command = engine.command else { continue }
                    for dir in path.split(separator: ":") {
                        let candidate = "\(dir)/\(command)"
                        if FileManager.default.isExecutableFile(atPath: candidate) { found.paths[engine] = candidate; break }
                    }
                }
                if found.paths[.codex] != nil { (found.codexModels, found.codexDefault, found.codexEfforts) = Self.readCodexModels() }
                if let gemini = found.paths[.gemini] { found.geminiModels = Self.readGeminiModels(gemini, path: path) }
                if let grok = found.paths[.grok] { (found.grokModels, found.grokDefault) = Self.readGrokModels(grok, path: path) }
                return found
            }.value
            shellPath = found.path
            paths = found.paths
            codexModels = found.codexModels
            codexDefault = found.codexDefault
            codexEfforts = found.codexEfforts
            geminiModels = found.geminiModels
            grokModels = found.grokModels
            grokDefault = found.grokDefault
            searched = true
            searching = false
        }
    }

    private struct Found: Sendable {
        var path: String
        var paths: [AIEngine: String] = [:]
        var codexModels: [AIModelOption] = []
        var codexDefault = ""
        var codexEfforts: [String: (levels: [AIEffortLevel], recommended: String)] = [:]
        var geminiModels: [AIModelOption] = []
        var grokModels: [AIModelOption] = []
        var grokDefault = ""
    }

    nonisolated private static func loginPath() -> String {
        let fallback = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(NSHomeDirectory())/.local/bin"
        guard let path = run("/bin/zsh", ["-lc", "print -r -- $PATH"], path: nil)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return fallback }
        return path + ":" + fallback
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String], path: String?) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let path {
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = path
            process.environment = environment
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { if process.isRunning { process.terminate() } }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// How many tokens a Codex model can hold, from its cache (`context_window`).
    nonisolated static func codexWindow(_ slug: String) -> Int? {
        let file = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["models"] as? [[String: Any]] else { return nil }
        return list.first { $0["slug"] as? String == slug }?["context_window"] as? Int
    }

    /// Codex keeps the models your plan offers in ~/.codex/models_cache.json.
    nonisolated private static func readCodexModels() -> ([AIModelOption], String, [String: (levels: [AIEffortLevel], recommended: String)]) {
        let home = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
        var models: [AIModelOption] = []
        var efforts: [String: (levels: [AIEffortLevel], recommended: String)] = [:]
        if let data = try? Data(contentsOf: home.appendingPathComponent("models_cache.json")),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let list = object["models"] as? [[String: Any]] {
            let shown = list.filter { ($0["visibility"] as? String) == "list" }
                .sorted { ($0["priority"] as? Int ?? 99) < ($1["priority"] as? Int ?? 99) }
            models = shown.compactMap { model in
                guard let slug = model["slug"] as? String else { return nil }
                return AIModelOption(id: slug, title: model["display_name"] as? String ?? slug, detail: model["description"] as? String ?? "")
            }
            for model in shown {
                guard let slug = model["slug"] as? String, let levels = model["supported_reasoning_levels"] as? [[String: Any]] else { continue }
                let recommended = model["default_reasoning_level"] as? String ?? "medium"
                efforts[slug] = (levels.compactMap { level in
                    guard let id = level["effort"] as? String else { return nil }
                    return AIEffortLevel(id: id, title: effortTitle(id), detail: level["description"] as? String ?? "", recommended: id == recommended)
                }, recommended)
            }
        }
        var configured = ""
        if let config = try? String(contentsOf: home.appendingPathComponent("config.toml"), encoding: .utf8) {
            for line in config.split(separator: "\n") where line.hasPrefix("model") {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, parts[0] == "model" { configured = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            }
        }
        return (models, configured, efforts)
    }

    /// `grok models`: "Default model: grok-4.7", then "  * grok-4.7 (default)" and "  - grok-4.6" lines.
    nonisolated private static func readGrokModels(_ grok: String, path: String) -> ([AIModelOption], String) {
        guard let output = run(grok, ["models"], path: path) else { return ([], "") }
        var models: [AIModelOption] = []
        var fallback = ""
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Default model:") { fallback = trimmed.dropFirst("Default model:".count).trimmingCharacters(in: .whitespaces) }
            guard trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") else { continue }
            let slug = trimmed.dropFirst(2).split(separator: " ").first.map(String.init) ?? ""
            if !slug.isEmpty { models.append(AIModelOption(id: slug, title: slug.replacingOccurrences(of: "grok-", with: "Grok ").replacingOccurrences(of: "-", with: " ").capitalized)) }
        }
        return (models, fallback)
    }

    /// "xhigh" → "Extra", as the apps say it.
    nonisolated static func effortTitle(_ id: String) -> String {
        switch id {
        case "minimal": L("En az", "Minimal")
        case "low": L("Düşük", "Low")
        case "medium": L("Orta", "Medium")
        case "high": L("Yüksek", "High")
        case "xhigh": L("Ekstra", "Extra")
        case "max": L("Maks", "Max")
        default: id.capitalized
        }
    }

    /// The reasoning levels an engine (and model) offers; empty when it has no such choice.
    func efforts(for engine: AIEngine, model: String) -> [AIEffortLevel] {
        switch engine {
        case .claude:
            return ["low", "medium", "high", "xhigh", "max"].map { id in
                AIEffortLevel(id: id, title: Self.effortTitle(id), recommended: id == "medium",
                              warning: id == "max" ? L("3,5× ya da daha fazla kullanım", "3.5× or more usage") : nil)
            }
        case .codex:
            let slug = model.isEmpty ? codexDefault : model
            return codexEfforts[slug]?.levels ?? codexEfforts.values.first?.levels ?? []
        case .grok:
            return ["low", "medium", "high", "xhigh"].map { AIEffortLevel(id: $0, title: Self.effortTitle($0)) }
        case .auto, .gemini, .onDevice:
            return []
        }
    }

    /// The level that applies: the one picked if the model offers it, otherwise the provider's recommendation.
    func effectiveEffort(for engine: AIEngine, model: String) -> String {
        let levels = efforts(for: engine, model: model)
        let chosen = engine.chosenEffort
        if levels.contains(where: { $0.id == chosen }) { return chosen }
        return levels.first(where: \.recommended)?.id ?? ""
    }

    /// `gemini models list`: "gemini-2.5-pro (gemini-2.5-pro)" lines.
    nonisolated private static func readGeminiModels(_ gemini: String, path: String) -> [AIModelOption] {
        guard let output = run(gemini, ["models", "list"], path: path) else { return [] }
        return output.split(separator: "\n").compactMap { line -> AIModelOption? in
            guard !line.hasPrefix(" "), let open = line.lastIndex(of: "("), line.hasSuffix(")") else { return nil }
            let slug = line[..<open].trimmingCharacters(in: .whitespaces)
            guard !slug.isEmpty, !slug.contains(" "), slug != "auto" else { return nil }
            return AIModelOption(id: slug, title: slug)
        }
    }

    func isAvailable(_ engine: AIEngine) -> Bool {
        switch engine {
        case .auto: resolved != nil
        case .onDevice: OnDeviceAI.problem == nil
        default: paths[engine] != nil
        }
    }

    /// Why an engine can't be used here, in plain words; nil when it can.
    func problem(_ engine: AIEngine) -> String? {
        switch engine {
        case .auto: resolved == nil ? L("Kurulu bir AI yok", "No AI is set up") : nil
        case .onDevice: OnDeviceAI.problem
        default: paths[engine] == nil ? L("Kurulu değil", "Not installed") : nil
        }
    }

    /// The engine "Automatic" stands for; nil until the CLIs have been looked for, so it never guesses Apple too early.
    var resolved: AIEngine? { searched ? AIEngine.order.first { isAvailable($0) } : nil }

    /// The engine that will answer: the one picked, or, when it isn't set up on this Mac, the first one that is.
    func resolve(_ engine: AIEngine) -> AIEngine? {
        if engine == .auto { return resolved }
        if searched, !isAvailable(engine) { return resolved }
        return engine
    }

    // MARK: Provider defaults

    /// The provider's own default model by name, as its CLI last reported it ("Opus 5.5"), or from its settings.
    func defaultModelName(_ engine: AIEngine) -> String? {
        switch engine {
        case .claude:
            if let configured = Self.claudeConfiguredModel { return Self.seen(engine, configured) ?? Self.claudeName(configured) }
            return Self.seen(engine, "")
        case .codex:
            return codexDefault.isEmpty ? nil : (codexModels.first { $0.id == codexDefault }?.title ?? codexDefault)
        case .grok:
            return grokDefault.isEmpty ? nil : (grokModels.first { $0.id == grokDefault }?.title ?? grokDefault)
        case .gemini:
            return L("Otomatik", "Auto")
        case .auto, .onDevice:
            return nil
        }
    }

    /// The model in ~/.claude/settings.json, when you set one in Claude Code.
    nonisolated static var claudeConfiguredModel: String? {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = object["model"] as? String, !model.isEmpty else { return nil }
        return model
    }

    /// Remembers which real model an alias (or the default, "") turned out to be, so menus can say "Opus 5.5".
    func remember(_ actual: String, for asked: String, engine: AIEngine) {
        guard engine == .claude, !actual.isEmpty else { return }
        let name = Self.claudeName(actual)
        let key = "ai.seen.\(engine.rawValue).\(asked)"
        if UserDefaults.standard.string(forKey: key) != name {
            UserDefaults.standard.set(name, forKey: key)
            seenVersion += 1
        }
    }

    /// Bumped when a model name is learned, so menus update.
    private(set) var seenVersion = 0

    nonisolated static func seen(_ engine: AIEngine, _ asked: String) -> String? {
        UserDefaults.standard.string(forKey: "ai.seen.\(engine.rawValue).\(asked)")
    }

    /// What can be picked for an engine; the first one is its default.
    func models(for engine: AIEngine) -> [AIModelOption] {
        _ = seenVersion
        let provider = defaultModelName(engine)
        let name = engine == .gemini ? L("Otomatik", "Auto") : L("Varsayılan", "Default")
        var list = [AIModelOption(id: "", title: provider.map { engine == .gemini ? $0 : "\(name) (\($0))" } ?? name,
                                  detail: L("\(engine.title) ne öneriyorsa", "Whatever \(engine.title) recommends"))]
        switch engine {
        case .claude:
            list += ["fable", "opus", "sonnet", "haiku"].map { alias in
                AIModelOption(id: alias, title: Self.seen(.claude, alias) ?? alias.prefix(1).uppercased() + alias.dropFirst())
            }
        case .codex:
            list += codexModels
        case .grok:
            list += grokModels
        case .gemini:
            list += geminiModels
        case .auto, .onDevice:
            break
        }
        return list
    }

    /// A model id as people read it: "claude-opus-5-5" → "Opus 5.5", "gpt-6-luna" → "GPT-6-Luna".
    func displayName(_ model: String, engine: AIEngine) -> String {
        if engine == .onDevice { return L("Cihaz içi model", "On-device model") }
        if model.isEmpty { return defaultModelName(engine) ?? engine.title }
        switch engine {
        case .claude: return Self.seen(.claude, model) ?? Self.claudeName(model)
        case .codex: return codexModels.first { $0.id == model }?.title ?? model
        case .gemini: return geminiModels.first { $0.id == model }?.title ?? model
        case .grok: return grokModels.first { $0.id == model }?.title ?? model
        case .auto, .onDevice: return model
        }
    }

    nonisolated static func claudeName(_ model: String) -> String {
        let parts = model.replacingOccurrences(of: "claude-", with: "").split(separator: "-").map(String.init)
        guard let family = parts.first else { return model }
        let version = parts.dropFirst().filter { $0.count <= 2 && Int($0) != nil }.joined(separator: ".")
        return family.prefix(1).uppercased() + family.dropFirst() + (version.isEmpty ? "" : " " + version)
    }
}

// MARK: - Requests

/// Everything one answer needs.
struct AIRequest: Sendable {
    var engine: AIEngine
    var model = ""
    /// The reasoning level to ask for ("high"); "" leaves it to the CLI.
    var effort = ""
    var system: String
    var prompt: String
    /// For the on-device model, which keeps its own memory of a chat: the chat, its newest message alone,
    /// and how many answers came before it.
    var chatID: UUID?
    var latest = ""
    var answered = 0
    /// Images for the newest message, for the AIs that can see them.
    var images: [URL] = []
    /// Claude keeps the chat itself: a new session with this id (`prompt` is then the whole chat), or, with `resume`,
    /// the one it already has (`prompt` is only the newest message, `fallback` the whole chat in case it was lost).
    var session: String?
    var resume = false
    var fallback = ""
    /// It may search the web (Claude, Codex, Grok).
    var web = false
}

/// An answer so far: the CLIs report the whole text each time, so updates never need ordering.
struct AIProgress: Sendable, Equatable {
    var text = ""
    var thinking = ""
    /// The model that actually answered, when the CLI says ("claude-opus-5-5").
    var model: String?
    /// How full the conversation is after this answer, when the CLI says.
    var usage: AIUsage?
    /// Searching the web right now.
    var searching = false
    /// The plan's limit, when the CLI reports it during the answer (Claude does).
    var limit: AILiveLimit?
}

/// The chat's size for the model: tokens it now holds, out of how many it can, and the answer's price at API rates.
struct AIUsage: Codable, Equatable, Sendable {
    var tokens: Int
    var window: Int?
    var cost: Double?

    var fraction: Double? { window.map { $0 > 0 ? min(1, Double(tokens) / Double($0)) : 0 } }
}

/// What Claude says about the plan's limit while it answers: still fine, getting close, or used up until `resetsAt`.
struct AILiveLimit: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case allowed, warning, rejected }
    var status: Status
    /// "five_hour", "seven_day"…
    var kind: String
    var resetsAt: Date?
    /// 0...1 when given.
    var used: Double?

    var label: String {
        switch kind {
        case "five_hour": L("5 saatlik limit", "5-hour limit")
        case "seven_day": L("Haftalık limit", "Weekly limit")
        case "seven_day_opus": L("Haftalık Opus limiti", "Weekly Opus limit")
        case "seven_day_sonnet": L("Haftalık Sonnet limiti", "Weekly Sonnet limit")
        default: L("Limit", "Limit")
        }
    }
}

struct AIError: Error, Equatable {
    let message: String
    /// The CLI didn't know a flag: an older version, worth one more try with the basic ones.
    var unknownOption = false
    /// Claude couldn't find the session to resume.
    var sessionLost: Bool { message.localizedCaseInsensitiveContains("No conversation found") }
    init(_ message: String, unknownOption: Bool = false) {
        self.message = message
        self.unknownOption = unknownOption
    }
}

/// Runs one request and streams its answer.
enum AIRunner {
    @MainActor static func stream(_ request: AIRequest) -> AsyncThrowingStream<AIProgress, Error> {
        if request.engine == .onDevice { return OnDeviceAI.stream(request) }
        let path = AIEngines.shared.paths[request.engine]
        let shellPath = AIEngines.shared.shellPath
        var request = request
        // Codex's default comes from your config, which the runner skips; ask for it by name.
        if request.engine == .codex && request.model.isEmpty { request.model = AIEngines.shared.codexDefault }
        return AsyncThrowingStream { [request] continuation in
            let task = Task.detached {
                do {
                    guard let path else { throw AIError(L("\(request.engine.title) kurulu değil", "\(request.engine.title) isn't installed")) }
                    do {
                        try await run(request, path: path, shellPath: shellPath, compatible: false, continuation: continuation)
                    } catch let error as AIError where error.unknownOption {
                        try await run(request, path: path, shellPath: shellPath, compatible: true, continuation: continuation)
                    } catch let error as AIError where request.resume && error.sessionLost {
                        // Claude no longer has the chat (cleaned up after a month, or removed): start it again, whole.
                        var fresh = request
                        fresh.resume = false
                        fresh.prompt = request.fallback
                        try await run(fresh, path: path, shellPath: shellPath, compatible: false, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static let workFolder: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Nabiz").appendingPathComponent("ai")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func arguments(_ request: AIRequest, compatible: Bool) -> [String] {
        var list: [String]
        switch request.engine {
        case .claude:
            // No tools, so it only writes. Its own chat prompt replaces Claude Code's coding one, so it answers like
            // the Claude app; safe mode skips your CLAUDE.md, hooks and plugins.
            // Only the web tools when web search is on (no files, no commands); none otherwise.
            list = request.web ? ["-p", "--tools", "WebSearch,WebFetch", "--allowedTools", "WebSearch,WebFetch"] : ["-p", "--tools", ""]
            if let session = request.session {
                list += request.resume ? ["--resume", session] : ["--session-id", session]
            } else {
                list.append("--no-session-persistence")
            }
            list += ["--output-format", "stream-json", "--include-partial-messages", "--verbose", "--system-prompt", request.system]
            if !compatible { list.append("--safe-mode") }
            if !request.model.isEmpty { list += ["--model", request.model] }
            if !request.effort.isEmpty, !compatible { list += ["--effort", request.effort] }
            if !request.images.isEmpty { list += ["--input-format", "stream-json"] }
        case .codex:
            list = (request.web ? ["--search"] : []) + ["exec"] + request.images.flatMap { ["-i", $0.path] } + ["--json", "--skip-git-repo-check", "--sandbox", "read-only", "--color", "never"]
            // No browser, computer control, apps, plugins, sub-agents or memories: it answers, it doesn't act.
            if !compatible {
                list += ["--ephemeral", "--ignore-user-config", "--ignore-rules"]
                for feature in ["apps", "plugins", "browser_use", "browser_use_external", "in_app_browser", "computer_use",
                                "multi_agent", "multi_agent_v2", "memories", "image_generation"] {
                    list += ["--disable", feature]
                }
            }
            if !request.model.isEmpty { list += ["-m", request.model] }
            if !request.effort.isEmpty { list += ["-c", "model_reasoning_effort=\"\(request.effort)\""] }
            list.append("-")
        case .grok:
            // One turn, read-only, no web or helpers: it only writes. The prompt comes from a file (Grok has no stdin).
            list = ["--prompt-file", grokPromptFile(request).path, "--output-format", "streaming-json", "--max-turns", "1",
                    "--permission-mode", "plan"] + (request.web ? [] : ["--disable-web-search"])
                + ["--no-subagents", "--system-prompt-override", request.system]
            if !request.model.isEmpty { list += ["-m", request.model] }
            if !request.effort.isEmpty { list += ["--reasoning-effort", request.effort] }
        case .gemini:
            list = ["-p", " ", "--approval-mode", "plan", "-o", "text"]
            if !compatible { list.append("--skip-trust") }
            if !request.model.isEmpty { list += ["-m", request.model] }
        case .auto, .onDevice:
            list = []
        }
        return list
    }

    /// What goes in on stdin: Claude gets the system prompt as a flag, the others read it first; Grok reads a file.
    static func input(_ request: AIRequest) -> String {
        switch request.engine {
        case .claude: request.images.isEmpty ? request.prompt : AIImages.claudeMessage(prompt: request.prompt, images: request.images)
        case .grok: ""
        default: request.system + "\n\n" + request.prompt
        }
    }

    /// Grok's prompt file, one per request, removed once it has run.
    static func grokPromptFile(_ request: AIRequest) -> URL {
        let url = workFolder.appendingPathComponent("grok-\(UUID().uuidString).txt")
        // Readable by this user only.
        FileManager.default.createFile(atPath: url.path, contents: Data(request.prompt.utf8), attributes: [.posixPermissions: 0o600])
        return url
    }

    /// Prompt files left by a crash or a force-quit (they hold your words): gone at launch.
    static func sweepPromptFiles() {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: workFolder.path)) ?? [] where name.hasPrefix("grok-") {
            try? FileManager.default.removeItem(at: workFolder.appendingPathComponent(name))
        }
    }

    /// Asks a CLI to stop, and makes sure it does a few seconds later.
    nonisolated static func end(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private static func run(_ request: AIRequest, path: String, shellPath: String, compatible: Bool,
                            continuation: AsyncThrowingStream<AIProgress, Error>.Continuation) async throws {
        // A closed pipe (a CLI that quits before reading the question) must not end Nabız.
        signal(SIGPIPE, SIG_IGN)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments(request, compatible: compatible)
        // Grok's prompt file holds your words; it goes however this ends.
        defer {
            if request.engine == .grok, let index = process.arguments?.firstIndex(of: "--prompt-file"),
               let list = process.arguments, index + 1 < list.count {
                let file = list[index + 1]
                try? FileManager.default.removeItem(atPath: file)
            }
        }
        // An empty folder, so nothing it might look at is yours.
        process.currentDirectoryURL = workFolder
        var environment = ProcessInfo.processInfo.environment
        if !shellPath.isEmpty { environment["PATH"] = shellPath }
        environment["NO_COLOR"] = "1"
        environment["GEMINI_CLI_TRUST_WORKSPACE"] = "true"
        process.environment = environment
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let parser = StreamParser(engine: request.engine)
        let errorText = ErrorBuffer()
        let timer = ErrorBuffer()
        // One queue reads and parses, so a late chunk can never land after the final read.
        let reading = DispatchQueue(label: "nabiz.ai.read")
        output.fileHandleForReading.readabilityHandler = { handle in
            reading.sync {
                if parser.feed(handle.availableData) { continuation.yield(parser.progress) }
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in errorText.append(handle.availableData) }

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { finished in done.resume(returning: finished.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    done.resume(throwing: AIError(L("\(request.engine.title) açılamadı", "Couldn't start \(request.engine.title)")))
                    return
                }
                // Stopped while it was starting: end it now.
                if Task.isCancelled { process.terminate() }
                let question = Data(Self.input(request).utf8)
                let writer = input.fileHandleForWriting
                DispatchQueue.global(qos: .userInitiated).async {
                    try? writer.write(contentsOf: question)
                    try? writer.close()
                }
                // A stuck CLI shouldn't hang here forever.
                DispatchQueue.global().asyncAfter(deadline: .now() + 300) {
                    if process.isRunning {
                        timer.append(Data("timeout".utf8))
                        Self.end(process)
                    }
                }
            }
        } onCancel: {
            // Before it started there's nothing to end (and ending it then would crash).
            if process.isRunning { Self.end(process) }
        }
        errors.fileHandleForReading.readabilityHandler = nil
        // What was still in the pipes when it finished.
        reading.sync {
            output.fileHandleForReading.readabilityHandler = nil
            if let rest = try? output.fileHandleForReading.readToEnd() { parser.feed(rest) }
        }
        if let rest = try? errors.fileHandleForReading.readToEnd() { errorText.append(rest) }
        try Task.checkCancellation()

        let progress = parser.progress
        let timedOut = !timer.text.isEmpty
        if !progress.text.isEmpty {
            continuation.yield(progress)
            // Some text, then it broke off: keep the text, but say it isn't the whole answer.
            if timedOut {
                throw AIError(L("5 dakikada bitmediği için durduruldu; cevap yarım kalmış olabilir",
                                "Stopped after 5 minutes; the answer may be cut short"))
            }
            if parser.failure != nil || status != 0 {
                throw AIError(L("Cevap yarıda kesildi: ", "The answer was cut off: ")
                              + explain(parser.failure ?? errorText.text, engine: request.engine))
            }
            return
        }
        if timedOut {
            throw AIError(L("\(request.engine.title) 5 dakikada cevap vermedi", "\(request.engine.title) didn't answer within 5 minutes"))
        }
        let problem = parser.failure ?? errorText.text
        if status != 0 && !compatible && (problem.contains("unknown option") || problem.contains("Unknown argument") || problem.contains("unexpected argument")) {
            throw AIError(problem, unknownOption: true)
        }
        if parser.failure != nil || status != 0 { throw AIError(explain(problem, engine: request.engine)) }
        throw AIError(L("Boş cevap geldi", "The answer came back empty"))
    }

    /// An HTTP status as a whole number ("429", "status: 429"), not inside "14290 ms".
    static func hasStatus(_ text: String, _ code: Int) -> Bool {
        text.range(of: "(?<![0-9])\(code)(?![0-9])", options: .regularExpression) != nil
    }

    /// A CLI's error in plain words.
    static func explain(_ raw: String, engine: AIEngine) -> String {
        let text = raw.lowercased()
        if text.contains("ineligibletier") || text.contains("no longer supported") {
            return L("Google bu hesapta Gemini CLI'ı artık desteklemiyor", "Google no longer supports Gemini CLI for this account")
        }
        if text.contains("not logged in") || text.contains("/login") || text.contains("login required") || text.contains("please login") || text.contains("log in") || text.contains("sign in")
            || text.contains("unauthorized") || text.contains("authenticat") || Self.hasStatus(text, 401) {
            return L("\(engine.title) oturumu yok; Terminal'de \(engine.command ?? "") yazıp bir kez giriş yap",
                     "\(engine.title) isn't signed in; type \(engine.command ?? "") in Terminal and sign in once")
        }
        if text.contains("rate limit") || text.contains("usage limit") || text.contains("quota exceeded")
            || text.contains("exceeded your") || Self.hasStatus(text, 429) {
            return L("\(engine.title) limiti doldu, biraz sonra dene", "\(engine.title) limit reached, try again later")
        }
        if text.contains("model") && (text.contains("not found") || text.contains("not available") || text.contains("invalid") || text.contains("not supported")) {
            return L("Bu model hesabında yok; başka bir model seç", "This model isn't available on your plan; pick another one")
        }
        let line = raw.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty && !$0.hasPrefix("at ") && !$0.lowercased().hasPrefix("hook") } ?? ""
        return line.isEmpty ? L("\(engine.title) cevap veremedi", "\(engine.title) couldn't answer") : String(line.prefix(200))
    }
}

/// Gathers a CLI's error output as it comes (it may be read from any thread).
private final class ErrorBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ more: Data) {
        lock.lock(); defer { lock.unlock() }
        if data.count < 65_536 { data.append(more) }
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Turns a CLI's output into answer text as it arrives: Claude's and Codex's JSON lines, Gemini's plain text.
/// Holds the whole answer so far, so late updates can't lose text.
final class StreamParser: @unchecked Sendable {
    private let engine: AIEngine
    private let lock = NSLock()
    private var buffer = Data()
    private var streamed = false
    private var _progress = AIProgress()
    private var _failure: String?
    /// Codex items by id, in the order they came: its messages and its reasoning summaries.
    private var items: [(id: String, kind: String, text: String)] = []

    init(engine: AIEngine) { self.engine = engine }

    var progress: AIProgress { lock.lock(); defer { lock.unlock() }; return _progress }
    var failure: String? { lock.lock(); defer { lock.unlock() }; return _failure }

    /// Reads more output; true when the answer changed.
    @discardableResult func feed(_ data: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !data.isEmpty else { return false }
        if engine == .gemini {
            // Plain text, read in chunks that can split a letter (ç, ş, ğ): decode only whole characters.
            buffer.append(data)
            var end = buffer.count
            while end > max(buffer.count - 3, 0), String(data: buffer.prefix(end), encoding: .utf8) == nil { end -= 1 }
            if let text = String(data: buffer.prefix(end), encoding: .utf8) {
                _progress.text += text
                buffer.removeFirst(end)
            } else {
                // Not UTF-8 at all: show what there is rather than nothing.
                _progress.text += String(decoding: buffer, as: UTF8.self)
                buffer.removeAll()
            }
            return true
        }
        buffer.append(data)
        // A line that never ends (a broken CLI) mustn't grow without bound.
        if buffer.count > 32 << 20, buffer.firstIndex(of: 0x0A) == nil { buffer.removeAll() }
        var changed = false
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            let updated = switch engine {
            case .claude: claude(object)
            case .grok: grok(object)
            default: codex(object)
            }
            if updated { changed = true }
        }
        return changed
    }

    private func claude(_ object: [String: Any]) -> Bool {
        switch object["type"] as? String {
        case "system":
            if let model = object["model"] as? String, _progress.model != model {
                _progress.model = model
                return true
            }
        case "stream_event":
            guard let event = object["event"] as? [String: Any] else { return false }
            if event["type"] as? String == "content_block_start", let block = event["content_block"] as? [String: Any],
               let kind = block["type"] as? String, kind == "server_tool_use" || kind == "tool_use" {
                _progress.searching = true
                return true
            }
            if event["type"] as? String == "content_block_start", let block = event["content_block"] as? [String: Any],
               block["type"] as? String == "text", !_progress.text.isEmpty, !_progress.text.hasSuffix("\n") {
                // A second text block (after thinking or a pause) starts a new paragraph.
                _progress.text += "\n\n"
                return true
            }
            guard let delta = event["delta"] as? [String: Any] else { return false }
            switch delta["type"] as? String {
            case "text_delta":
                _progress.text += delta["text"] as? String ?? ""
                _progress.searching = false
                streamed = true
                return true
            case "thinking_delta":
                _progress.thinking += delta["thinking"] as? String ?? ""
                return true
            default:
                return false
            }
        case "rate_limit_event":
            guard let info = object["rate_limit_info"] as? [String: Any] else { return false }
            let status: AILiveLimit.Status = switch info["status"] as? String {
            case "rejected": .rejected
            case "allowed_warning": .warning
            default: .allowed
            }
            let kind = info["rateLimitType"] as? String ?? ""
            let windows = info["unifiedWindows"] as? [String: Any]
            let used = (windows?[kind] as? [String: Any])?["utilization"] as? Double ?? info["utilization"] as? Double
            let reset = (info["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
            _progress.limit = AILiveLimit(status: status, kind: kind, resetsAt: reset, used: used)
            return true
        case "result":
            if let usage = object["usage"] as? [String: Any] {
                // What the chat holds now: the last request's input (fresh, cached and newly cached) plus the answer.
                let last = (usage["iterations"] as? [[String: Any]])?.last { $0["type"] as? String == "message" } ?? usage
                let tokens = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"]
                    .reduce(0) { $0 &+ max(last[$1] as? Int ?? 0, 0) }
                let models = object["modelUsage"] as? [String: [String: Any]]
                let window = models?.values.compactMap { $0["contextWindow"] as? Int }.max()
                _progress.usage = AIUsage(tokens: tokens, window: window, cost: object["total_cost_usd"] as? Double)
            }
            let result = object["result"] as? String ?? ""
            if object["is_error"] as? Bool == true {
                _failure = result.isEmpty ? (object["subtype"] as? String ?? "error") : result
            } else if !streamed || _progress.text.isEmpty {
                _progress.text = result
                return true
            }
        default:
            break
        }
        return false
    }

    /// Grok's streaming JSON: {"type":"text","data":"…"}, thinking as "thinking"/"reasoning", then "end" or "error".
    private func grok(_ object: [String: Any]) -> Bool {
        let data = object["data"] as? String ?? object["text"] as? String ?? ""
        switch object["type"] as? String {
        case "text":
            _progress.text += data
            return !data.isEmpty
        case "thinking", "reasoning", "thought":
            _progress.thinking += data
            return !data.isEmpty
        case "error":
            _failure = object["message"] as? String ?? (object["error"] as? [String: Any])?["message"] as? String ?? (data.isEmpty ? "error" : data)
        case "end":
            if let reason = object["stopReason"] as? String, reason != "end_turn", reason != "max_turns", _progress.text.isEmpty {
                _failure = reason
            }
        default:
            break
        }
        return false
    }

    private func codex(_ object: [String: Any]) -> Bool {
        switch object["type"] as? String {
        case "item.started", "item.updated", "item.completed":
            guard let item = object["item"] as? [String: Any], let kind = item["type"] as? String else { return false }
            if kind == "web_search" {
                _progress.searching = object["type"] as? String != "item.completed"
                return true
            }
            guard kind == "agent_message" || kind == "reasoning" else { return false }
            let id = item["id"] as? String ?? UUID().uuidString
            let text = item["text"] as? String ?? ""
            if let index = items.firstIndex(where: { $0.id == id }) { items[index].text = text } else { items.append((id, kind, text)) }
            _progress.text = items.filter { $0.kind == "agent_message" && !$0.text.isEmpty }.map(\.text).joined(separator: "\n\n")
            _progress.thinking = items.filter { $0.kind == "reasoning" && !$0.text.isEmpty }.map(\.text).joined(separator: "\n\n")
            return true
        case "turn.completed":
            // Codex reads the whole chat each turn, so its input is how full the chat is.
            if let usage = object["usage"] as? [String: Any] {
                let tokens = max(usage["input_tokens"] as? Int ?? 0, 0) &+ max(usage["output_tokens"] as? Int ?? 0, 0)
                _progress.usage = AIUsage(tokens: tokens)
                return true
            }
        case "turn.failed":
            _failure = (object["error"] as? [String: Any])?["message"] as? String ?? "failed"
        case "error":
            _failure = object["message"] as? String ?? "error"
        default:
            break
        }
        return false
    }
}

// MARK: - Apple's on-device model

enum OnDeviceAI {
    /// Why it can't be used on this Mac, or nil when it's ready.
    @MainActor static var problem: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.appleIntelligenceNotEnabled):
                return L("Apple Intelligence kapalı (Sistem Ayarları)", "Apple Intelligence is off (System Settings)")
            case .unavailable(.modelNotReady): return L("Model hâlâ iniyor", "The model is still downloading")
            case .unavailable(.deviceNotEligible): return L("Bu Mac desteklemiyor", "This Mac doesn't support it")
            case .unavailable: return L("Şu an kullanılamıyor", "Not available right now")
            }
        }
        #endif
        return L("macOS 26 ve Apple Intelligence gerekir", "Needs macOS 26 and Apple Intelligence")
    }

    /// The on-device model reads about 4,000 tokens in all, so long chats are cut from the start.
    static let maxPrompt = 9_000
    /// Open sessions by chat, with how many answers each has given.
    @MainActor private static var sessions: [UUID: (session: AnyObject, answered: Int)] = [:]

    @MainActor static func stream(_ request: AIRequest) -> AsyncThrowingStream<AIProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try await run(request) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A 2–5 word title for a chat, in its language; nil when the model isn't here or says nothing useful.
    /// What you'll probably say next, for the grey suggestion in the empty message box; nil when nothing fits.
    @MainActor static func suggestion(question: String, answer: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), problem == nil {
            let session = LanguageModelSession(instructions: Instructions(
                "You guess what the USER will type next to the assistant: a short follow-up question or request, in the user's "
                    + "language, written by the user (\"How do I…?\", \"Show an example\", \"Peki bunu nasıl yaparım?\"). "
                    + "Never answer, never write as the assistant, never repeat the question. Under 12 words. "
                    + "If no follow-up is likely, reply NONE. Reply with the message only."))
            // Small models drift into English; name the user's language outright.
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(String(question.prefix(500)))
            let language = recognizer.dominantLanguage.flatMap { Locale(identifier: "en").localizedString(forLanguageCode: $0.rawValue) } ?? "the user's language"
            let text = "Write the follow-up in \(language).\n\nUser: \(question.prefix(1_500))\n\nAssistant: \(answer.prefix(2_500))"
            guard let reply = try? await session.respond(to: text) else { return nil }
            let line = reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”«»"))
                .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            // A follow-up is short and asks for something; anything else is the model answering instead.
            let words = line.split(separator: " ").count
            let asks = line.hasSuffix("?") || words <= 8
            guard (3...110).contains(line.count), words <= 14, asks, !line.uppercased().hasPrefix("NONE"),
                  !line.lowercased().hasPrefix("user:"), !answer.contains(line) else { return nil }
            return line
        }
        #endif
        return nil
    }

    @MainActor static func title(for text: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), problem == nil {
            let session = LanguageModelSession(instructions: Instructions(
                "Write a short title (2 to 5 words) for the conversation below, in the language it is written in. "
                    + "Reply with the title only: no quotes, no full stop, no emoji."))
            guard let reply = try? await session.respond(to: text) else { return nil }
            let title = reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”«».*#"))
                .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return (2...60).contains(title.count) ? title : nil
        }
        #endif
        return nil
    }

    @MainActor private static func run(_ request: AIRequest, update: (AIProgress) -> Void) async throws {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if let problem { throw AIError(problem) }
            // The chat's own session remembers it, so only the new message goes in; otherwise (a new, reopened or
            // rewritten chat) a fresh session reads the chat so far.
            var session: LanguageModelSession
            var prompt = request.prompt
            if let id = request.chatID, let saved = sessions[id], saved.answered == request.answered,
               let existing = saved.session as? LanguageModelSession, !request.latest.isEmpty {
                session = existing
                prompt = request.latest
            } else {
                session = LanguageModelSession(instructions: Instructions(request.system))
            }
            if prompt.count > maxPrompt { prompt = String(prompt.suffix(maxPrompt)) }
            do {
                for try await snapshot in session.streamResponse(to: prompt) {
                    try Task.checkCancellation()
                    update(AIProgress(text: snapshot.content))
                }
                if let id = request.chatID {
                    if sessions.count > 20 { sessions.removeAll() }
                    sessions[id] = (session, request.answered + 1)
                }
            } catch let error as LanguageModelSession.GenerationError {
                if let id = request.chatID { sessions[id] = nil }
                switch error {
                case .exceededContextWindowSize: throw AIError(L("Sohbet cihaz içi model için çok uzun; yeni sohbet aç", "The chat is too long for the on-device model; start a new one"))
                case .guardrailViolation, .refusal: throw AIError(L("Cihaz içi model bunu cevaplamadı", "The on-device model wouldn't answer this"))
                case .unsupportedLanguageOrLocale: throw AIError(L("Cihaz içi model bu dili desteklemiyor", "The on-device model doesn't support this language"))
                default: throw AIError(error.localizedDescription)
                }
            }
            return
        }
        #endif
        throw AIError(problem ?? "")
    }
}

// MARK: - Text tasks

/// Ready-made things to do with a piece of text.
enum AITextTask: String, CaseIterable, Identifiable {
    case summarize, fix, shorten, toTurkish, toEnglish, explain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summarize: L("Özetle", "Summarise")
        case .fix: L("Yazımı düzelt", "Fix the writing")
        case .shorten: L("Kısalt", "Make it shorter")
        case .toTurkish: L("Türkçeye çevir", "Translate to Turkish")
        case .toEnglish: L("İngilizceye çevir", "Translate to English")
        case .explain: L("Açıkla", "Explain")
        }
    }

    var symbol: String {
        switch self {
        case .summarize: "text.append"
        case .fix: "checkmark.seal"
        case .shorten: "arrow.down.right.and.arrow.up.left"
        case .toTurkish, .toEnglish: "character.bubble"
        case .explain: "questionmark.bubble"
        }
    }

    /// Only the result comes back, so it can be pasted as it is.
    func prompt(_ text: String) -> String {
        let job: String = switch self {
        case .summarize: "Summarise the text below in a few short sentences, in the same language as the text."
        case .fix: "Fix spelling, grammar and punctuation in the text below. Keep its language, meaning, tone and line breaks."
        case .shorten: "Rewrite the text below shorter and clearer. Keep its language and meaning."
        case .toTurkish: "Translate the text below into natural Turkish."
        case .toEnglish: "Translate the text below into natural English."
        case .explain: "Explain the text below simply, in \(Prefs.isTurkish ? "Turkish" : "English"), in a few short sentences."
        }
        return "\(job) Reply with the result only: no introduction, no notes, no quotes around it.\n\n<text>\n\(text)\n</text>"
    }
}

// MARK: - Secrets

/// Text that looks like a password, key or token: never offered to an AI as "summarise what I copied".
enum SecretText {
    static func looksSecret(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["sk-", "sk_", "pk_", "rk_", "ghp_", "gho_", "github_pat_", "xox", "AKIA", "eyJ", "AIza", "glpat-", "shpat_"]
        if prefixes.contains(where: trimmed.hasPrefix) || trimmed.contains("_live_") || trimmed.contains("_test_") { return true }
        if trimmed.contains("-----BEGIN") && trimmed.contains("PRIVATE KEY") { return true }
        // One long word mixing letters and digits: a token rather than prose.
        guard trimmed.count >= 20, !trimmed.contains(where: \.isWhitespace) else { return false }
        return trimmed.contains(where: \.isNumber) && trimmed.contains(where: \.isLetter) && !trimmed.contains("://")
    }
}

// MARK: - Selected text

/// The text selected in the app in front, read through Accessibility (no keystrokes, the clipboard is untouched).
enum SelectedText {
    @MainActor static func read() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(text.prefix(20_000))
    }
}
