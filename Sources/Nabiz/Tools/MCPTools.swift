// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit

struct MCPToolError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// One thing an AI app can do with Nabız.
@MainActor
struct MCPTool {
    enum Group { case basic, commands, notes, clipboard }

    let name: String
    let title: String
    let description: String
    let group: Group
    var readOnly = true
    /// JSON Schema properties of the arguments.
    var properties: [String: [String: Any]] = [:]
    var required: [String] = []
    let run: @MainActor ([String: Any]) async throws -> String

    var descriptor: [String: Any] {
        [
            "name": name,
            "title": title,
            "description": description,
            "inputSchema": ["type": "object", "properties": properties, "required": required] as [String: Any],
            "annotations": ["title": title, "readOnlyHint": readOnly, "destructiveHint": false, "openWorldHint": false],
        ]
    }
}

@MainActor
enum MCPTools {
    /// Launcher commands an AI app may not run: they end the session or throw work away.
    static let unsafeCommands: Set<String> = ["sys:quitAll", "sys:emptyTrash", "sys:restart", "sys:shutDown", "sys:logOut"]

    /// The tools the person allowed in Settings → MCP.
    static var available: [MCPTool] {
        all.filter { tool in
            switch tool.group {
            case .basic: true
            case .commands: Prefs.bool(Prefs.mcpCommands)
            case .notes: Prefs.bool(Prefs.mcpNotes)
            case .clipboard: Prefs.bool(Prefs.mcpClipboard)
            }
        }
    }

