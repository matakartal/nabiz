import AppKit
import Observation

/// Things Nabız can do on a schedule, without asking — the user set them up.
enum ScheduledAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case darkModeOn, darkModeOff, keepAwakeOff, shutdownSimulators, quitDocker
    case cleanRust, cleanXcode, clearClipboard, displayOff, reminder
    case devCleanup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .darkModeOn: L("Karanlık modu aç", "Turn on dark mode")
        case .darkModeOff: L("Açık moda geç", "Switch to light mode")
        case .keepAwakeOff: L("Uyanık kalmayı kapat", "Stop keeping awake")
        case .shutdownSimulators: L("Simülatörleri kapat", "Shut down simulators")
        case .quitDocker: L("Docker'ı kapat", "Quit Docker")
        case .cleanRust: L("Rust önbelleğini temizle", "Clean Rust caches")
        case .cleanXcode: L("Xcode önbelleğini temizle", "Clean Xcode cache")
        case .clearClipboard: L("Panoyu temizle", "Clear the clipboard")
        case .displayOff: L("Ekranı kapat", "Turn the display off")
        case .reminder: L("Hatırlatma göster", "Show a reminder")
        case .devCleanup: L("Geliştirici temizliği (güvenli olanlar)", "Developer clean-up (the safe ones)")
        }
    }

    var symbol: String {
        switch self {
        case .darkModeOn: "moon.fill"
        case .darkModeOff: "sun.max.fill"
        case .keepAwakeOff: "cup.and.saucer"
        case .shutdownSimulators: "iphone.slash"
        case .quitDocker: "shippingbox"
        case .cleanRust: "gearshape.2"
        case .cleanXcode: "hammer"
        case .clearClipboard: "clipboard"
        case .displayOff: "moon.zzz"
        case .reminder: "bell"
        case .devCleanup: "sparkles.rectangle.stack"
        }
    }
}

struct ScheduledTask: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var action: ScheduledAction
    var hour: Int
    var minute: Int
    /// Calendar weekdays it runs on: 1 = Sunday … 7 = Saturday.
    var weekdays: Set<Int> = Set(1...7)
    var enabled = true
    /// For reminders.
    var note = ""
    var lastRun: Date?

    var timeText: String { String(format: "%02d:%02d", hour, minute) }

    /// Today's run time, if today is one of its days.
    func scheduled(on day: Date, calendar: Calendar = .current) -> Date? {
        guard weekdays.contains(calendar.component(.weekday, from: day)) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// The next time it will run, within a week.
    func next(after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let time = scheduled(on: day, calendar: calendar), time > now else { continue }
            return time
        }
        return nil
    }
}

/// Runs scheduled tasks. Checked on every tick: a task runs once its time has come today, and is made up within
/// six hours if the Mac was asleep; later than that it waits for its next day.
@MainActor
@Observable
final class Scheduler {
    static let shared = Scheduler()
    private static let key = "scheduledTasks"
    static let catchUp: TimeInterval = 6 * 3600

    private(set) var tasks: [ScheduledTask] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key) {
            tasks = (try? JSONDecoder().decode([ScheduledTask].self, from: data)) ?? []
        }
    }

    /// Ready-made tasks offered in Settings.
    static var presets: [ScheduledTask] {
        [
            ScheduledTask(action: .cleanRust, hour: 3, minute: 0),
            ScheduledTask(action: .devCleanup, hour: 3, minute: 30, weekdays: [1]),
            ScheduledTask(action: .darkModeOn, hour: 19, minute: 0),
            ScheduledTask(action: .darkModeOff, hour: 8, minute: 0),
            ScheduledTask(action: .shutdownSimulators, hour: 18, minute: 30, weekdays: Set(2...6)),
            ScheduledTask(action: .keepAwakeOff, hour: 23, minute: 0),
        ]
    }

    func add(_ task: ScheduledTask) {
        var task = task
        task.id = UUID()
        // Starts from now: a time already passed today waits for its next day.
        task.lastRun = Date()
        tasks.append(task)
        save()
    }

    func update(_ task: ScheduledTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        save()
    }

    func remove(_ task: ScheduledTask) {
        tasks.removeAll { $0.id == task.id }
        save()
    }

    func runNow(_ task: ScheduledTask) {
        perform(task)
        markRun(task.id, at: Date())
    }

    func check(now: Date = Date()) {
        for task in tasks where task.enabled {
            guard let time = task.scheduled(on: now), time <= now, now.timeIntervalSince(time) < Self.catchUp,
                  (task.lastRun ?? .distantPast) < time else { continue }
            perform(task)
            markRun(task.id, at: now)
            Notifier.shared.post(id: "task-\(task.id)-\(Int(now.timeIntervalSince1970))",
                                 title: task.action == .reminder ? (task.note.isEmpty ? L("Hatırlatma", "Reminder") : task.note)
                                                                 : L("Zamanlanmış görev çalıştı", "Scheduled task ran"),
                                 body: task.action == .reminder ? task.timeText : "\(task.action.title) · \(task.timeText)")
        }
    }

    private func markRun(_ id: UUID, at date: Date) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].lastRun = date
        save()
    }

    private func perform(_ task: ScheduledTask) {
        let toolbox = Toolbox.shared
        switch task.action {
        case .darkModeOn: toolbox.setDarkMode(true)
        case .darkModeOff: toolbox.setDarkMode(false)
        case .keepAwakeOff: KeepAwake.shared.stop()
        case .shutdownSimulators: Task.detached(priority: .utility) { Simulators.shutdownAll() }
        case .quitDocker:
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.docker.docker").forEach { $0.terminate() }
        case .cleanRust: toolbox.cleanRustUnattended()
        case .cleanXcode: toolbox.cleanDerivedDataUnattended()
        case .devCleanup: DevCleanupStore.shared.cleanSafe(notify: true)
        case .clearClipboard: NSPasteboard.general.clearContents()
        case .displayOff: Task { _ = await Toolbox.run("/usr/bin/pmset", ["displaysleepnow"]) }
        case .reminder: break // the notification is the reminder
        }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(tasks), forKey: Self.key)
    }
}
