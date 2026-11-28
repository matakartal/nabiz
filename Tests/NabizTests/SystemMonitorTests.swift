// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

/// The network rate: read interface by interface, across the 32-bit counters wrapping around.
@Suite("System monitor")
struct SystemMonitorTests {
    @Test func aNewInterfaceIsNotABurst() {
        let before = ["en0": NetworkCounters.Pair(down: 1_000, up: 500)]
        // A dock plugged in with 3 GB already on its counter.
        let after = ["en0": NetworkCounters.Pair(down: 3_000, up: 600), "en7": .init(down: 3_000_000_000, up: 1_000)]
        let delta = NetworkCounters.delta(from: before, to: after)
        #expect(delta.down == 2_000 && delta.up == 100)
    }

    @Test func aWrappedCounterStillCounts() {
        let before = ["en0": NetworkCounters.Pair(down: UInt32.max - 99, up: 0)]
        let after = ["en0": NetworkCounters.Pair(down: 400, up: 10)]
        let delta = NetworkCounters.delta(from: before, to: after)
        #expect(delta.down == 500 && delta.up == 10)
    }

    @Test func anInterfaceThatWentAwayCountsNothing() {
        let before = ["en0": NetworkCounters.Pair(down: 10, up: 10), "en7": .init(down: 99, up: 99)]
        let delta = NetworkCounters.delta(from: before, to: ["en0": .init(down: 20, up: 20)])
        #expect(delta.down == 10 && delta.up == 10)
    }
}
