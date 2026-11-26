import AppKit
import Darwin
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import Observation

// MARK: - Network

struct NetworkRate: Sendable {
    var down: Double
    var up: Double
}

/// Bytes per second over Wi-Fi, Ethernet and cellular, summed. VPN tunnels are skipped so traffic is not counted twice.
actor NetworkSampler {
    private var last: (down: UInt64, up: UInt64, time: UInt64)?

    func sample() -> NetworkRate? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var down: UInt64 = 0, up: UInt64 = 0
        var cursor = list
        while let ifa = cursor {
            cursor = ifa.pointee.ifa_next
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.pointee.ifa_data else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            down += UInt64(stats.ifi_ibytes)
            up += UInt64(stats.ifi_obytes)
        }
        let now = DispatchTime.now().uptimeNanoseconds
        let previous = last
        last = (down, up, now)
        // The counters are 32-bit and wrap; a wrapped sample reads as zero for one tick.
        guard let previous, now > previous.time, down >= previous.down, up >= previous.up else {
            return NetworkRate(down: 0, up: 0)
        }
        let seconds = Double(now - previous.time) / 1_000_000_000
        return NetworkRate(down: Double(down - previous.down) / seconds, up: Double(up - previous.up) / seconds)
    }
}

/// The first IPv4 address on Wi-Fi or Ethernet.
enum LocalIP {
    static func address() -> String? {
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
        return found["en0"] ?? found.sorted { $0.key < $1.key }.first?.value
    }
}

// MARK: - Battery

struct BatteryState: Sendable {
    var percent: Int
    var charging: Bool
    var plugged: Bool
    var minutesLeft: Int?
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
            let time = d[kIOPSTimeToEmptyKey] as? Int ?? -1
            return BatteryState(percent: current * 100 / max,
                                charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                                plugged: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                                minutesLeft: time > 0 ? time : nil)
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
