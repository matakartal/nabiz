// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Observation

/// Seven days of one-minute averages for CPU, RAM, GPU and the main AI limit, kept in a small file
/// (about 40 KB) in Application Support. Minutes the Mac was asleep stay empty instead of being made up.
@MainActor
@Observable
final class UsageHistory {
    static let shared = UsageHistory()

    enum Series: String, CaseIterable, Identifiable {
        case cpu, memory, gpu, ai
        var id: String { rawValue }
    }

    /// One stored minute; values are percentages 0...100, `Self.empty` where there is no reading.
    private struct Store: Codable {
        var start: Int = 0
        var values: [String: [UInt8]] = [:]
    }

    static let empty: UInt8 = 255
    private static let capacity = 7 * 24 * 60

    private var store = Store()
    @ObservationIgnored private var minute: Int?
    @ObservationIgnored private var sums: [Series: (total: Double, count: Int)] = [:]
    @ObservationIgnored private var savedAt = Date()

    private static var file: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nabiz")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("history.plist")
    }

    init() {
        if let data = try? Data(contentsOf: Self.file), let saved = try? PropertyListDecoder().decode(Store.self, from: data) {
            store = saved
        }
    }

    /// Adds one sample; a finished minute is stored as the average of its samples.
    func record(cpu: Double, memory: Double, gpu: Double?, ai: Double?, at date: Date = Date()) {
        let now = Int(date.timeIntervalSince1970 / 60)
        if let minute, minute != now { commit(minute) }
        minute = now
        add(.cpu, cpu)
        add(.memory, memory)
        if let gpu { add(.gpu, gpu) }
        if let ai { add(.ai, ai) }
        if date.timeIntervalSince(savedAt) > 600 { save() }
    }

    private func add(_ series: Series, _ value: Double) {
        let current = sums[series] ?? (0, 0)
        sums[series] = (current.total + value, current.count + 1)
    }

    private func commit(_ minute: Int) {
        if store.start == 0 { store.start = minute }
        let index = minute - store.start
        guard index >= 0 else { return }
        for series in Series.allCases {
            var list = store.values[series.rawValue] ?? []
            // Fill minutes with no samples (sleep, app not running) as empty.
            if list.count < index { list.append(contentsOf: repeatElement(Self.empty, count: index - list.count)) }
            let value = sums[series].map { UInt8(min(max($0.total / Double($0.count) * 100, 0), 100).rounded()) } ?? Self.empty
            if list.count == index { list.append(value) } else if index < list.count { list[index] = value }
            store.values[series.rawValue] = list
        }
        sums = [:]
        trim()
    }

    /// Keeps the last seven days.
    private func trim() {
        let longest = store.values.values.map(\.count).max() ?? 0
        let excess = longest - Self.capacity
        guard excess > 0 else { return }
        for key in store.values.keys { store.values[key] = Array(store.values[key]!.dropFirst(excess)) }
        store.start += excess
    }

    func save() {
        savedAt = Date()
        if let data = try? PropertyListEncoder().encode(store) { try? data.write(to: Self.file, options: .atomic) }
    }

    struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    /// The last `span` seconds averaged into `buckets` points; empty buckets are left out.
    func points(_ series: Series, span: TimeInterval, buckets: Int, now: Date = Date()) -> [Point] {
        guard let list = store.values[series.rawValue], !list.isEmpty, buckets > 0 else { return [] }
        let end = Int(now.timeIntervalSince1970 / 60)
        let first = end - Int(span / 60)
        let size = max(Int(span / 60) / buckets, 1)
        var result: [Point] = []
        var bucketStart = first
        while bucketStart < end {
            var total = 0.0, count = 0
            for minute in bucketStart..<min(bucketStart + size, end) {
                let index = minute - store.start
                guard index >= 0, index < list.count, list[index] != Self.empty else { continue }
                total += Double(list[index])
                count += 1
            }
            if count > 0 {
                result.append(Point(date: Date(timeIntervalSince1970: Double(bucketStart + size / 2) * 60), value: total / Double(count)))
            }
            bucketStart += size
        }
        return result
    }
}
