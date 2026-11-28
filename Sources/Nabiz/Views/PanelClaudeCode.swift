// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import SwiftUI

/// Live Claude Code sessions: the ones waiting for you first, then the working ones, then the idle ones. Tapping one
/// brings its app forward.
struct ClaudeSessionSection: View {
    /// More than this and the rest fold under a "+N more" row.
    static let limit = 8
    @State private var showAll = false

    var body: some View {
        let sessions = ClaudeSessionStore.shared.sessions
        let hidden = showAll ? 0 : max(sessions.count - Self.limit, 0)
        ForEach(sessions.prefix(sessions.count - hidden)) { ClaudeSessionRow(session: $0) }
        if hidden > 0 {
            PanelRow(icon: .symbol("ellipsis"), title: L("+\(hidden) daha", "+\(hidden) more"), titleColor: Theme.textMuted,
                     action: { showAll = true }) { _ in EmptyView() }
        }
    }
}

/// "● Ultra paket farkı  nabiz · Work      Needs you": one line; "Show" on hover.
private struct ClaudeSessionRow: View {
    let session: ClaudeSession

    var body: some View {
        let store = ClaudeSessionStore.shared
        let canShow = store.canShow(session)
        PanelRow(icon: .dot(dot), title: ClaudeSessions.title(session), subtitle: store.subtitle(session),
                 action: canShow ? { store.show(session) } : nil) { hovering in
            if hovering {
                InlineButton(L("Göster", "Show")) { store.show(session) }
            } else {
                Value(ClaudeSessions.statusText(session), color: session.status == .waiting ? Theme.warning.mark : Theme.textMuted)
            }
        }
        .help(tooltip)
    }

    private var dot: Color {
        switch session.status {
        case .waiting: Theme.warning.fill
        case .busy: Theme.accent
        case .idle: Theme.textMuted
        }
    }

    /// The full folder, where it runs and when it started.
    private var tooltip: String {
        var lines = [(session.cwd as NSString).abbreviatingWithTildeInPath]
        var origin = ClaudeSessions.entrypointName(session.entrypoint)
        if let started = session.startedAt {
            origin += " · " + L("\(Format.duration(Date().timeIntervalSince(started))) önce başladı",
                                "started \(Format.duration(Date().timeIntervalSince(started))) ago")
        }
        lines.append(origin)
        if session.configDir != ClaudeSessions.defaultDir {
            lines.append((session.configDir as NSString).abbreviatingWithTildeInPath)
        }
        return lines.joined(separator: "\n")
    }
}
