import AppKit
import SwiftUI

/// The projects most recently worked on: branch, changes and unpushed commits; hover to open them.
struct ProjectSection: View {
    @AppStorage(Prefs.projectCount) private var count = 5
    @Environment(\.flash) private var flash

    var body: some View {
        let store = ProjectStore.shared
        ForEach(store.recent.prefix(max(count, 1))) { project in
            PanelRow(icon: .symbol(Self.symbol(project)), title: project.displayName, subtitle: Self.subtitle(project), hoverable: true) { hovering in
                if hovering {
                    HStack(spacing: Theme.Spacing.m) {
                        if let editor = ProjectActions.preferredEditor {
                            InlineButton(editor.name) { ProjectActions.openInEditor(project) }
                        } else if project.xcode != nil {
                            InlineButton("Xcode") { ProjectActions.openInXcode(project) }
                        }
                        InlineButton("Terminal") { ProjectActions.terminal(project) }
                        ProjectMenu(project: project)
                    }
                } else {
                    Value(Self.badge(project))
                }
            }
            .help(project.path)
        }
    }

    static func symbol(_ project: Project) -> String {
        if project.stack.contains(.xcode) || project.stack.contains(.swift) { return "swift" }
        if project.stack.contains(.rust) { return "gearshape.2" }
        if project.stack.contains(.node) { return "curlybraces" }
        if project.stack.contains(.python) { return "chevron.left.forwardslash.chevron.right" }
        return "folder"
    }

    /// "main · 16 changed · 20 unpushed"
    static func subtitle(_ project: Project) -> String {
        [project.branch ?? L("bağımsız HEAD", "detached HEAD"), project.statusText].joined(separator: " · ")
    }

    /// "↑20 ●16" on the right; nothing when it's clean.
    static func badge(_ project: Project) -> String {
        var parts: [String] = []
        if project.ahead > 0 { parts.append("↑\(project.ahead)") }
        if project.behind > 0 { parts.append("↓\(project.behind)") }
        if project.changes > 0 { parts.append("●\(project.changes)") }
        return parts.joined(separator: " ")
    }

    /// "2 unpushed" in the closed header.
    static var summary: String {
        let unpushed = ProjectStore.shared.projects.filter { $0.ahead > 0 }.count
        if unpushed > 0 { return L("\(unpushed) gönderilmedi", "\(unpushed) unpushed") }
        return ProjectStore.shared.recent.first?.displayName ?? ""
    }
}

/// "⋯": everything else a project offers.
struct ProjectMenu: View {
    let project: Project

