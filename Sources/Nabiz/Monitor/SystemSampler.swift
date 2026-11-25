import Darwin
import Foundation
import IOKit

enum Pressure: Int, Sendable {
    case normal, warning, critical
}

struct SystemSnapshot: Sendable {
    /// Share of all cores in use, 0...1.
    var cpu: Double
    var cores: Int
    var load: Double
    /// Activity Monitor's "Memory Used": app memory + wired + compressed.
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var pressure: Pressure
    var swapUsed: UInt64
    var swapTotal: UInt64
    /// Busiest GPU, 0...1; nil when the GPU does not report it.
    var gpu: Double?
    var diskFree: UInt64?
    var bootDate: Date?
    /// ProcessInfo.ThermalState raw value (0 nominal ... 3 critical).
    var thermal: Int

    var memoryFraction: Double { memoryTotal == 0 ? 0 : Double(memoryUsed) / Double(memoryTotal) }
    var swapFraction: Double { swapTotal == 0 ? 0 : Double(swapUsed) / Double(swapTotal) }
}

/// Reads machine-wide counters. CPU needs two reads: the first call returns 0.
actor SystemSampler {
    private let host = mach_host_self()
    private var lastTicks: (busy: UInt64, total: UInt64)?

    func sample() -> SystemSnapshot {
        let (used, total) = memory()
        let swap = swapUsage()
        return SystemSnapshot(
            cpu: cpu(),
            cores: ProcessInfo.processInfo.activeProcessorCount,
            load: loadAverage(),
            memoryUsed: used,
            memoryTotal: total,
            pressure: pressure(),
            swapUsed: swap.used,
            swapTotal: swap.total,
            gpu: gpuUtilization(),
            diskFree: diskFree(),
            bootDate: bootDate(),
            thermal: ProcessInfo.processInfo.thermalState.rawValue
        )
    }

    private func cpu() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        defer { lastTicks = (busy, total) }
        guard let last = lastTicks, total > last.total, busy >= last.busy else { return 0 }
        return Double(busy - last.busy) / Double(total - last.total)
    }

    private func memory() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let page = UInt64(getpagesize())
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = internalPages > purgeable ? internalPages - purgeable : 0
        let used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (min(used, total), total)
    }

    private func pressure() -> Pressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 4...: return .critical
        case 2...: return .warning
        default: return .normal
        }
    }

    private func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }

    private func loadAverage() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) > 0 ? loads[0] : 0
    }

    private func bootDate() -> Date? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000)
    }

    private func diskFree() -> UInt64? {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage.map { UInt64(max($0, 0)) }
    }

    /// Apple GPUs publish "Device Utilization %" under PerformanceStatistics; no privileges needed.
    private func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var busiest: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let value = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, nil, 0)?
                .takeRetainedValue() as? [String: Any],
                let utilization = value["Device Utilization %"] as? NSNumber
            else { continue }
            busiest = max(busiest ?? 0, utilization.doubleValue / 100)
        }
        return busiest
    }
}
