// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

@Suite("Pace")
struct PaceTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let week: TimeInterval = 7 * 86_400

    private func read(used: Double, hoursLeft: Double, period: TimeInterval? = nil, recent: Double? = nil) -> PaceReading? {
        PaceModel.read(used: used, resetsAt: now.addingTimeInterval(hoursLeft * 3600), period: period ?? week,
                       recentRate: recent, now: now)
    }

    @Test("An even pace lands at about 100%: on track")
    func evenPace() throws {
        // Half the week gone, 48% used: projected 96%.
        let pace = try #require(read(used: 0.48, hoursLeft: 84))
        #expect(pace.status == .onTrack)
        #expect(abs(pace.projected - 0.96) < 0.001)
        #expect(abs(pace.expected - 0.5) < 0.001)
        #expect(pace.runway == nil)
    }

    @Test("Light use is ahead")
    func ahead() throws {
        let pace = try #require(read(used: 0.2, hoursLeft: 84))
        #expect(pace.status == .ahead)
    }

    @Test("Heavy use runs out before the reset, with a runway")
    func behind() throws {
        // 5-hour window, 62% used after 1.5 h: 0.413/h, so the remaining 38% lasts about 55 minutes.
        let pace = try #require(read(used: 0.62, hoursLeft: 3.5, period: 5 * 3600))
        #expect(pace.status == .behind)
        let runway = try #require(pace.runway)
        #expect(abs(runway / 60 - 55.2) < 1)
    }

    @Test("A recent burst beats a quiet average")
    func recentBurst() throws {
        // 30% used over 68 h is slow, but 5% in the last hour is not.
        let quiet = try #require(read(used: 0.3, hoursLeft: 100))
        #expect(quiet.status == .ahead)
        let burst = try #require(read(used: 0.3, hoursLeft: 100, recent: 0.05 / 3600))
        #expect(burst.status == .behind)
    }

    @Test("Used up is spent")
    func spent() throws {
        #expect(try #require(read(used: 1, hoursLeft: 2)).status == .spent)
    }

    @Test("Too early or past the reset: no reading")
    func noReading() {
        #expect(read(used: 0.01, hoursLeft: 168 - 0.001) == nil)
        #expect(read(used: 0.5, hoursLeft: -1) == nil)
        #expect(PaceModel.read(used: 0.5, resetsAt: now.addingTimeInterval(3600), period: nil, recentRate: nil, now: now) == nil)
    }

    @Test("Unused near reset: over half left, under a day to go, multi-day window")
    func unused() throws {
        #expect(try #require(read(used: 0.2, hoursLeft: 20)).unusedNearReset)
        #expect(try #require(read(used: 0.6, hoursLeft: 20)).unusedNearReset == false)
        #expect(try #require(read(used: 0.2, hoursLeft: 2, period: 5 * 3600)).unusedNearReset == false)
    }

    @Test("History: recent rate needs 15 minutes, and a reset starts over")
    func history() {
        var history = PaceHistory()
        let start = now.addingTimeInterval(-1800)
        history.record("w", used: 0.10, at: start)
        #expect(history.recentRate("w", now: start) == nil)
        history.record("w", used: 0.13, at: start.addingTimeInterval(1800))
        let rate = history.recentRate("w", now: now)
        #expect(rate.map { abs($0 - 0.03 / 1800) < 1e-9 } == true)
        history.record("w", used: 0.01, at: now.addingTimeInterval(60))
        #expect(history.recentRate("w", now: now.addingTimeInterval(60)) == nil)
    }
}