    var body: some View {
        Menu {
            ProjectMenuItems(project: project)
        } label: {
            Image(systemName: "ellipsis").font(Theme.body).foregroundStyle(Palette.green.mark)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct ProjectMenuItems: View {
    let project: Project

    var body: some View {
        ForEach(ProjectActions.installedEditors, id: \.bundleID) { editor in
            Button(L("\(editor.name) ile aç", "Open in \(editor.name)")) { ProjectActions.openInEditor(project, editor: editor) }
        }
        if project.xcode != nil { Button(L("Xcode ile aç", "Open in Xcode")) { ProjectActions.openInXcode(project) } }
        Button(L("Terminal'de aç", "Open in Terminal")) { ProjectActions.terminal(project) }
        Button(L("\(ProjectActions.agentName) başlat", "Start \(ProjectActions.agentName)")) { ProjectActions.agent(project) }
        if !project.scripts.isEmpty {
            Divider()
            ForEach(project.scripts, id: \.self) { script in
                Button(L("Çalıştır: \(script)", "Run: \(script)")) {
                    if ["dev", "start"].contains(script) { ProjectActions.startDev(project) } else { ProjectActions.runScript(project, script) }
                }
            }
        }
        if project.remote != nil {
            Divider()
            Button(L("GitHub'da aç", "Open on GitHub")) { ProjectActions.github(project) }
            Button(L("Pull request'ler", "Pull requests")) { ProjectActions.github(project, pulls: true) }
        }
        Divider()
        Button(L("Finder'da göster", "Show in Finder")) { ProjectActions.reveal(project) }
        Button(L("Yolu kopyala", "Copy path")) { ProjectActions.copyPath(project) }
    }
}

/// A QR code of a dev server's network address, so a phone on the same Wi-Fi opens it.
@MainActor
enum PhoneQR {
    private static var panel: NSPanel?

    /// The address a phone can open, or why it can't.
    static func address(for server: DevServer) -> (url: String?, problem: String?) {
        guard let port = server.ports.first else { return (nil, nil) }
        guard let ip = LocalIP.address() else { return (nil, L("Mac bir ağa bağlı değil.", "This Mac isn't on a network.")) }
        let url = "http://\(ip):\(port)"
        guard server.reachableOnNetwork else {
            return (url, L("\(server.tool) yalnızca bu Mac'e açık. Telefondan açmak için ağa aç: \(hostHint(server.tool))",
                           "\(server.tool) only listens on this Mac. To open it from a phone, start it on the network: \(hostHint(server.tool))"))
        }
        return (url, nil)
    }

    static func hostHint(_ tool: String) -> String {
        switch tool {
        case "vite", "astro", "nuxt", "nuxi": "--host"
        case "next", "next-server": "-H 0.0.0.0"
        case "wrangler": "--ip 0.0.0.0"
        case "http.server": "--bind 0.0.0.0"
        default: L("0.0.0.0'a bağla (--host)", "bind to 0.0.0.0 (--host)")
        }
    }

    static func show(_ server: DevServer) {
        let found = address(for: server)
        guard let url = found.url else {
            Monitor.panelActions.flash(found.problem ?? L("Adres yok", "No address"))
            return
        }
        panel?.close()
        let view = PhoneQRView(url: url, title: server.projectName, problem: found.problem) { panel?.close() }
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                             styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        panel = window
    }
}

struct PhoneQRView: View {
    let url: String
    let title: String
    let problem: String?
    let close: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Text(verbatim: title).font(Theme.body.weight(.semibold)).foregroundStyle(Theme.text)
            if let image = Capture.qrImage(url, scale: 8) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 200, height: 200)
                    .padding(Theme.Spacing.m).background(.white, in: RoundedRectangle(cornerRadius: Theme.fieldRadius))
                    .opacity(problem == nil ? 1 : 0.35)
            }
            Text(verbatim: url).font(Theme.body.monospaced()).foregroundStyle(Theme.textMuted).textSelection(.enabled)
            if let problem {
                Text(verbatim: problem).font(Theme.small).foregroundStyle(Theme.warning.mark)
                    .multilineTextAlignment(.center).frame(width: 240)
            } else {
                Text(verbatim: L("Telefon aynı Wi-Fi'da olmalı.", "The phone must be on the same Wi-Fi.")).font(Theme.small).foregroundStyle(Theme.textMuted)
            }
            HStack(spacing: Theme.Spacing.m) {
                Button(L("Kopyala", "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    close()
                    Monitor.panelActions.flash(L("Adres kopyalandı", "Address copied"))
                }
                Button(L("Kapat", "Close"), action: close).keyboardShortcut(.cancelAction)
            }
        }
        .padding(Theme.Spacing.l)
        .padding(.top, Theme.Spacing.m)
    }
}

