// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

@Suite("Scheduled tasks")
struct SchedulerTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }

    /// Wednesday 26 November 2026, 10:00 in Istanbul.
    var wednesday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 10))! }

    @Test("Today's time only on chosen weekdays")
    func scheduledToday() {
        let daily = ScheduledTask(action: .cleanRust, hour: 3, minute: 0)
        #expect(daily.scheduled(on: wednesday, calendar: calendar) != nil)
        let weekends = ScheduledTask(action: .cleanRust, hour: 3, minute: 0, weekdays: [1, 7])
        #expect(weekends.scheduled(on: wednesday, calendar: calendar) == nil)
    }

    @Test("Next run: later today, else the next chosen day")
    func next() throws {
        let evening = ScheduledTask(action: .darkModeOn, hour: 19, minute: 0)
        let today = try #require(evening.next(after: wednesday, calendar: calendar))
        #expect(calendar.component(.day, from: today) == 26)
        #expect(calendar.component(.hour, from: today) == 19)

        let morning = ScheduledTask(action: .darkModeOff, hour: 8, minute: 0)
        #expect(calendar.component(.day, from: try #require(morning.next(after: wednesday, calendar: calendar))) == 27)

        let mondays = ScheduledTask(action: .shutdownSimulators, hour: 9, minute: 0, weekdays: [2])
        let monday = try #require(mondays.next(after: wednesday, calendar: calendar))
        #expect(calendar.component(.weekday, from: monday) == 2)
        #expect(calendar.component(.day, from: monday) == 30)
    }

    @Test("Time text")
    func timeText() {
        #expect(ScheduledTask(action: .reminder, hour: 7, minute: 5).timeText == "07:05")
    }
}

@MainActor
@Suite("AI alerts")
struct AIAlertTests {
    @Test("One alert per window, even when the reset time drifts, and none again within 12 hours")
    func once() throws {
        let defaults = try #require(UserDefaults(suiteName: "nabiz-tests-\(UUID())"))
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let now = reset.addingTimeInterval(-86_400)
        #expect(AIAlertLog.shouldSend("low", limit: "claude.week", resetsAt: reset, now: now, defaults: defaults))
        #expect(!AIAlertLog.shouldSend("low", limit: "claude.week", resetsAt: reset.addingTimeInterval(37), now: now.addingTimeInterval(60), defaults: defaults))
        #expect(!AIAlertLog.shouldSend("low", limit: "claude.week", resetsAt: reset.addingTimeInterval(7200), now: now.addingTimeInterval(3600), defaults: defaults))
        #expect(AIAlertLog.shouldSend("burn", limit: "claude.week", resetsAt: reset, now: now, defaults: defaults))
        #expect(AIAlertLog.shouldSend("low", limit: "claude.week", resetsAt: reset.addingTimeInterval(7 * 86_400), now: reset.addingTimeInterval(3600), defaults: defaults))
    }
}
