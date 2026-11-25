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
