// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import IOKit

// MARK: - Battery health

struct BatteryHealth: Sendable, Equatable {
    /// Full-charge capacity against the design capacity, 0...1 (what System Settings calls "Maximum Capacity").
    var health: Double?
    var cycles: Int?
    /// The connected charger's rating, when plugged in.
    var adapterWatts: Int?
}

enum BatteryHealthReader {
    /// From the AppleSmartBattery service; nil on Macs without a battery. No privileges needed.
    static func read() -> BatteryHealth? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }

        let design = number("DesignCapacity", in: properties)
        // Newer Macs report the real full-charge capacity as NominalChargeCapacity (inside BatteryData); older ones
        // as AppleRawMaxCapacity. MaxCapacity is already a percentage on Apple silicon, so it is not used.
        let full = number("AppleRawMaxCapacity", in: properties) ?? number("NominalChargeCapacity", in: properties)
        var health: Double?
        if let design, let full, design > 0 { health = min(full / design, 1) }

        let adapter = (properties["AdapterDetails"] as? [String: Any]).flatMap { number("Watts", in: $0) }
        let plugged = properties["ExternalConnected"] as? Bool ?? false
        return BatteryHealth(health: health,
                             cycles: number("CycleCount", in: properties).map { Int($0) },
                             adapterWatts: plugged ? adapter.map { Int($0) } : nil)
    }

    /// The first value for `key`, looking into nested dictionaries too.
    private static func number(_ key: String, in dict: [String: Any]) -> Double? {
        if let value = dict[key] as? NSNumber { return value.doubleValue }
        for value in dict.values {
            if let nested = value as? [String: Any], let found = number(key, in: nested) { return found }
        }
        return nil
    }
}

// MARK: - Security checklist

struct SecurityCheck: Identifiable, Sendable, Equatable {
    enum Kind: String, Sendable, CaseIterable {
        case fileVault, firewall, gatekeeper, sip, autoUpdates
    }

    let kind: Kind
    let on: Bool
    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .fileVault: "FileVault"
        case .firewall: L("Güvenlik duvarı", "Firewall")
        case .gatekeeper: "Gatekeeper"
        case .sip: L("Sistem bütünlüğü (SIP)", "System Integrity (SIP)")
        case .autoUpdates: L("Güvenlik güncellemeleri", "Security updates")
        }
    }

    /// The System Settings pane where it is turned on.
    var settingsURL: URL? {
        switch kind {
        case .fileVault, .gatekeeper:
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")
        case .firewall:
            URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall")
        // SIP can only be turned back on from Recovery; there is no pane for it.
        case .sip: nil
        case .autoUpdates:
            URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")
        }
    }
}

enum SecurityChecker {
    /// Five read-only checks with the system's own tools; none needs administrator rights. Takes about a second.
    static func run() async -> [SecurityCheck] {
        async let fileVault = Toolbox.run("/usr/bin/fdesetup", ["status"])
        async let firewall = Toolbox.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
        async let gatekeeper = output("/usr/sbin/spctl", ["--status"])
        async let sip = Toolbox.run("/usr/bin/csrutil", ["status"])
        let updates = UserDefaults(suiteName: "/Library/Preferences/com.apple.SoftwareUpdate")?
            .object(forKey: "CriticalUpdateInstall") as? Bool

        var checks: [SecurityCheck] = []
        if let text = await fileVault { checks.append(SecurityCheck(kind: .fileVault, on: text.contains("is On"))) }
        if let text = await firewall { checks.append(SecurityCheck(kind: .firewall, on: text.contains("enabled"))) }
        if let text = await gatekeeper { checks.append(SecurityCheck(kind: .gatekeeper, on: text.contains("enabled"))) }
        if let text = await sip { checks.append(SecurityCheck(kind: .sip, on: text.contains("enabled"))) }
        // "Install security responses and system files"; unset means the system default, which is on.
        checks.append(SecurityCheck(kind: .autoUpdates, on: updates ?? true))
        return checks
    }

    /// spctl prints its answer on stderr and exits non-zero when assessments are disabled, so read both streams.
    private static func output(_ path: String, _ arguments: [String]) async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}
