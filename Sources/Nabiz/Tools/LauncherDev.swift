// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit

/// The launcher's developer answers: ports, projects, JWTs, Unix time, hashes, ids, cases, colours, cron, HTTP codes.
extension LauncherModel {
    func devSections(_ query: String) -> [LauncherSection] {
        var sections: [LauncherSection] = []
        let lower = query.lowercased()
        let words = query.split(separator: " ", maxSplits: 1).map(String.init)
        let head = words.first?.lowercased() ?? ""
        let rest = words.count > 1 ? words[1] : ""

        // ":3000", "port 3000"; "port" / "ports" alone lists every one.
        if let port = Ports.query(query) {
            sections.append(LauncherSection(id: "port", title: L("Port \(port)", "Port \(port)"), items: portItems(port)))
        } else if ["port", "ports", "portlar", "portlari"].contains(Fuzzy.fold(lower)) {
            let uses = PortCache.shared.uses
            sections.append(LauncherSection(id: "port", title: L("Dinleyen portlar", "Listening ports"),
                                            items: uses.prefix(20).map { portItem($0) }))
        }

        // Projects: by name ("nabiz"), or all of them for "proj" / "projeler".
        let store = ProjectStore.shared
        if ["proj", "project", "projects", "proje", "projeler", "repo", "repos"].contains(Fuzzy.fold(lower)) {
            sections.append(LauncherSection(id: "projects", title: L("Projeler", "Projects"), items: store.recent.prefix(12).map(projectItem)))
        } else if query.count >= 2 {
            let found = store.projects.compactMap { project -> (Int, Project)? in
                let best = [Fuzzy.score(query, project.name), Fuzzy.score(query, project.displayName)].compactMap { $0 }.max()
                return best.flatMap { $0 >= 600 ? ($0, project) : nil }
            }
            .sorted { $0.0 > $1.0 }.prefix(4).map { projectItem($0.1) }
            if !found.isEmpty { sections.append(LauncherSection(id: "projects", title: L("Projeler", "Projects"), items: found)) }
        }

        if let jwt = DevUtils.jwt(query) {
            sections.append(LauncherSection(id: "jwt", title: "JWT", items: jwtItems(jwt)))
        }

        if let date = DevUtils.epoch(query) {
            sections.append(LauncherSection(id: "epoch", title: L("Unix zamanı", "Unix time"), items: dateItems(date)))
        } else if ["now", "unix", "epoch", "timestamp", "zaman damgasi", "simdi"].contains(Fuzzy.fold(lower)) {
            let now = Date()
            sections.append(LauncherSection(id: "epoch", title: L("Şu an", "Now"), items: [
                copyItem("epoch-s", "clock", String(Int(now.timeIntervalSince1970)), subtitle: L("Unix zamanı (saniye)", "Unix time (seconds)")),
                copyItem("epoch-ms", "clock", String(Int(now.timeIntervalSince1970 * 1000)), subtitle: L("Unix zamanı (milisaniye)", "Unix time (milliseconds)")),
                copyItem("epoch-iso", "calendar", DevUtils.iso8601(now), subtitle: "ISO 8601"),
            ]))
        }

        // "sha256 text", "md5 text", "hash text".
        if !rest.isEmpty, let kinds = hashKinds(head) {
            sections.append(LauncherSection(id: "hash", title: "Hash", items: kinds.map { kind in
                copyItem("hash-\(kind.rawValue)", "number", DevUtils.hash(rest, kind), subtitle: kind.rawValue.uppercased())
            }))
        }

        switch Fuzzy.fold(lower) {
        case "ulid": sections.append(LauncherSection(id: "ids", title: "ID", items: [copyItem("ulid", "number", DevUtils.ulid(), subtitle: "ULID")]))
        case "nanoid": sections.append(LauncherSection(id: "ids", title: "ID", items: [copyItem("nanoid", "number", DevUtils.nanoid(), subtitle: "nanoid")]))
        case "uuid", "guid":
            sections.append(LauncherSection(id: "ids", title: "ID", items: [
                copyItem("uuid", "number", UUID().uuidString.lowercased(), subtitle: "UUID v4"),
                copyItem("uuid-upper", "number", UUID().uuidString, subtitle: "UUID v4"),
                copyItem("ulid", "number", DevUtils.ulid(), subtitle: "ULID"),
            ]))
        default: break
        }

        // "case hello world", "camel hello world", "snake helloWorld".
        if !rest.isEmpty, let styles = caseStyles(head) {
            sections.append(LauncherSection(id: "case", title: L("Yazım biçimi", "Case"), items: styles.map { style in
                copyItem("case-\(style.rawValue)", "textformat", DevUtils.convert(rest, to: style), subtitle: style.title)
            }))
        }

        if let rgb = DevUtils.color(query) {
            let color = NSColor(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: rgb.alpha)
            sections.append(LauncherSection(id: "color", title: L("Renk", "Colour"), items: DevUtils.formats(rgb).map { format in
                var item = copyItem("color-\(format.title)", "paintpalette", format.value, subtitle: format.title)
                item.icon = .emoji(Self.swatch(color))
                return item
            }))
        }

        if let cron = DevUtils.cron(query) {
            sections.append(LauncherSection(id: "cron", title: "Cron", items: [copyItem("cron", "calendar.badge.clock", cron, subtitle: query)]))
        }

        if ["http", "status", "durum"].contains(head), let code = Int(rest.trimmingCharacters(in: .whitespaces)), let meaning = DevUtils.httpStatus(code) {
            sections.append(LauncherSection(id: "http", title: "HTTP", items: [copyItem("http", "network", "\(code) \(meaning)", subtitle: L("HTTP durum kodu", "HTTP status code"))]))
        }

        if ["brew", "homebrew"].contains(Fuzzy.fold(lower)),
           let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: FileManager.default.isExecutableFile) {
            let home = NSHomeDirectory()
            func terminal(_ id: String, _ title: String, _ command: String) -> LauncherItem {
                LauncherItem(id: "dev:\(id)", icon: .symbol("mug"), title: title, subtitle: command, accessory: "Terminal",
                             primaryTitle: L("Terminal'de çalıştır", "Run in Terminal"),
                             primary: { [weak self] in
                                 self?.close()
                                 TerminalLauncher.open(home, run: command, title: "Homebrew")
                             }, remember: false)
            }
            sections.append(LauncherSection(id: "brew", title: "Homebrew", items: [
                terminal("brew-upgrade", L("Paketleri güncelle", "Upgrade packages"), "\(brew) update && \(brew) outdated && \(brew) upgrade"),
                terminal("brew-outdated", L("Eski paketleri göster", "Show outdated packages"), "\(brew) update && \(brew) outdated"),
                terminal("brew-cleanup", L("Eski sürümleri temizle", "Clean up old versions"), "\(brew) cleanup -s --prune=all"),
            ]))
        }

