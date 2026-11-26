// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import SwiftUI

/// Settings → Developer: where projects open, the developer clean-up, notarization and what the launcher answers.
struct DeveloperPage: View {
    @AppStorage(Prefs.devEditor) private var editor = ""
    @AppStorage(Prefs.devAgent) private var agent = "claude"
    @AppStorage(Prefs.showProjects) private var showProjects = true
    @AppStorage(Prefs.projectCount) private var projectCount = 5
    @AppStorage(Prefs.showDocker) private var showDocker = true
    @AppStorage(Prefs.devStaleDays) private var staleDays = 30
    @AppStorage(Prefs.notaryWatch) private var notaryWatch = true
    @AppStorage(Prefs.notaryProfile) private var notaryProfile = ""

    var body: some View {
        let cleanup = DevCleanupStore.shared
        Form {
            Section {} header: { PageHeader(page: .developer) }
            SettingsSection("developer.projects") {
                Toggle(L("Panelde projeleri göster", "Show projects in the panel"), isOn: $showProjects)
                Picker(L("Kaç proje", "How many"), selection: $projectCount) {
                    ForEach([3, 5, 8, 12], id: \.self) { Text("\($0)").tag($0) }
                }
                .disabled(!showProjects)
                Picker(L("Projeyi aç", "Open projects in"), selection: $editor) {
                    Text(L("İlk yüklü editör", "First editor installed")).tag("")
                    ForEach(ProjectActions.installedEditors, id: \.bundleID) { Text($0.name).tag($0.bundleID) }
                }
                Picker(L("Kodlama ajanı", "Coding agent"), selection: $agent) {
                    Text("Claude Code").tag("claude")
                    Text("Codex").tag("codex")
                }
                Toggle(L("Panelde Docker konteynerlerini göster", "Show Docker containers in the panel"), isOn: $showDocker)
            } header: {
                Text(L("Projeler", "Projects"))
            } footer: {
                Footnote(L("~/Developer, ~/Projects, ~/code ve ~/src altındaki git depoları; dal, değişiklik ve gönderilmemiş commit'ler. Launcher'da proje adını yaz, ↩ editörde, ⌘↩ Terminal'de açar; ⌘K'da Xcode, ajan, npm script'leri ve GitHub.",
                           "Git repositories under ~/Developer, ~/Projects, ~/code and ~/src: branch, changes and unpushed commits. Type a project's name in the launcher: ↩ opens it in the editor, ⌘↩ in Terminal; ⌘K has Xcode, the agent, npm scripts and GitHub."))
            }
            SettingsSection("developer.cleanup") {
                HStack {
                    if cleanup.scanning {
                        ProgressView().controlSize(.small)
                        Text(L("Taranıyor…", "Scanning…")).foregroundStyle(.secondary)
                    } else if cleanup.scannedAt != nil {
                        Text(L("Toplam \(Format.bytes(cleanup.total))", "\(Format.bytes(cleanup.total)) in all")).font(.body.weight(.semibold))
                    } else {
                        Text(L("Ne kadar yer açılabileceğini görmek için tara.", "Scan to see how much space can be freed.")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if cleanup.safeTotal > 0 && !cleanup.scanning {
                        Button(L("Güvenli olanları temizle", "Clean the safe ones")) { cleanup.cleanSafe(notify: false) }
                    }
                    Button(cleanup.scannedAt == nil ? L("Tara", "Scan") : L("Yeniden tara", "Scan again")) { cleanup.scan() }
                        .disabled(cleanup.scanning)
                }
                ForEach(cleanup.items) { item in CleanupRow(item: item) }
                Picker(L("node_modules şu kadar dokunulmamışsa", "node_modules when untouched for"), selection: $staleDays) {
                    ForEach([14, 30, 60, 90], id: \.self) { Text(L("\($0) gün", "\($0) days")).tag($0) }
                }
            } header: {
                Text(L("Geliştirici temizliği", "Developer clean-up"))
            } footer: {
                Footnote(L("Hepsi sorulup temizlenir. \"Güvenli\" olanlar kendiliğinden geri gelir (önbellekler, eski tarayıcılar, kullanılamayan simülatörler); Görevler'den haftalık da çalıştırılabilir. Değişikliği olan worktree'lere, birleşmemiş dallara ve kodunuza hiç dokunulmaz.",
                           "Each one asks first. The \"safe\" ones come back on their own (caches, old browsers, unavailable simulators) and can also run weekly from Schedules. Worktrees with changes, unmerged branches and your code are never touched."))
            }
            SettingsSection("developer.notary") {
                Toggle(L("Notarize bitince haber ver", "Tell me when notarization finishes"), isOn: $notaryWatch)
                TextField(L("Anahtar zinciri profili", "Keychain profile"), text: $notaryProfile, prompt: Text(verbatim: "nabiz"))
                    .disabled(!notaryWatch)
            } header: {
                Text(L("Notarize", "Notarization"))
            } footer: {
                Footnote(L("`xcrun notarytool submit` çalışırken panelde görünür; bitince Apple'ın cevabı (Accepted / Invalid) bildirim olarak gelir. Arada Apple'a soru gönderilmez. Profil, komutta yazmıyorsa kullanılır.",
                           "While `xcrun notarytool submit` runs it shows in the panel; when it ends, Apple's answer (Accepted / Invalid) comes as a notification. Apple isn't asked in between. The profile is used when the command doesn't name one."))
            }
            SettingsSection("developer.launcher") {
                ForEach(Self.examples, id: \.0) { example in
                    LabeledContent {
                        Text(verbatim: example.1).foregroundStyle(.secondary)
                    } label: {
                        Text(verbatim: example.0).font(.body.monospaced())
                    }
                }
            } header: {
                Text(L("Launcher'da", "In the launcher"))
            } footer: {
                Footnote(L("Hepsi bu Mac'te hesaplanır; token ve anahtarlar AI'a ya da web aramasına gönderilmez.",
                           "All worked out on this Mac; tokens and keys are never sent to AI or a web search."))
            }
        }
        .formStyle(.grouped)
        .onAppear { if cleanup.scannedAt == nil { cleanup.scan() } }
    }

    static var examples: [(String, String)] {
        [
            (":3000", L("Portu kim tutuyor; durdur ya da aç", "Who holds the port; stop or open it")),
            ("port", L("Dinleyen tüm portlar", "Every listening port")),
            ("proj · nabiz", L("Projeler; editörde, Terminal'de, Xcode'da aç", "Projects; open in the editor, Terminal, Xcode")),
            ("eyJhbGci…", L("JWT çöz: içerik, bitiş", "Decode a JWT: payload, expiry")),
            ("1732636800 · now", L("Unix zamanı ↔ tarih", "Unix time ↔ date")),
            ("sha256 metin · hash metin", L("MD5, SHA-1, SHA-256, SHA-512", "MD5, SHA-1, SHA-256, SHA-512")),
            ("uuid · ulid · nanoid", L("Yeni kimlik", "A new id")),
            ("case hello world", L("camelCase, snake_case, kebab-case…", "camelCase, snake_case, kebab-case…")),
            ("#1db954 · rgb(…)", L("HEX, RGB, HSL, SwiftUI, UIKit, Compose", "HEX, RGB, HSL, SwiftUI, UIKit, Compose")),
            ("*/5 * * * 1-5", L("Cron ifadesini açıkla", "Explain a cron expression")),
            ("http 429", L("HTTP durum kodu", "HTTP status code")),
            ("base64 … · url …", L("Kodla ve çöz", "Encode and decode")),
        ]
    }
}

private struct CleanupRow: View {
    let item: CleanupItem

    var body: some View {
        let busy = DevCleanupStore.shared.cleaning.contains(item.kind)
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            Image(systemName: item.symbol).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: item.title)
                    if item.isSafe {
                        Text(L("güvenli", "safe")).font(.caption).foregroundStyle(Palette.green.mark)
                    }
                }
                Text(verbatim: item.detail.isEmpty ? item.explanation : item.detail)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .help(item.explanation)
            Spacer()
            Text(verbatim: item.size > 0 ? ([.pnpmStore, .dockerImages].contains(item.kind) ? "≤ " : "") + Format.bytes(item.size)
                                         : L("\(item.targets.count) dal", "\(item.targets.count) branches"))
                .monospacedDigit().foregroundStyle(.secondary)
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Button(L("Temizle", "Clean")) { DevCleanupStore.shared.clean(item) }
            }
        }
    }
}
