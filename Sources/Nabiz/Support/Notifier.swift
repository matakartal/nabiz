import Foundation
import UserNotifications

/// Opt-in alerts for the two things worth interrupting for: memory turning critical, and an AI limit almost used up.
/// Each fires once per episode: memory again only after it recovered, an AI window again only after it reset.
@MainActor
final class Notifier {
    static let shared = Notifier()

    private var memoryWasCritical = false
    private var warnedLimits: Set<String> = []

    /// Asks macOS for permission; the setting stays off if the user declines.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if !granted {
                Task { @MainActor in UserDefaults.standard.set(false, forKey: Prefs.notifications) }
            }
        }
    }

    func check(monitor: Monitor) {
        guard Prefs.bool(Prefs.notifications) else { return }

        let critical = monitor.system?.pressure == .critical
        if critical && !memoryWasCritical {
            let advice = monitor.advice.first { $0.id == "memory" }
            send(id: "memory", title: L("Bellek kritik seviyede", "Memory is critical"),
                 body: advice?.detail ?? L("Ağır uygulamaları kapat.", "Quit heavy apps."))
        }
        memoryWasCritical = critical

        for status in AILimitsStore.shared.statuses {
            for limit in status.limits {
                // One alert per window: the key carries the reset time, so a new window can warn again.
                let key = "\(limit.id)@\(limit.resetsAt?.timeIntervalSince1970 ?? 0)"
                guard limit.remaining < 0.1, !warnedLimits.contains(key) else { continue }
                warnedLimits.insert(key)
                let reset = limit.resetsAt.map { L(" \(Format.countdown(until: $0)) sonra sıfırlanır.", " Resets in \(Format.countdown(until: $0)).") } ?? ""
                send(id: key, title: L("\(status.provider.shortName) limiti bitmek üzere", "\(status.provider.shortName) limit almost used"),
                     body: L("\(limit.label): \(Format.percent(limit.remaining)) kaldı.", "\(limit.label): \(Format.percent(limit.remaining)) left.") + reset)
            }
        }
    }

    private func send(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
