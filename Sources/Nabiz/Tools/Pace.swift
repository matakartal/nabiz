// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import Foundation

/// Where a usage window is heading: will it last until it resets, and if not, when does it run out?
///
/// Two speeds are measured. The window's average (used so far ÷ time so far) is steady but slow to notice a
/// sudden burst; the recent rate (the change over the last hour of readings) catches one at once. The faster of the
/// two drives the projection, so a burn is never hidden by a quiet start to the window.
struct PaceReading: Sendable, Equatable {
    enum Status: Sendable, Equatable {
        /// Projected to finish the window with at least 10% left.
        case ahead
        /// Projected to land between 90% and 100%.
        case onTrack
        /// Projected to run out before the reset.
        case behind
        /// Already used up.
        case spent
    }

    let status: Status
    /// Share of the limit used by the reset at the current speed (1 = exactly used up; can exceed 1).
    let projected: Double
    /// Where an even pace would be now: the share of the window that has passed (0...1).
    let expected: Double
    /// Time until the limit runs out at the current speed, when that comes before the reset.
    let runway: TimeInterval?
    /// More than half of a multi-day window left with under a day to go: use it or lose it.
    let unusedNearReset: Bool
}

enum PaceModel {
    /// A reading needs at least a minute and 1% of the window behind it, and a reset still ahead.
    static func read(used: Double, resetsAt: Date?, period: TimeInterval?, recentRate: Double?,
                     now: Date = Date()) -> PaceReading? {
        guard let resetsAt, let period, period > 0 else { return nil }
        let timeLeft = resetsAt.timeIntervalSince(now)
        let elapsed = period - timeLeft
        guard timeLeft > 0, elapsed >= max(60, period * 0.01) else { return nil }
        let expected = min(max(elapsed / period, 0), 1)
        let unused = period > 86_400 && timeLeft <= 86_400 && used < 0.5

        if used >= 1 {
            return PaceReading(status: .spent, projected: used, expected: expected, runway: 0, unusedNearReset: false)
        }

        // Share of the limit per second.
        let average = used / elapsed
        let rate = max(average, recentRate ?? 0)
        let projected = used + rate * timeLeft
        let runway: TimeInterval? = rate > 0 && projected > 1 ? (1 - used) / rate : nil

        let status: PaceReading.Status = projected > 1 ? .behind : projected > 0.9 ? .onTrack : .ahead
        return PaceReading(status: status, projected: projected, expected: expected, runway: runway, unusedNearReset: unused)
    }
}

/// Recent readings per limit, for the recent rate. Kept in memory: an hour of history is enough, and a restart
/// simply falls back on the window average until new readings arrive.
struct PaceHistory {
    private var samples: [String: [(date: Date, used: Double)]] = [:]

    mutating func record(_ id: String, used: Double, at date: Date = Date()) {
        var list = samples[id] ?? []
        // Usage went down: the window reset. Start over.
        if let last = list.last, used < last.used - 0.005 { list.removeAll() }
        list.append((date, used))
        list.removeAll { date.timeIntervalSince($0.date) > 2 * 3600 }
        samples[id] = list
    }

    /// Share of the limit per second over the last hour, once at least 15 minutes of readings exist.
    func recentRate(_ id: String, now: Date = Date()) -> Double? {
        guard let list = samples[id], let last = list.last,
              let first = list.first(where: { now.timeIntervalSince($0.date) <= 3600 }) else { return nil }
        let span = last.date.timeIntervalSince(first.date)
        guard span >= 15 * 60, last.used >= first.used else { return nil }
        return (last.used - first.used) / span
    }
}