/// Docker's containers, one row per compose project: how many run and their ports; start, stop, open, logs.
struct DockerSection: View {
    var body: some View {
        let store = DockerStore.shared
        ForEach(store.groups) { group in
            let busy = store.busy.contains(group.name)
            PanelRow(icon: .dot(group.running > 0 ? Palette.green.mark : Theme.textMuted), title: group.name,
                     subtitle: Self.subtitle(group), titleColor: group.orphaned && group.running == 0 ? Theme.warning.mark : nil, hoverable: !busy) { hovering in
                if busy {
                    ProgressView().controlSize(.mini)
                } else if hovering {
                    HStack(spacing: Theme.Spacing.m) {
                        if let port = group.ports.first, let url = URL(string: "http://localhost:\(port)") {
                            InlineButton(L("Aç", "Open")) { NSWorkspace.shared.open(url) }
                        }
                        InlineButton(group.running == 0 ? L("Başlat", "Start") : L("Durdur", "Stop"),
                                     role: group.running == 0 ? nil : .destructive) { store.toggle(group) }
                        Menu {
                            if group.running > 0 { Button(L("Yeniden başlat", "Restart")) { store.restart(group) } }
                            ForEach(group.containers) { container in
                                Menu(container.name) {
                                    Button(L("Günlükler", "Logs")) { store.logs(container) }
                                    if container.running { Button(L("Kabuk aç", "Open a shell")) { store.shell(container) } }
                                    ForEach(container.ports, id: \.self) { port in
                                        Button("localhost:\(port)") { NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!) }
                                    }
                                }
                            }
                            if let folder = group.folder, FileManager.default.fileExists(atPath: folder) {
                                Divider()
                                Button(L("Klasörü göster", "Show folder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
                            }
                            Divider()
                            Button(L("Kaldır…", "Remove…")) { store.remove(group) }
                        } label: {
                            Image(systemName: "ellipsis").font(Theme.body).foregroundStyle(Palette.green.mark)
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                } else {
                    Value(group.containers.count > 1 ? "\(group.running)/\(group.containers.count)" : (group.running > 0 ? "" : L("durdu", "stopped")))
                }
            }
            .help(group.orphaned ? L("Bu proje silinmiş bir klasörden başlatılmış; büyük ihtimalle artık gerekmiyor.",
                                     "Started from a folder that no longer exists; probably not needed any more.") : group.folder ?? group.containers.first?.image ?? "")
        }
    }

    /// ":5432 :6379 · Up 5 hours"
    static func subtitle(_ group: DockerGroup) -> String {
        var parts: [String] = []
        if group.orphaned { parts.append(L("klasörü yok", "folder gone")) }
        let ports = group.ports.prefix(4).map { ":\($0)" }.joined(separator: " ")
        if !ports.isEmpty { parts.append(ports) }
        if group.containers.count == 1, let status = group.containers.first?.status { parts.append(status) }
        return parts.isEmpty ? (group.containers.first?.image ?? "") : parts.joined(separator: " · ")
    }
}

/// "⋯" on a booted iOS simulator: status bar, appearance, links, screenshots, recording and its apps.
struct SimulatorMenu: View {
    let simulator: Simulator

    var body: some View {
        let tools = SimTools.shared
        let udid = simulator.id
        Menu {
            Button(tools.cleanBar.contains(udid) ? L("Durum çubuğunu eski hâline getir", "Restore the status bar")
                                                 : L("Durum çubuğu: 9:41, tam şarj", "Status bar: 9:41, full battery")) { tools.toggleStatusBar(udid) }
            Button(L("Karanlık mod", "Dark mode")) { tools.appearance(udid, dark: true) }
            Button(L("Açık mod", "Light mode")) { tools.appearance(udid, dark: false) }
            Divider()
            Button(L("Kopyalanan bağlantıyı aç", "Open the copied link")) { tools.openCopiedURL(udid) }
            Button(L("Ekran görüntüsü al ve düzenle", "Screenshot and mark up")) { tools.screenshot(udid) }
            Button(tools.recording?.udid == udid ? L("Kaydı durdur", "Stop recording") : L("Ekranı kaydet", "Record the screen")) { tools.toggleRecording(udid) }
            if let apps = tools.apps[udid], !apps.isEmpty {
                Divider()
                ForEach(apps) { app in
                    Menu(app.name) {
                        Button(L("Test bildirimi gönder", "Send a test notification")) { tools.push(udid, app: app) }
                        Button(L("Veri klasörünü aç", "Open its data folder")) { tools.openData(udid, app: app) }
                        Button(L("İzinleri sıfırla", "Reset permissions")) { tools.resetPermissions(udid, app: app) }
                    }
                }
            }
            Divider()
            Button(L("Simülatörü sıfırla…", "Erase the simulator…")) { tools.erase(udid, name: simulator.name) }
        } label: {
            Image(systemName: "ellipsis").font(Theme.body).foregroundStyle(Palette.green.mark)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