        if ["base64", "b64"].contains(head), !rest.isEmpty {
            var items = [copyItem("b64-enc", "lock.doc", Data(rest.utf8).base64EncodedString(), subtitle: L("Base64'e çevrildi", "Encoded"))]
            if let decoded = TextTransform.base64Decode.apply(rest) ?? DevUtils.base64URL(rest).flatMap({ String(data: $0, encoding: .utf8) }) {
                items.append(copyItem("b64-dec", "lock.open", decoded, subtitle: L("Base64'ten çözüldü", "Decoded")))
            }
            sections.append(LauncherSection(id: "base64", title: "Base64", items: items))
        }
        if ["url", "urlencode", "urldecode"].contains(head), !rest.isEmpty {
            var items: [LauncherItem] = []
            if let encoded = TextTransform.urlEncode.apply(rest) { items.append(copyItem("url-enc", "link", encoded, subtitle: L("URL için kodlandı", "URL-encoded"))) }
            if let decoded = TextTransform.urlDecode.apply(rest) { items.append(copyItem("url-dec", "link", decoded, subtitle: L("URL kodu çözüldü", "URL-decoded"))) }
            if !items.isEmpty { sections.append(LauncherSection(id: "url", title: "URL", items: items)) }
        }
        return sections
    }

    // MARK: Rows

    /// A result row: ↩ copies it, ⌘↩ pastes it.
    func copyItem(_ id: String, _ symbol: String, _ value: String, subtitle: String? = nil) -> LauncherItem {
        let shown = value.count > 90 ? String(value.prefix(90)) + "…" : value
        let copy: @MainActor () -> Void = { [weak self] in
            // A generated value, not something the user copied: kept out of the history.
            ClipboardHistory.shared.writeOwn(value)
            self?.close()
            Monitor.panelActions.flash(L("Kopyalandı", "Copied"))
        }
        var item = LauncherItem(id: "dev:\(id)", icon: .symbol(symbol), title: shown.replacingOccurrences(of: "\n", with: " "), subtitle: subtitle,
                                primaryTitle: L("Kopyala", "Copy"), primary: copy, remember: false)
        if Paster.canPaste {
            item.secondaryTitle = L("Yapıştır", "Paste")
            item.secondary = { [weak self] in self?.paste(text: value) }
        }
        return item
    }

    private func portItems(_ port: UInt16) -> [LauncherItem] {
        let uses = PortCache.shared.uses.filter { $0.port == port }
        if !uses.isEmpty { return uses.map { portItem($0) } }
        if ProcInfo.somethingListens(on: port) {
            return [portItem(PortUse(port: port, pid: nil, name: L("Sistem süreci", "A system process"),
                                     note: Ports.wellKnown(port) ?? L("macOS'un kendi süreci; buradan durdurulamaz.", "Part of macOS; it can't be stopped from here."),
                                     folder: nil, project: nil, started: nil, everyInterface: false, stoppable: false))]
        }
        var items = [copyItem("port-free", "checkmark.circle", L("Port \(port) boş", "Port \(port) is free"),
                              subtitle: Ports.wellKnown(port).map { L("Genelde: \($0)", "Usually: \($0)") })]
        items[0].primaryTitle = L("Kopyala", "Copy")
        return items
    }

    private func portItem(_ use: PortUse) -> LauncherItem {
        var title = ":\(use.port)  \(use.name)"
        if let project = use.projectName { title += " · \(project)" }
        var subtitle: [String] = []
        if let note = use.note { subtitle.append(note) }
        if let started = use.started { subtitle.append(Format.duration(Date().timeIntervalSince(started))) }
        if use.everyInterface && use.stoppable { subtitle.append(L("ağa açık", "open to the network")) }
        let url = use.url
        let stop: @MainActor () -> Void = { [weak self] in
            self?.close()
            if let pid = use.pid { PortCache.shared.forget(pid: pid) }
            Task {
                let freed = await Task.detached(priority: .userInitiated) { Ports.free(use) }.value
                Monitor.panelActions.flash(freed ? L("Port \(use.port) boşaltıldı", "Port \(use.port) is free")
                                                 : L("Durdurulamadı", "Couldn't stop it"))
            }
        }
        let open: @MainActor () -> Void = { [weak self] in
            self?.close()
            if let url { NSWorkspace.shared.open(url) }
        }
        return LauncherItem(id: "port:\(use.port):\(use.pid ?? 0)", icon: .symbol(use.stoppable ? "network" : "lock"), title: title,
                            subtitle: subtitle.joined(separator: " · "), accessory: use.pid.map { "pid \($0)" },
                            primaryTitle: use.stoppable ? L("Durdur", "Stop") : L("Tarayıcıda aç", "Open in browser"),
                            primary: use.stoppable ? stop : open,
                            secondaryTitle: use.stoppable ? L("Tarayıcıda aç", "Open in browser") : nil,
                            secondary: use.stoppable ? open : nil,
                            remember: false)
    }

    func projectItem(_ project: Project) -> LauncherItem {
        let editor = ProjectActions.preferredEditor
        return LauncherItem(id: "proj:\(project.path)", icon: .symbol(ProjectSection.symbol(project)), title: project.displayName,
                            subtitle: ProjectSection.subtitle(project), accessory: L("Proje", "Project"),
                            primaryTitle: editor.map { L("\($0.name) ile aç", "Open in \($0.name)") } ?? L("Aç", "Open"),
                            primary: { [weak self] in
                                self?.close()
                                ProjectActions.openInEditor(project)
                            },
                            secondaryTitle: L("Terminal'de aç", "Open in Terminal"),
                            secondary: { [weak self] in
                                self?.close()
                                ProjectActions.terminal(project)
                            })
    }

    private func jwtItems(_ jwt: DevUtils.JWT) -> [LauncherItem] {
        var summary: [String] = []
        if let algorithm = jwt.algorithm { summary.append(algorithm) }
        if let expires = jwt.expires {
            let left = expires.timeIntervalSinceNow
            summary.append(left > 0 ? L("\(Format.duration(left)) sonra bitiyor", "expires in \(Format.duration(left))")
                                    : L("\(Format.duration(-left)) önce bitti", "expired \(Format.duration(-left)) ago"))
        }
        if let subject = jwt.subject { summary.append("sub \(subject)") }
        var items = [copyItem("jwt-payload", "key", summary.isEmpty ? L("İçerik (payload)", "Payload") : summary.joined(separator: " · "),
                              subtitle: L("İçeriği kopyala", "Copy the payload")),
                     copyItem("jwt-header", "key", jwt.header, subtitle: L("Başlık", "Header"))]
        items[0].primary = { [weak self] in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(jwt.payload, forType: .string)
            self?.close()
            Monitor.panelActions.flash(L("İçerik kopyalandı", "Payload copied"))
        }
        items[0].secondary = nil
        items[0].secondaryTitle = nil
        if let expires = jwt.expires {
            items.append(copyItem("jwt-exp", "clock", expires.formatted(date: .abbreviated, time: .standard), subtitle: L("Bitiş (exp)", "Expires (exp)")))
        }
        if let issuer = jwt.issuer { items.append(copyItem("jwt-iss", "building.2", issuer, subtitle: L("Veren (iss)", "Issuer (iss)"))) }
        return items
    }

    private func dateItems(_ date: Date) -> [LauncherItem] {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: Prefs.isTurkish ? "tr_TR" : "en_US")
        let ago = formatter.localizedString(for: date, relativeTo: Date())
        let utc = ISO8601DateFormatter()
        return [
            copyItem("epoch-local", "calendar", date.formatted(date: .complete, time: .standard), subtitle: L("Yerel saat · \(ago)", "Local time · \(ago)")),
            copyItem("epoch-utc", "globe", utc.string(from: date), subtitle: "UTC · ISO 8601"),
            copyItem("epoch-other", "clock", String(Int(date.timeIntervalSince1970 * 1000)), subtitle: L("Milisaniye", "Milliseconds")),
        ]
    }

    private func hashKinds(_ head: String) -> [DevUtils.HashKind]? {
        if head == "hash" { return DevUtils.HashKind.allCases }
        return DevUtils.HashKind(rawValue: head).map { [$0] }
    }

    private func caseStyles(_ head: String) -> [DevUtils.Case]? {
        switch head {
        case "case", "yazım", "yazim": DevUtils.Case.allCases
        case "camel", "camelcase": [.camel]
        case "pascal", "pascalcase": [.pascal]
        case "snake", "snake_case": [.snake]
        case "kebab", "kebab-case": [.kebab]
        case "constant", "screaming": [.constant]
        default: nil
        }
    }

    /// A coloured square, as an emoji stand-in for the row icon.
    private static func swatch(_ color: NSColor) -> String {
        let palette: [(String, NSColor)] = [("🟥", .systemRed), ("🟧", .systemOrange), ("🟨", .systemYellow), ("🟩", .systemGreen),
                                            ("🟦", .systemBlue), ("🟪", .systemPurple), ("🟫", .brown), ("⬛", .black), ("⬜", .white)]
        guard let rgb = color.usingColorSpace(.sRGB) else { return "⬜" }
        return palette.min { distance($0.1, rgb) < distance($1.1, rgb) }?.0 ?? "⬜"
    }

    private static func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        guard let a = a.usingColorSpace(.sRGB) else { return .infinity }
        return pow(a.redComponent - b.redComponent, 2) + pow(a.greenComponent - b.greenComponent, 2) + pow(a.blueComponent - b.blueComponent, 2)
    }

    // MARK: ⌘K

    func devActions(for item: LauncherItem, group: String) -> [LauncherAction] {
        guard item.id.hasPrefix("proj:"), let project = ProjectStore.shared.project(String(item.id.dropFirst(5))) else { return [] }
        var list: [LauncherAction] = []
        let close: @MainActor () -> Void = { [weak self] in self?.close() }
        for editor in ProjectActions.installedEditors where editor.bundleID != ProjectActions.preferredEditor?.bundleID {
            list.append(LauncherAction(id: "editor-\(editor.bundleID)", title: L("\(editor.name) ile aç", "Open in \(editor.name)"), symbol: "chevron.left.forwardslash.chevron.right", group: group) {
                close(); ProjectActions.openInEditor(project, editor: editor)
            })
        }
        if project.xcode != nil {
            list.append(LauncherAction(id: "xcode", title: L("Xcode ile aç", "Open in Xcode"), symbol: "hammer", group: group) { close(); ProjectActions.openInXcode(project) })
        }
        list.append(LauncherAction(id: "agent", title: L("\(ProjectActions.agentName) başlat", "Start \(ProjectActions.agentName)"), symbol: "sparkles", group: group) {
            close(); ProjectActions.agent(project)
        })
        for script in project.scripts {
            list.append(LauncherAction(id: "script-\(script)", title: L("Çalıştır: \(script)", "Run: \(script)"), symbol: "play", group: group) {
                close()
                if ["dev", "start"].contains(script) { ProjectActions.startDev(project) } else { ProjectActions.runScript(project, script) }
            })
        }
        if project.remote != nil {
            list.append(LauncherAction(id: "github", title: L("GitHub'da aç", "Open on GitHub"), symbol: "globe", group: group) { close(); ProjectActions.github(project) })
            list.append(LauncherAction(id: "pulls", title: L("Pull request'ler", "Pull requests"), symbol: "arrow.triangle.pull", group: group) {
                close(); ProjectActions.github(project, pulls: true)
            })
        }
        list.append(LauncherAction(id: "reveal", title: L("Finder'da göster", "Show in Finder"), symbol: "folder", group: group) { close(); ProjectActions.reveal(project) })
        list.append(LauncherAction(id: "copyPath", title: L("Yolu kopyala", "Copy path"), symbol: "doc.on.doc", group: group) { close(); ProjectActions.copyPath(project) })
        return list
    }
}
