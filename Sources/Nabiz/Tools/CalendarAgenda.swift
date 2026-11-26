import AppKit
import EventKit
import SwiftUI

/// Today's meetings from the Mac's calendars (iCloud, Google, Exchange… whatever Calendar.app has): the panel
/// section, launcher rows, a heads-up a minute before a meeting, and one click to join its call.
/// Nothing is read until the calendar is turned on, which is when macOS asks for access.
@MainActor
@Observable
final class CalendarAgenda {
    static let shared = CalendarAgenda()

    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let allDay: Bool
        let calendar: String
        let calendarID: String
        let color: Color
        let location: String?
        let meetingURL: URL?

        var isNow: Bool { start <= Date() && end > Date() }
    }

    private(set) var authorized = false
    private(set) var denied = false
    /// Every event left today, then tomorrow's when today is done.
    private(set) var upcoming: [Event] = []
    private(set) var calendars: [(id: String, title: String, color: Color)] = []
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var alerted: Set<String> = []

    private init() { readStatus() }

    var enabled: Bool { Prefs.bool(Prefs.calendarEnabled) }

    /// The next timed event that hasn't ended, for the menu, the launcher and "join".
    var next: Event? { upcoming.first { !$0.allDay && $0.end > Date() } }

    private func readStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorized = status == .fullAccess
        denied = status == .denied || status == .restricted
    }

    /// Follows the setting: asks for access the first time, then keeps the list fresh.
    func update() {
        guard enabled else {
            upcoming = []
            return
        }
        readStatus()
        if !authorized && !denied {
            Task {
                _ = try? await store.requestFullAccessToEvents()
                readStatus()
                if authorized { observeChanges(); reload() }
            }
            return
        }
        guard authorized else { return }
        observeChanges()
        refreshIfNeeded()
    }

    private func observeChanges() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarAgenda.shared.reload() }
        }
    }

    func refreshIfNeeded() {
        guard enabled, authorized else { return }
        if let loadedAt, Date().timeIntervalSince(loadedAt) < 60, Calendar.current.isDateInToday(loadedAt) { return }
        reload()
    }

    func reload() {
        guard authorized else { return }
        loadedAt = Date()
        calendars = store.calendars(for: .event).map { ($0.calendarIdentifier, $0.title, Color(nsColor: $0.color)) }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        let today = events(from: Date(), to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!)
        if today.contains(where: { !$0.allDay }) {
            upcoming = today
        } else {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
            upcoming = today + events(from: tomorrow, to: Calendar.current.date(byAdding: .day, value: 1, to: tomorrow)!).filter { !$0.allDay }.prefix(3)
        }
    }

    /// From now until the end of the given number of days.
    func events(days: Int) -> [Event] {
        let end = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: Date()))!
        return events(from: Date(), to: end)
    }

    private func events(from start: Date, to end: Date) -> [Event] {
        guard authorized, start < end else { return [] }
        let hidden = Set(Prefs.string(Prefs.calendarHidden).split(separator: ",").map(String.init))
        let wanted = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !wanted.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: wanted)
        return store.events(matching: predicate)
            .filter { $0.endDate > start && $0.status != .canceled && !Self.declined($0) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { event in
                Event(id: (event.eventIdentifier ?? UUID().uuidString) + "@\(event.startDate.timeIntervalSince1970)",
                      title: event.title?.isEmpty == false ? event.title : L("(Başlıksız)", "(No title)"),
                      start: event.startDate, end: event.endDate, allDay: event.isAllDay,
                      calendar: event.calendar.title, calendarID: event.calendar.calendarIdentifier,
                      color: Color(nsColor: event.calendar.color),
                      location: event.location.flatMap { $0.isEmpty ? nil : $0 },
                      meetingURL: Self.meetingURL(event.url, event.location, event.notes))
            }
    }

    /// Meetings the user said no to stay out of the way.
    private static func declined(_ event: EKEvent) -> Bool {
        event.attendees?.first { $0.isCurrentUser }?.participantStatus == .declined
    }

    nonisolated private static let meetingHosts = ["zoom.us", "zoom.com", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com",
                                       "facetime.apple.com", "whereby.com", "around.co", "meet.jit.si", "gotomeeting.com", "chime.aws",
                                       "app.slack.com", "discord.gg", "discord.com"]

    /// The first link to a video call in the event's URL, location or notes.
    nonisolated static func meetingURL(_ url: URL?, _ location: String?, _ notes: String?) -> URL? {
        let isMeeting: (URL) -> Bool = { link in
            guard let host = link.host()?.lowercased() else { return false }
            return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        if let url, isMeeting(url) { return url }
        let text = [location, notes].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url).first(where: isMeeting)
    }

    func join(_ event: Event) {
        guard let url = event.meetingURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openInCalendar() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    /// Called every second: a notification a minute before each meeting, once.
    func tick() {
        guard enabled, authorized else { return }
        refreshIfNeeded()
        guard Prefs.bool(Prefs.calendarAlert) else { return }
        let now = Date()
        for event in upcoming where !event.allDay && !alerted.contains(event.id) {
            let left = event.start.timeIntervalSince(now)
            guard left <= 60 && left > -30 else { continue }
            alerted.insert(event.id)
            Notifier.shared.requestPermission(keepSetting: true)
            let body = event.meetingURL != nil
                ? L("Katılmak için panelde ya da başlatıcıda \"katıl\".", "Join from the panel, or type \"join\" in the launcher.")
                : event.location ?? event.calendar
            Notifier.shared.post(id: "calendar-\(event.id)", title: L("1 dk sonra: \(event.title)", "In 1 min: \(event.title)"), body: body)
        }
    }

    /// "10:00–10:30", "now · until 10:30", "all day".
    static func timeText(_ event: Event) -> String {
        if event.allDay { return L("tüm gün", "all day") }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        if event.isNow { return L("şimdi · \(end)'e kadar", "now · until \(end)") }
        let day = Calendar.current.isDateInTomorrow(event.start) ? L("yarın ", "tomorrow ") : ""
        return "\(day)\(start)–\(end)"
    }

    /// "in 12 min", "in 2 h", for the next meeting.
    static func untilText(_ event: Event) -> String {
        if event.isNow { return L("şimdi", "now") }
        let minutes = Int(event.start.timeIntervalSinceNow / 60) + 1
        if minutes < 60 { return L("\(minutes) dk sonra", "in \(minutes) min") }
        let hours = minutes / 60
        return Calendar.current.isDateInToday(event.start) ? L("\(hours) sa sonra", "in \(hours) h") : timeText(event)
    }
}