    static var all: [MCPTool] {
        [
            // MARK: Reading the Mac
            MCPTool(name: "system_status", title: "System status",
                    description: "This Mac right now: CPU and GPU load, memory used and pressure, swap, free disk, battery, temperature state, network speed, uptime, and the apps using the most memory and CPU.",
                    group: .basic) { _ in try systemStatus() },
            MCPTool(name: "ai_limits", title: "AI subscription limits",
                    description: "How much of the user's Claude, ChatGPT/Codex, Gemini and Grok subscription windows (5-hour, weekly, per model) is used, when each resets, and whether it is on pace to run out. One entry per account; a second account of a provider carries its nickname in \"account\". Only the providers turned on in Nabız.",
                    group: .basic) { _ in try await aiLimits() },
            MCPTool(name: "calendar_events", title: "Calendar",
                    description: "The user's calendar events from now on, with times, location, and a meeting link when there is one.",
                    group: .basic,
                    properties: ["days": ["type": "integer", "description": "How many days ahead, 1 (today) to 14. Default 1.", "minimum": 1, "maximum": 14]]) { args in
                try await calendarEvents(days: int(args["days"]) ?? 1)
            },
            MCPTool(name: "calculate", title: "Calculate",
                    description: "Nabız's calculator: maths (12*4, sqrt 2, 20% of 150), currencies (100 usd to try, 0.5 btc), units (5 km mi, 120 km/h mph), time zones (15:00 istanbul to new york) and dates (today + 30 days, days until 2027-01-01).",
                    group: .basic,
                    properties: ["expression": ["type": "string", "description": "What to work out, as you would type it."]],
                    required: ["expression"]) { args in
                let expression = try string(args["expression"], "expression")
                let results = Calculator.evaluateAll(expression)
                guard !results.isEmpty else { throw MCPToolError("Nabız couldn't work that out: \(expression)") }
                return results.map(\.text).joined(separator: "\n")
            },
            MCPTool(name: "market_prices", title: "Market prices",
                    description: "Live prices and 24-hour change from Hyperliquid: crypto (BTC, ETH, SOL…) and HIP-3 stocks, indices and commodities. Without symbols, the markets the user watches.",
                    group: .basic,
                    properties: ["symbols": ["type": "array", "items": ["type": "string"], "description": "Market names such as BTC, ETH or xyz:NVDA."]]) { args in
                try await marketPrices(args["symbols"] as? [String] ?? [])
            },
            MCPTool(name: "exchange_rates", title: "Exchange rates",
                    description: "European Central Bank reference rates, as the value of one unit of each currency in the base currency, with the daily change.",
                    group: .basic,
                    properties: ["base": ["type": "string", "description": "Base currency code; default the user's main currency."],
                                 "codes": ["type": "array", "items": ["type": "string"], "description": "Currency codes; default the user's watched ones."]]) { args in
                try exchangeRates(base: args["base"] as? String, codes: args["codes"] as? [String])
            },
            MCPTool(name: "notify", title: "Send a notification",
                    description: "Shows a macOS notification on the user's Mac, for example when a long task finishes or needs their attention.",
                    group: .basic, readOnly: false,
                    properties: ["title": ["type": "string"], "message": ["type": "string"]],
                    required: ["title"]) { args in
                let title = try string(args["title"], "title")
                Notifier.shared.requestPermission(keepSetting: true)
                Notifier.shared.post(id: "mcp-\(Date().timeIntervalSince1970)", title: title, body: args["message"] as? String ?? "")
                return "Notification sent."
            },
            MCPTool(name: "dev_servers", title: "Running dev servers",
                    description: "Dev servers the user has running on this Mac (vite, next, wrangler, python http.server…): project, folder, ports, pid, how long it has run and its local URL. Check this before starting a server: if the project already has one, use it instead of starting a second on another port.",
                    group: .basic) { _ in
                let servers = await Task.detached(priority: .userInitiated) { DevServers.running() }.value
                guard !servers.isEmpty else { return "No dev servers are running." }
                return json(servers.map { server -> [String: Any] in
                    var item: [String: Any] = ["project": server.projectName, "folder": server.folder, "tool": server.tool,
                                               "ports": server.ports.map(Int.init), "pid": Int(server.pid)]
                    if let url = server.url { item["url"] = url.absoluteString }
                    if let started = server.started { item["running_minutes"] = Int(Date().timeIntervalSince(started) / 60) }
                    return item
                })
            },

            MCPTool(name: "port_info", title: "Who uses a port",
                    description: "Which process listens on a TCP port of this Mac (any of the user's processes, plus Docker, AirPlay and other system ones), its project folder, whether it's open to the network, and the first free port from there. Without a port, every listening port. Use it before picking a port or when one is 'already in use'.",
                    group: .basic,
                    properties: ["port": ["type": "integer", "minimum": 1, "maximum": 65535]]) { args in
                let port = int(args["port"]).flatMap { UInt16(exactly: $0) }
                let uses = await Task.detached(priority: .userInitiated) { port.map(Ports.lookup) ?? Ports.all() }.value
                var result: [String: Any] = ["listening": uses.map { use -> [String: Any] in
                    var item: [String: Any] = ["port": Int(use.port), "process": use.name, "open_to_network": use.everyInterface,
                                               "stoppable_by_stop_dev_server": use.stoppable && use.project != nil]
                    if let pid = use.pid { item["pid"] = Int(pid) }
                    if let folder = use.folder { item["folder"] = folder }
                    if let note = use.note { item["note"] = note }
                    return item
                }]
                if let port {
                    let free: Int? = await Task.detached(priority: .userInitiated) { Ports.firstFree(from: port).map(Int.init) }.value
                    result["first_free_port"] = free ?? NSNull()
                }
                return json(result)
            },
            MCPTool(name: "projects", title: "The user's projects",
                    description: "Git repositories in the user's project folders (~/Developer…): path, branch, files changed, commits ahead/behind its upstream, last activity, stack (node, swift, xcode, rust…), package manager, package.json scripts, GitHub URL and the dev server running for it, if any. Most recently active first.",
                    group: .basic) { _ in
                let found = await Task.detached(priority: .userInitiated) { () -> ([Project], [DevServer]) in
                    let projects = Projects.find().map(Projects.read)
                    return (projects, DevServers.running())
                }.value
                let (projects, servers) = found
                return json(projects.sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }.map { project -> [String: Any] in
                    var item: [String: Any] = ["name": project.displayName, "path": project.path, "changes": project.changes,
                                               "ahead": project.ahead, "behind": project.behind, "stack": project.stack.map(\.rawValue),
                                               "scripts": project.scripts]
                    if let branch = project.branch { item["branch"] = branch }
                    if let upstream = project.upstream { item["upstream"] = upstream }
                    if let manager = project.packageManager { item["package_manager"] = manager }
                    if let remote = project.remote { item["github"] = remote.absoluteString }
                    if let last = project.lastActivity { item["last_activity"] = DevUtils.iso8601(last) }
                    if project.isWorktree { item["worktree"] = true }
                    if let server = servers.first(where: { $0.project == project.path }), let url = server.url { item["dev_server"] = url.absoluteString }
                    return item
                })
            },
            MCPTool(name: "docker_containers", title: "Docker containers",
                    description: "Docker containers on this Mac (running and stopped): name, image, state, host ports and the compose project with its folder. Empty when Docker isn't running.",
                    group: .basic) { _ in
                guard let containers = await Task.detached(priority: .userInitiated) { Docker.containers() }.value else {
                    return "Docker isn't running."
                }
                return json(containers.map { container -> [String: Any] in
                    var item: [String: Any] = ["name": container.name, "image": container.image, "running": container.running,
                                               "status": container.status, "ports": container.ports.map(Int.init)]
                    if let project = container.project { item["project"] = project }
                    if let folder = container.folder { item["folder"] = folder }
                    return item
                })
            },

            // MARK: Acting on the Mac
            MCPTool(name: "list_commands", title: "List Mac commands",
                    description: "Everything run_command can do, as id and title: lock screen, sleep, window layouts (halves, thirds, your own), sound output devices, mute, timers, focus mode, Pomodoro, screenshots, keep awake, the user's Shortcuts and scripts, and Nabız's tools.",
                    group: .commands) { _ in
                commands().map { "\($0.id)\t\($0.title)" }.joined(separator: "\n")
            },
            MCPTool(name: "run_command", title: "Run a Mac command",
                    description: "Runs one command from list_commands by its id (for example win:leftHalf, sys:lock, cmd:focus-25). Window commands act on the window in front.",
                    group: .commands, readOnly: false,
                    properties: ["id": ["type": "string", "description": "A command id from list_commands."]],
                    required: ["id"]) { args in
                let id = try string(args["id"], "id")
                guard !unsafeCommands.contains(id) else { throw MCPToolError("For safety, \(id) can only be run by the user.") }
                guard let command = commands().first(where: { $0.id == id }) else {
                    throw MCPToolError("No command \(id). Call list_commands for the ids.")
                }
                LauncherPanel.shared.run(itemID: id)
                return "Done: \(command.title)"
            },
            MCPTool(name: "open_app", title: "Open an app",
                    description: "Opens (or brings forward) an app on this Mac by its name; close spellings are fine.",
                    group: .commands, readOnly: false,
                    properties: ["name": ["type": "string"]], required: ["name"]) { args in
                try await openApp(try string(args["name"], "name"))
            },
            MCPTool(name: "set_volume", title: "Set the volume",
                    description: "Sets the Mac's output volume, 0 to 100, and unmutes it.",
                    group: .commands, readOnly: false,
                    properties: ["level": ["type": "integer", "minimum": 0, "maximum": 100]], required: ["level"]) { args in
                guard let level = int(args["level"]), (0...100).contains(level) else { throw MCPToolError("level must be 0 to 100") }
                SoundOutput.setVolume(level)
                return "Volume \(level)%."
            },
            MCPTool(name: "stop_dev_server", title: "Stop a dev server",
                    description: "Stops one of the dev servers dev_servers lists, by its port or pid (and the npm/pnpm wrapper that only ran it). Nothing else can be stopped this way.",
                    group: .commands, readOnly: false,
                    properties: ["port": ["type": "integer", "minimum": 1, "maximum": 65535], "pid": ["type": "integer"]]) { args in
                let port = int(args["port"]), pid = int(args["pid"])
                guard port != nil || pid != nil else { throw MCPToolError("Give the server's port or pid.") }
                let servers = await Task.detached(priority: .userInitiated) { DevServers.running() }.value
                guard let server = servers.first(where: { s in pid.map { Int(s.pid) == $0 } ?? s.ports.contains { Int($0) == port } }) else {
                    throw MCPToolError("No dev server there. Call dev_servers for the list.")
                }
                let stopped = await Task.detached(priority: .userInitiated) { DevServers.stop(server.pid) }.value
                return stopped ? "Stopped \(server.tool) in \(server.projectName) (\(server.portsText))." : "It didn't stop; it may need the user."
            },
            MCPTool(name: "start_timer", title: "Start a timer",
                    description: "Starts a countdown in the menu bar that plays a sound and notifies when it ends.",
                    group: .commands, readOnly: false,
                    properties: ["minutes": ["type": "integer", "minimum": 1, "maximum": 600]], required: ["minutes"]) { args in
                guard let minutes = int(args["minutes"]), (1...600).contains(minutes) else { throw MCPToolError("minutes must be 1 to 600") }
                CountdownTimer.shared.start(minutes: minutes)
                return "Timer: \(minutes) min."
            },
            MCPTool(name: "focus_mode", title: "Focus mode",
                    description: "Starts or stops Nabız's focus mode, which keeps chat apps (and blocked websites, if the user turned that on) away.",
                    group: .commands, readOnly: false,
                    properties: ["action": ["type": "string", "enum": ["start", "stop"]],
                                 "minutes": ["type": "integer", "description": "How long; leave out for until stopped.", "minimum": 1, "maximum": 600]],
                    required: ["action"]) { args in
                let action = try string(args["action"], "action")
                if action == "stop" {
                    FocusMode.shared.stop()
                    return "Focus mode off."
                }
                let minutes = int(args["minutes"]).map { min(max($0, 1), 600) }
                FocusMode.shared.start(minutes: minutes)
                return minutes.map { "Focus mode on for \($0) min." } ?? "Focus mode on until stopped."
            },
            MCPTool(name: "copy_to_clipboard", title: "Copy to the clipboard",
                    description: "Puts text on the Mac's clipboard so the user can paste it.",
                    group: .commands, readOnly: false,
                    properties: ["text": ["type": "string"]], required: ["text"]) { args in
                let text = try string(args["text"], "text")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                Monitor.panelActions.flash(L("Kopyalandı", "Copied"))
                return "Copied \(text.count) characters."
            },

            // MARK: Notes and snippets
            MCPTool(name: "notes_search", title: "Search notes",
                    description: "The user's Nabız notes, newest first: id, title, a preview and when each changed. With a query, only notes containing it.",
                    group: .notes,
                    properties: ["query": ["type": "string"], "limit": ["type": "integer", "minimum": 1, "maximum": 100]]) { args in
                notesSearch(args["query"] as? String ?? "", limit: int(args["limit"]) ?? 20)
            },
            MCPTool(name: "note_read", title: "Read a note",
                    description: "The full Markdown text of one note, by its id from notes_search.",
                    group: .notes,
                    properties: ["id": ["type": "string"]], required: ["id"]) { args in
                try note(args["id"]).text
            },
            MCPTool(name: "note_create", title: "Create a note",
                    description: "Saves a new note (Markdown; the first line is its title) and returns its id.",
                    group: .notes, readOnly: false,
                    properties: ["text": ["type": "string"]], required: ["text"]) { args in
                let text = try string(args["text"], "text")
                let id = NoteStore.shared.create(text)
                NoteStore.shared.saveNow()
                return "Created note \(id.uuidString)."
            },
            MCPTool(name: "note_append", title: "Add to a note",
                    description: "Adds text to the end of a note, on a new line.",
                    group: .notes, readOnly: false,
                    properties: ["id": ["type": "string"], "text": ["type": "string"]], required: ["id", "text"]) { args in
                let existing = try note(args["id"])
                let text = try string(args["text"], "text")
                NoteStore.shared.update(existing.id, text: existing.text.hasSuffix("\n") ? existing.text + text : existing.text + "\n" + text)
                NoteStore.shared.saveNow()
                return "Added to \(existing.title)."
            },
            MCPTool(name: "snippets_list", title: "List snippets",
                    description: "The user's saved text snippets: keyword, name and text.",
                    group: .notes) { _ in
                json(LauncherStore.shared.snippets.map { ["keyword": $0.keyword, "name": $0.name, "text": $0.text] })
            },

            // MARK: Clipboard (off unless the user turns it on)
            MCPTool(name: "clipboard_history", title: "Clipboard history",
                    description: "What the user copied recently (text, links, colours, file names), newest first. Pinned items are marked.",
                    group: .clipboard,
                    properties: ["query": ["type": "string"], "limit": ["type": "integer", "minimum": 1, "maximum": 100]]) { args in
                clipboardHistory(args["query"] as? String ?? "", limit: int(args["limit"]) ?? 20)
            },
        ] + recording
    }

    // MARK: Helpers

    static func string(_ value: Any?, _ name: String) throws -> String {
        guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("\(name) is required")
        }
        return text
    }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    static func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// A number with a fixed count of decimals, written to JSON as it reads ("378.2", not "378.19999999999999").
    private static func number(_ value: Double, _ digits: Int) -> NSDecimalNumber {
        NSDecimalNumber(string: String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), value))
    }

    private static func gb(_ bytes: UInt64) -> NSDecimalNumber { number(Double(bytes) / 1_073_741_824, 1) }

    private static func iso(_ date: Date) -> String { date.formatted(.iso8601) }

    static func commands() -> [(id: String, title: String)] {
        AppIndex.shared.refreshIfNeeded()
        Extensions.shared.refreshIfNeeded()
        return LauncherPanel.shared.model.commandList().filter { !unsafeCommands.contains($0.id) }
    }

    private static func systemStatus() throws -> String {
        guard let monitor = SettingsWindow.monitor, let system = monitor.system else {
            throw MCPToolError("Nabız hasn't measured yet; try again in a few seconds.")
        }
        var result: [String: Any] = [
            "cpu_percent": Int((system.cpu * 100).rounded()),
            "cores": system.cores,
            "load_average": number(system.load, 2),
            "memory_used_gb": gb(system.memoryUsed),
            "memory_total_gb": gb(system.memoryTotal),
            "memory_pressure": ["normal", "warning", "critical"][system.pressure.rawValue],
            "swap_used_gb": gb(system.swapUsed),
            "thermal_state": ["nominal", "fair", "serious", "critical"][min(max(system.thermal, 0), 3)],
        ]
        if let gpu = system.gpu { result["gpu_percent"] = Int((gpu * 100).rounded()) }
        if let free = system.diskFree { result["disk_free_gb"] = gb(free) }
        if let boot = system.bootDate { result["up_since"] = iso(boot) }
        if let battery = monitor.battery {
            var info: [String: Any] = ["percent": battery.percent, "charging": battery.charging, "plugged_in": battery.plugged]
            if let minutes = battery.minutesLeft { info["minutes_left"] = minutes }
            result["battery"] = info
        }
        if let network = monitor.network {
            result["network_kb_per_s"] = ["down": Int(network.down / 1024), "up": Int(network.up / 1024)]
        }
        let app: (ProcessGroup) -> [String: Any] = { ["name": $0.name, "memory_gb": gb($0.memory), "cpu_percent": Int(($0.cpu * 100).rounded())] }
        result["top_by_memory"] = monitor.top(by: .memory, count: 5).map(app)
        result["top_by_cpu"] = monitor.top(by: .cpu, count: 5).map(app)
        if !monitor.simulators.isEmpty { result["running_simulators"] = monitor.simulators.count }
        return json(result)
    }

    private static func aiLimits() async throws -> String {
        let store = AILimitsStore.shared
        guard !store.enabled.isEmpty else {
            throw MCPToolError("No AI limits are turned on. The user can pick providers in Nabız → Settings → AI.")
        }
        store.refreshIfNeeded()
        for _ in 0..<40 where store.loading || store.statuses.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
        return json(store.statuses.map { status -> [String: Any] in
            var entry: [String: Any] = ["provider": status.provider.name]
            if let account = store.label(status) { entry["account"] = account }
            if let plan = status.plan { entry["plan"] = plan }
            if let problem = status.problem { entry["problem"] = problem }
            entry["limits"] = status.limits.map { limit -> [String: Any] in
                var item: [String: Any] = ["window": limit.label, "used_percent": Int((limit.used * 100).rounded())]
                if let reset = limit.resetsAt { item["resets_at"] = iso(reset) }
                return item
            }
            return entry
        })
    }

    private static func calendarEvents(days: Int) async throws -> String {
        let agenda = CalendarAgenda.shared
        guard agenda.authorized else {
            throw MCPToolError("Nabız has no calendar access. The user can turn on the calendar in Nabız → Settings → Calendar.")
        }
        let events = agenda.events(days: min(max(days, 1), 14))
        return json(events.map { event -> [String: Any] in
            var item: [String: Any] = ["title": event.title, "start": iso(event.start), "end": iso(event.end), "all_day": event.allDay,
                                       "calendar": event.calendar]
            if let location = event.location { item["location"] = location }
            if let link = event.meetingURL { item["meeting_link"] = link.absoluteString }
            return item
        })
    }

    private static func marketPrices(_ symbols: [String]) async throws -> String {
        let store = MarketStore.shared
        if store.markets.isEmpty {
            store.refreshCrypto()
            for _ in 0..<20 where store.markets.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
        }
        let markets: [Market]
        if symbols.isEmpty {
            store.refreshWatched(maxAge: 10)
            markets = store.watched
        } else {
            markets = symbols.compactMap { symbol in
                let wanted = symbol.lowercased()
                return store.markets[symbol] ?? store.markets.values.first { $0.id.lowercased() == wanted }
                    ?? store.markets.values.filter { $0.name.lowercased() == wanted }.max { $0.volume < $1.volume }
            }
        }
        guard !markets.isEmpty else { throw MCPToolError("No matching markets. Use Hyperliquid names such as BTC, ETH or xyz:NVDA.") }
        return json(markets.map { market -> [String: Any] in
            var item: [String: Any] = ["market": market.id, "price": number(market.price, market.price >= 100 ? 2 : market.price >= 1 ? 4 : 6)]
            if let change = market.change { item["change_24h_percent"] = number(change * 100, 2) }
            return item
        })
    }

    private static func exchangeRates(base: String?, codes: [String]?) throws -> String {
        let store = RateStore.shared
        store.refreshIfNeeded()
        let base = (base ?? Prefs.string(Prefs.baseCurrency)).uppercased()
        let codes = (codes ?? Prefs.string(Prefs.watchedCurrencies).split(separator: ",").map(String.init)).map { $0.uppercased() }
        guard store.rate(base) != nil else { throw MCPToolError("Unknown currency \(base), or the rates haven't loaded yet.") }
        var rates: [String: Any] = [:]
        for code in codes where code != base {
            guard let value = store.convert(1, from: code, to: base) else { continue }
            var item: [String: Any] = ["value": number(value, 4)]
            if let change = store.change(code, in: base) { item["change_percent"] = number(change * 100, 2) }
            rates[code] = item
        }
        return json(["base": base, "date": store.table?.date ?? "", "rates": rates])
    }

    private static func openApp(_ name: String) async throws -> String {
        let index = AppIndex.shared
        index.refreshIfNeeded()
        for _ in 0..<20 where index.apps.isEmpty { try? await Task.sleep(for: .milliseconds(150)) }
        let best = index.apps.compactMap { app -> (Int, AppIndex.App)? in
            [Fuzzy.score(name, app.name), Fuzzy.score(name, app.fileName)].compactMap { $0 }.max().map { ($0, app) }
        }.max { $0.0 < $1.0 }
        guard let app = best?.1 else { throw MCPToolError("No app called \(name) on this Mac.") }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration)
        return "Opened \(app.name)."
    }

    private static func notesSearch(_ query: String, limit: Int) -> String {
        let query = query.trimmingCharacters(in: .whitespaces)
        let notes = NoteStore.shared.sorted.filter { !$0.isEmpty && (query.isEmpty || Fuzzy.contains(query, $0.text)) }
        return json(notes.prefix(min(max(limit, 1), 100)).map {
            ["id": $0.id.uuidString, "title": $0.title, "preview": $0.preview, "modified": iso($0.modified)]
        })
    }

    private static func note(_ value: Any?) throws -> Note {
        let text = try string(value, "id")
        guard let id = UUID(uuidString: text), let note = NoteStore.shared.notes.first(where: { $0.id == id }) else {
            throw MCPToolError("No note with id \(text). Call notes_search for ids.")
        }
        return note
    }

    private static func clipboardHistory(_ query: String, limit: Int) -> String {
        let query = query.trimmingCharacters(in: .whitespaces)
        let items = ClipboardHistory.shared.items.filter { $0.kind != .image && (query.isEmpty || Fuzzy.contains(query, $0.preview)) }
        return json(items.prefix(min(max(limit, 1), 100)).map { item -> [String: Any] in
            var entry: [String: Any] = ["kind": item.kind.rawValue, "copied": iso(item.date), "pinned": item.pinned]
            entry["text"] = item.kind == .files ? (item.files ?? []).joined(separator: "\n") : String((item.text ?? item.preview).prefix(4000))
            if let app = item.app { entry["app"] = app }
            return entry
        })
    }
}
