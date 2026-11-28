// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import SwiftUI

/// Open Hyperliquid positions of the wallet set in Settings → Markets: the account first, then one row per
/// position with its open profit or loss. A dot turns orange near liquidation and red when it is very close.
struct PositionsSection: View {
    let actions: PanelActions
    private let store = PositionStore.shared

    var body: some View {
        if let account = store.account {
            PanelRow(icon: .symbol("wallet.bifold"), title: L("Hesap", "Account"), subtitle: PositionText.accountSubtitle(account),
                     action: { open(Hyperliquid.url("portfolio")?.absoluteString ?? "") }) { _ in
                Value(Format.dollars(account.accountValue), color: Theme.text)
            }
            .help(accountDetails(account))
            ForEach(account.positions) { position in
                PositionRow(position: position) { if let url = position.tradeURL { open(url.absoluteString) } }
            }
        } else if store.failed {
            PanelRow(icon: .symbol("wifi.exclamationmark"), title: L("Bağlanılamadı", "Couldn't connect"),
                     action: { store.retry() }) { _ in
                Value(L("Tekrar dene", "Try again"), color: Palette.green.mark)
            }
        } else {
            PanelRow(icon: .symbol("wallet.bifold"), title: L("Yükleniyor…", "Loading…")) { _ in
                ProgressView().controlSize(.mini)
            }
        }
    }

    private func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        actions.close()
        NSWorkspace.shared.open(url)
    }

    /// "Withdrawable $9,870 · Hyperliquid $16,320 · XYZ $2,100 · click to open on Hyperliquid".
    private func accountDetails(_ account: HyperliquidAccount) -> String {
        var parts = [L("Çekilebilir \(Format.dollars(account.withdrawable))", "Withdrawable \(Format.dollars(account.withdrawable))")]
        if account.dexes.count > 1 {
            parts += account.dexes.map { "\(MarketStore.shared.dexTitle($0.dex)) \(Format.dollars($0.accountValue))" }
        }
        parts.append(L("Hyperliquid'de açmak için tıkla", "click to open on Hyperliquid"))
        return parts.joined(separator: " · ")
    }
}

/// "● BTC  Long 5x · 0,25 · liq 47.900      +$476.00"; hovering offers Trade.
private struct PositionRow: View {
    let position: PerpPosition
    let open: () -> Void

    var body: some View {
        let pnl = position.unrealizedPnl
        PanelRow(icon: .dot(dotColor), title: position.name, subtitle: PositionText.subtitle(position), action: open) { hovering in
            if hovering {
                InlineButton(L("İşlem", "Trade")) { open() }
            } else {
                Value(Format.dollars(pnl, signed: true),
                      color: abs(pnl) < 0.005 ? Theme.textMuted : pnl > 0 ? Palette.green.mark : Theme.warning.mark)
            }
        }
        .help(PositionText.details(position, fundingRate: MarketStore.shared.markets[position.coin]?.funding))
    }

    private var dotColor: Color {
        switch position.risk {
        case .safe: Theme.textMuted
        case .near: Theme.warning.fill
        case .close: Theme.danger
        }
    }
}

extension PositionSummary.Tone {
    var color: Color {
        switch self {
        case .muted: Theme.textMuted
        case .up: Palette.green.mark
        case .down, .warning: Theme.warning.mark
        }
    }
}
