// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Darwin
import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import Observation
import SystemConfiguration

// MARK: - Network

struct NetworkRate: Sendable {
    var down: Double
    var up: Double
}

/// Bytes per second over Wi-Fi, Ethernet and cellular, summed. VPN tunnels are skipped so traffic is not counted twice.
actor NetworkSampler {
    private var last: (counters: [String: NetworkCounters.Pair], time: UInt64)?

    func sample() -> NetworkRate? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var counters: [String: NetworkCounters.Pair] = [:]
        var cursor = list
        while let ifa = cursor {
            cursor = ifa.pointee.ifa_next
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.pointee.ifa_data else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            counters[name] = .init(down: stats.ifi_ibytes, up: stats.ifi_obytes)
        }
        let now = DispatchTime.now().uptimeNanoseconds
        let previous = last
        last = (counters, now)
        guard let previous, now > previous.time else { return NetworkRate(down: 0, up: 0) }
        let bytes = NetworkCounters.delta(from: previous.counters, to: counters)
        let seconds = Double(now - previous.time) / 1_000_000_000
        return NetworkRate(down: Double(bytes.down) / seconds, up: Double(bytes.up) / seconds)
    }
}

/// The traffic between two readings of the interfaces' byte counters.
enum NetworkCounters {
    struct Pair: Sendable, Equatable {
        var down: UInt32
        var up: UInt32
    }

    /// Compared interface by interface: one that just appeared (a dock plugged in, a hotspot) has no earlier
    /// reading and counts nothing yet, instead of its whole total showing as one huge burst. The counters are 32-bit
    /// and wrap around; wrapping subtraction reads the traffic across the wrap correctly.
    static func delta(from old: [String: Pair], to new: [String: Pair]) -> (down: UInt64, up: UInt64) {
        var down: UInt64 = 0, up: UInt64 = 0
        for (name, now) in new {
            guard let before = old[name] else { continue }
            down += UInt64(now.down &- before.down)
            up += UInt64(now.up &- before.up)
        }
        return (down, up)
    }
}

/// Bytes per second read from and written to the disks, from IOKit's per-disk statistics.
actor DiskIOSampler {
    private var last: (read: UInt64, written: UInt64, time: UInt64)?

    func sample() -> (read: Double, write: Double)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, written: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, nil, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            written += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        let now = DispatchTime.now().uptimeNanoseconds
        let previous = last
        last = (read, written, now)
        // A disk that went away makes the totals drop: skip that one reading.
        guard let previous, now > previous.time, read >= previous.read, written >= previous.written else { return nil }
        let seconds = Double(now - previous.time) / 1_000_000_000
        return (Double(read - previous.read) / seconds, Double(written - previous.written) / seconds)
    }
}

/// The interface the Mac is online through, by its name in System Settings ("Wi-Fi", "Ethernet"), and its address.
struct NetworkLink: Sendable, Equatable {
    var kind: String
    var address: String
    var isWiFi: Bool

    /// "en0" → "Wi-Fi", from SystemConfiguration; no location permission is needed for this (unlike the Wi-Fi name).
    static func current() -> NetworkLink? {
        guard let (name, address) = LocalIP.primary() else { return nil }
        let interface = (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface])?.first { SCNetworkInterfaceGetBSDName($0) as String? == name }
        let type = interface.flatMap { SCNetworkInterfaceGetInterfaceType($0) as String? }
        return NetworkLink(kind: interface.flatMap { SCNetworkInterfaceGetLocalizedDisplayName($0) as String? } ?? name,
                           address: address, isWiFi: type == kSCNetworkInterfaceTypeIEEE80211 as String)
    }
}

/// The first IPv4 address on Wi-Fi or Ethernet.
enum LocalIP {
    static func address() -> String? { primary()?.address }

    /// The interface and its address: en0 first, else the first other one that has an address.
    static func primary() -> (name: String, address: String)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var found: [String: String] = [:]
        var cursor = list
        while let ifa = cursor {
            cursor = ifa.pointee.ifa_next
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            found[name] = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        if let en0 = found["en0"] { return ("en0", en0) }
        return found.sorted { $0.key < $1.key }.first.map { ($0.key, $0.value) }
    }
}

// MARK: - Battery

struct BatteryState: Sendable {
    var percent: Int
    var charging: Bool
    var plugged: Bool
    var minutesLeft: Int?
    /// While charging: minutes until full, once macOS has worked it out.
    var minutesToFull: Int?
}

enum Battery {
    /// nil on Macs without a battery.
    static func read() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            // -1 means macOS is still working it out.
            let time = d[kIOPSTimeToEmptyKey] as? Int ?? -1
            let toFull = d[kIOPSTimeToFullChargeKey] as? Int ?? -1
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            return BatteryState(percent: current * 100 / max,
                                charging: charging,
                                plugged: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                                minutesLeft: time > 0 ? time : nil,
                                minutesToFull: charging && toFull > 0 ? toFull : nil)
        }
        return nil
    }
}

// MARK: - Keep awake

/// Stops the display from sleeping, for a while or until turned off. Released when Nabız quits.
@MainActor
@Observable
final class KeepAwake {
    static let shared = KeepAwake()

    @ObservationIgnored private var assertion: IOPMAssertionID = 0
    private(set) var isOn = false
    private(set) var until: Date?
    @ObservationIgnored private var timer: Task<Void, Never>?

    func start(minutes: Int?) {
        stop()
        Monitor.panelActions.flash(minutes.map { L("Uyanık: \(Format.duration(Double($0) * 60))", "Awake for \(Format.duration(Double($0) * 60))") }
                                   ?? L("Uyanık: süresiz", "Awake until stopped"))
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn), "Nabız" as CFString, &id)
        guard result == kIOReturnSuccess else { return }
        assertion = id
        isOn = true
        if let minutes {
            until = Date().addingTimeInterval(Double(minutes) * 60)
            timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(minutes * 60))
                if !Task.isCancelled { self?.stop() }
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if isOn { IOPMAssertionRelease(assertion) }
        isOn = false
        until = nil
    }
}

// MARK: - Countdown timer

/// A kitchen timer in the menu bar: counts down, then plays a sound and posts a notification.
@MainActor
@Observable
final class CountdownTimer {
    static let shared = CountdownTimer()

    private(set) var endsAt: Date?
    private(set) var minutes = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool { endsAt.map { $0 > Date() } ?? false }

    /// "12:34", or "1:02:03" past an hour.
    var remainingText: String? {
        guard let endsAt, endsAt > Date() else { return nil }
        let seconds = Int(endsAt.timeIntervalSinceNow.rounded(.up))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    func start(minutes: Int) {
        stop()
        self.minutes = minutes
        Monitor.panelActions.flash(L("Zamanlayıcı: \(minutes) dk", "Timer: \(minutes) min"))
        let end = Date().addingTimeInterval(Double(minutes) * 60)
        endsAt = end
        Notifier.shared.requestPermission(keepSetting: true)
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        endsAt = nil
    }

    private func finish() {
        endsAt = nil
        task = nil
        NSSound(named: "Glass")?.play()
        Notifier.shared.post(id: "timer-\(Date().timeIntervalSince1970)",
                             title: L("Süre doldu", "Time's up"),
                             body: L("\(minutes) dakikalık zamanlayıcı bitti.", "Your \(minutes)-minute timer is done."))
    }
}
