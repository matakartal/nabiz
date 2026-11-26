// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import Foundation
import UserNotifications

/// Opt-in alerts for the two things worth interrupting for: memory turning critical, and an AI limit almost used up.
/// Each fires once per episode: memory again only after it recovered, an AI window again only after it reset.
@MainActor
final class Notifier {
    static let shared = Notifier()

    private var memoryWasCritical = false
    private var cpuWarned = false
    private var diskWarned = false
    private var batteryWarned = false

    /// Asks macOS for permission; the Notifications setting goes back off if the user declines
    /// (unless `keepSetting`, for price alerts, which don't depend on that setting).
    func requestPermission(keepSetting: Bool = false) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if !granted && !keepSetting {
                Task { @MainActor in UserDefaults.standard.set(false, forKey: Prefs.notifications) }
            }
        }
    }

    /// For features with their own opt-in (price alerts).
    func post(id: String, title: String, body: String) { send(id: id, title: title, body: body) }

    func check(monitor: Monitor) {
        guard Prefs.bool(Prefs.notifications) else { return }

        let critical = monitor.system?.pressure == .critical
        if critical && !memoryWasCritical {
            let advice = monitor.advice.first { $0.id == "memory" }
            send(id: "memory", title: L("Bellek kritik seviyede", "Memory is critical"),
                 body: advice?.detail ?? L("Ağır uygulamaları kapat.", "Quit heavy apps."))
        }
        memoryWasCritical = critical

        // CPU pinned above 90% for three minutes: name what is doing it.
        if let since = monitor.busySince, Date().timeIntervalSince(since) >= 180 {
            if !cpuWarned {
                cpuWarned = true
                let top = monitor.top(by: .cpu, count: 1).first
                send(id: "cpu", title: L("İşlemci 3 dakikadır çok yoğun", "CPU busy for 3 minutes"),
                     body: top.map { L("En çok \($0.name) kullanıyor (\(Format.percent($0.cpu))).", "\($0.name) uses the most (\(Format.percent($0.cpu))).") }
                         ?? L("Mac yavaşlayabilir ve ısınabilir.", "The Mac may slow down and heat up."))
            }
        } else if monitor.busySince == nil {
            cpuWarned = false
        }

        // Disk under 10 GB: once, until it is back above 15 GB.
        if let free = monitor.system?.diskFree {
            if free < 10 << 30, !diskWarned {
                diskWarned = true
                send(id: "disk", title: L("Disk dolmak üzere", "Disk almost full"),
                     body: L("\(Format.bytes(free)) boş kaldı. Nabız'daki Xcode temizliği ya da Depolama ayarları yardımcı olabilir.",
                             "\(Format.bytes(free)) left. Nabız's Clean Xcode or Storage settings can help."))
            } else if free > 15 << 30 {
                diskWarned = false
            }
        }

        // Battery at 10% on battery power: once per discharge.
        if let battery = monitor.battery {
            if !battery.plugged, battery.percent <= 10, !batteryWarned {
                batteryWarned = true
                send(id: "battery", title: L("Pil %\(battery.percent)", "Battery at \(battery.percent)%"),
                     body: L("Şarja takmazsan Mac yakında uyuyacak.", "Plug in soon, or the Mac will go to sleep."))
            } else if battery.plugged {
                batteryWarned = false
            }
        }

        for status in AILimitsStore.shared.statuses {
            for limit in status.limits {
                guard let pace = limit.pace else {
                    almostUsed(status, limit)
                    continue
                }
                if pace.status == .behind, let runway = pace.runway,
                   AIAlertLog.shouldSend("burn", limit: limit.id, resetsAt: limit.resetsAt) {
                    send(id: "burn-\(limit.id)",
                         title: L("\(status.provider.shortName) hızlı bitiyor", "\(status.provider.shortName) is burning fast"),
                         body: L("\(limit.label): bu hızla \(Format.duration(runway)) sonra biter, sıfırlanmadan önce.",
                                 "\(limit.label): at this speed it runs out in \(Format.duration(runway)), before it resets."))
                }
                if pace.unusedNearReset, AIAlertLog.shouldSend("unused", limit: limit.id, resetsAt: limit.resetsAt) {
                    send(id: "unused-\(limit.id)",
                         title: L("\(status.provider.shortName): kullan ya da kaybet", "\(status.provider.shortName): use it or lose it"),
                         body: L("\(limit.label) limitinin \(Format.percent(limit.remaining))'i duruyor ve bir günden az sonra sıfırlanıyor.",
                                 "\(Format.percent(limit.remaining)) of \(limit.label) is left and it resets in under a day."))
                }
                almostUsed(status, limit)
            }
        }
    }

    private func almostUsed(_ status: AIStatus, _ limit: AILimit) {
        guard limit.remaining < 0.1, AIAlertLog.shouldSend("low", limit: limit.id, resetsAt: limit.resetsAt) else { return }
        let reset = limit.resetsAt.map { L(" \(Format.countdown(until: $0)) sonra sıfırlanır.", " Resets in \(Format.countdown(until: $0)).") } ?? ""
        send(id: "low-\(limit.id)", title: L("\(status.provider.shortName) limiti bitmek üzere", "\(status.provider.shortName) limit almost used"),
             body: L("\(limit.label): \(Format.percent(limit.remaining)) kaldı.", "\(limit.label): \(Format.percent(limit.remaining)) left.") + reset)
    }

    private func send(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

/// Remembers, across restarts, which AI alerts were sent. Each kind of alert goes out at most once per limit window:
/// providers report the reset time a little differently on every reading, so the window is matched to the hour,
/// and the same alert never repeats within 12 hours whatever the provider reports.
@MainActor
enum AIAlertLog {
    private static let key = "aiAlertLog"
    static let cooldown: TimeInterval = 12 * 3600

    static func shouldSend(_ kind: String, limit: String, resetsAt: Date?, now: Date = Date(),
                           defaults: UserDefaults = .standard) -> Bool {
        var log = defaults.dictionary(forKey: key) as? [String: [Double]] ?? [:]
        let id = "\(kind):\(limit)"
        let window = ((resetsAt?.timeIntervalSince1970 ?? 0) / 3600).rounded()
        if let entry = log[id], entry.count == 2 {
            let (sentWindow, sentAt) = (entry[0], entry[1])
            let sameWindow = abs(sentWindow - window) <= 1
            if sameWindow || now.timeIntervalSince1970 - sentAt < cooldown { return false }
        }
        log[id] = [window, now.timeIntervalSince1970]
        defaults.set(log, forKey: key)
        return true
    }
}
