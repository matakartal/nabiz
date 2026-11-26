// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import Foundation

/// Every kind of suggestion, each with its own switch in Settings → Suggestions.
enum AdviceKind: String, CaseIterable, Identifiable {
    case memory, cpu, thermal, disk, battery, batteryHealth, aiBurn, docker, rust, claude, security, uptime
    case unpushed, devCleanup, simulators, notarize

    var id: String { rawValue }
    var prefKey: String { "advice.\(rawValue)" }
    var isOn: Bool { Prefs.bool(prefKey) }

    var title: String {
        switch self {
        case .memory: L("Bellek dolunca", "Memory runs out")
        case .cpu: L("İşlemci uzun süre yoğunsa", "CPU stays busy")
        case .thermal: L("Mac ısınınca", "Mac gets hot")
        case .disk: L("Disk dolmak üzereyse", "Disk almost full")
        case .battery: L("Pil azalınca", "Battery low")
        case .batteryHealth: L("Pil yıprandıysa", "Battery worn")
        case .aiBurn: L("AI limiti hızlı bitiyorsa", "AI limit burning fast")
        case .docker: L("Docker boşta bellek tutuyorsa", "Docker idle with memory")
        case .rust: L("Rust önbelleği büyüdüyse", "Rust caches grew")
        case .claude: L("Çok fazla Claude Code işlemi", "Too many Claude Code processes")
        case .security: L("Güvenlik ayarı kapalıysa", "A security setting is off")
        case .uptime: L("Uzun süredir yeniden başlatılmadıysa", "Not restarted for long")
        case .unpushed: L("Commit'ler gönderilmeden kaldıysa", "Commits left unpushed")
        case .devCleanup: L("Geliştirici çöpü biriktiyse", "Developer leftovers piled up")
        case .simulators: L("Birden çok simülatör açıksa", "Several simulators running")
        case .notarize: L("Apple notarize ederken", "While Apple notarizes")
        }
    }

    /// When it shows, in one line, for the settings list.
    var detail: String {
        switch self {
        case .memory: L("Bellek baskısı yarım dakika sürünce ya da takas alanı şişince; en çok yer kaplayanı kapatır.",
                        "When memory pressure lasts half a minute or swap swells; quits what takes the most.")
        case .cpu: L("İşlemci 2 dakika %90'ın üstünde kalınca; en çok yorana tek dokunuş.",
                     "When the CPU stays above 90% for 2 minutes; one tap for what works it hardest.")
        case .thermal: L("macOS işlemciyi yavaşlatmaya başlayınca.", "When macOS starts slowing the processor down.")
        case .disk: L("10 GB'ın altında kalınca; 3 GB'ın altı kırmızı.", "Under 10 GB free; under 3 GB turns red.")
        case .battery: L("Prizde değilken %15'in altında; %5'te kırmızı.", "Unplugged under 15%; red at 5%.")
        case .batteryHealth: L("Kapasite %80'in altına inince.", "When capacity drops under 80%.")
        case .aiBurn: L("Açtığın bir limit sıfırlanmadan önce bitecek hızdaysa.", "When a limit you turned on will run out before it resets.")
        case .docker: L("Konteyner yokken 2 GB'tan fazla tutunca.", "Over 2 GB held with no containers running.")
        case .rust: L("target/ klasörleri 10 GB'ı geçince.", "When target/ folders pass 10 GB.")
        case .claude: L("20'den fazla işlem açık kalınca.", "With more than 20 processes open.")
        case .security: L("Aşağıda seçtiğin kontrollerden biri kapalıysa.", "When one of the checks you pick below is off.")
        case .uptime: L("7 günü geçip takas alanı dolunca, ya da 30 günü geçince.", "Past 7 days with swap in use, or past 30 days.")
        case .unpushed: L("Bir projede 1 günden eski commit'ler gönderilmemişse.", "When a project has commits older than a day that aren't pushed.")
        case .devCleanup: L("Simülatör, worktree, build ve paket artıkları 20 GB'ı geçince.", "When simulator, worktree, build and package leftovers pass 20 GB.")
        case .simulators: L("3 ya da daha fazla simülatör aynı anda açıkken.", "With 3 or more simulators running at once.")
        case .notarize: L("notarytool submit sürerken; bitince bildirim gelir.", "While notarytool submit runs; a notification comes when it's done.")
        }
    }

    static func registerDefaults() {
        var defaults: [String: Any] = [:]
        allCases.forEach { defaults[$0.prefKey] = true }
        SecurityCheck.Kind.allCases.forEach { defaults[$0.prefKey] = $0.watchedByDefault }
        UserDefaults.standard.register(defaults: defaults)
    }
}

extension SecurityCheck.Kind {
    var prefKey: String { "security.\(rawValue)" }
    /// Whether an off state turns into a suggestion.
    var isWatched: Bool { Prefs.bool(prefKey) }

    /// The firewall ships off on macOS and matters little behind a home router, so it isn't nagged about unless asked.
    var watchedByDefault: Bool { self != .firewall }

    /// Most important first: the one named when several are off.
    var priority: Int {
        switch self {
        case .fileVault: 0
        case .sip: 1
        case .gatekeeper: 2
        case .autoUpdates: 3
        case .firewall: 4
        }
    }

    /// What being off means, in plain words.
    var risk: String {
        switch self {
        case .fileVault: L("Mac kaybolursa dosyaların okunabilir.", "If the Mac is lost, your files can be read.")
        case .sip: L("Sistem dosyaları değiştirilmeye açık.", "System files are open to changes.")
        case .gatekeeper: L("İmzasız uygulamalar uyarısız açılıyor.", "Unsigned apps open without a warning.")
        case .autoUpdates: L("Güvenlik yamaları kendiliğinden gelmiyor.", "Security fixes don't arrive on their own.")
        case .firewall: L("Gelen bağlantılar süzülmüyor; ortak Wi‑Fi'da önemli.", "Incoming connections aren't filtered; matters on public Wi‑Fi.")
        }
    }
}

/// "Hide until tomorrow": a hidden suggestion comes back when the time is up, or sooner if it gets more serious.
enum AdviceSnooze {
    static let key = "adviceSnoozed"

    private static var all: [String: [String: Double]] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Double]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func isHidden(_ advice: Advice) -> Bool {
        guard let entry = all[advice.id], let until = entry["until"], let level = entry["level"] else { return false }
        return Date().timeIntervalSince1970 < until && advice.level.rawValue <= Int(level)
    }

    static func hide(_ advice: Advice, for seconds: TimeInterval) {
        var list = all.filter { ($0.value["until"] ?? 0) > Date().timeIntervalSince1970 }
        list[advice.id] = ["until": Date().timeIntervalSince1970 + seconds, "level": Double(advice.level.rawValue)]
        all = list
    }

    static var count: Int { all.values.filter { ($0["until"] ?? 0) > Date().timeIntervalSince1970 }.count }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
