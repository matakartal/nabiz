// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation

/// "tokyo", "time in london", "saat new york", "15:00 istanbul to tokyo", "9am pst to tsi".
@MainActor
enum WorldClock {
    private static let aliases: [String: String] = [
        "nyc": "America/New_York", "ny": "America/New_York", "new york": "America/New_York", "newyork": "America/New_York",
        "la": "America/Los_Angeles", "sf": "America/Los_Angeles", "san francisco": "America/Los_Angeles",
        "silicon valley": "America/Los_Angeles", "seattle": "America/Los_Angeles", "boston": "America/New_York",
        "miami": "America/New_York", "washington": "America/New_York", "dc": "America/New_York", "austin": "America/Chicago",
        "dallas": "America/Chicago", "houston": "America/Chicago", "abd": "America/New_York", "usa": "America/New_York",
        "londra": "Europe/London", "ingiltere": "Europe/London", "uk": "Europe/London", "moskova": "Europe/Moscow",
        "pekin": "Asia/Shanghai", "beijing": "Asia/Shanghai", "cin": "Asia/Shanghai", "china": "Asia/Shanghai",
        "singapur": "Asia/Singapore", "sidney": "Australia/Sydney", "viyana": "Europe/Vienna", "atina": "Europe/Athens",
        "roma": "Europe/Rome", "bruksel": "Europe/Brussels", "lizbon": "Europe/Lisbon", "varsova": "Europe/Warsaw",
        "prag": "Europe/Prague", "kahire": "Africa/Cairo", "tahran": "Asia/Tehran", "baku": "Asia/Baku",
        "tiflis": "Asia/Tbilisi", "kyiv": "Europe/Kiev", "kiev": "Europe/Kiev", "seul": "Asia/Seoul",
        "delhi": "Asia/Kolkata", "new delhi": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "bangalore": "Asia/Kolkata",
        "hindistan": "Asia/Kolkata", "india": "Asia/Kolkata", "turkiye": "Europe/Istanbul", "turkey": "Europe/Istanbul",
        "ankara": "Europe/Istanbul", "izmir": "Europe/Istanbul", "antalya": "Europe/Istanbul", "almanya": "Europe/Berlin",
        "germany": "Europe/Berlin", "munih": "Europe/Berlin", "munich": "Europe/Berlin", "frankfurt": "Europe/Berlin",
        "fransa": "Europe/Paris", "france": "Europe/Paris", "japonya": "Asia/Tokyo", "japan": "Asia/Tokyo",
        "hollanda": "Europe/Amsterdam", "isvicre": "Europe/Zurich", "zurih": "Europe/Zurich", "ispanya": "Europe/Madrid",
        "italya": "Europe/Rome", "yunanistan": "Europe/Athens", "rusya": "Europe/Moscow", "kanada": "America/Toronto",
        "avustralya": "Australia/Sydney", "brezilya": "America/Sao_Paulo", "sao paulo": "America/Sao_Paulo",
        "meksika": "America/Mexico_City", "mexico city": "America/Mexico_City", "dubai": "Asia/Dubai", "bae": "Asia/Dubai",
        "abu dabi": "Asia/Dubai", "katar": "Asia/Qatar", "doha": "Asia/Qatar", "riyad": "Asia/Riyadh", "kudus": "Asia/Jerusalem",
        "tel aviv": "Asia/Jerusalem", "hong kong": "Asia/Hong_Kong", "taipei": "Asia/Taipei", "bangkok": "Asia/Bangkok",
        "jakarta": "Asia/Jakarta", "manila": "Asia/Manila", "lagos": "Africa/Lagos", "nairobi": "Africa/Nairobi",
        "utc": "UTC", "gmt": "GMT", "tsi": "Europe/Istanbul", "trt": "Europe/Istanbul",
    ]
    private static let abbreviations: Set<String> = ["est", "edt", "cst", "cdt", "mst", "mdt", "pst", "pdt", "cet", "cest",
                                                      "eet", "eest", "bst", "jst", "kst", "aest", "msk", "hkt", "sgt"]
    private static let fillers: Set<String> = ["time", "saat", "saati", "kac", "now", "simdi", "what", "whats", "is", "it",
                                               "the", "current", "su", "an", "anda", "in", "at", "de", "da", "te", "ta"]
    private static let separators: Set<String> = ["to", "->", "→", "=>", "icin", "is"]

    /// City (as Foundation names it, lowercased, spaces) → time zone id.
    private static let cities: [String: String] = {
        var map: [String: String] = [:]
        for id in TimeZone.knownTimeZoneIdentifiers {
            guard let city = id.split(separator: "/").last else { continue }
            map[Fuzzy.fold(city.replacingOccurrences(of: "_", with: " "))] = id
        }
        return map
    }()

    static func zone(_ phrase: String) -> TimeZone? {
        let key = phrase.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        if let id = aliases[key] ?? cities[key] { return TimeZone(identifier: id) }
        if abbreviations.contains(key) { return TimeZone(abbreviation: key.uppercased()) }
        return nil
    }

    static func name(_ zone: TimeZone) -> String {
        if zone.identifier == "UTC" || zone.identifier == "GMT" { return zone.identifier }
        return zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
    }

    static func evaluate(_ input: String, now: Date = Date()) -> [Calculator.Result]? {
        // "tokyo'da saat kaç?" → "tokyo saat kac"
        let cleaned = Fuzzy.fold(input).replacingOccurrences(of: "?", with: " ").replacingOccurrences(of: "'", with: " ")
            .replacingOccurrences(of: "’", with: " ").replacingOccurrences(of: ",", with: " ")
        var words = cleaned.split(separator: " ").map(String.init)
        guard !words.isEmpty, words.count <= 8 else { return nil }

        // An optional time first: "15:00", "9am", "9 pm", "21".
        var time: (hour: Int, minute: Int)?
        if let first = words.first, let parsed = clock(first, next: words.count > 1 ? words[1] : nil) {
            time = parsed.time
            words.removeFirst(parsed.used)
        }
        let separator = words.firstIndex { separators.contains($0) }
        let left = (separator.map { Array(words[..<$0]) } ?? words).filter { !fillers.contains($0) }
        let right = separator.map { Array(words[($0 + 1)...]).filter { !fillers.contains($0) } } ?? []
        guard let from = zone(left.joined(separator: " ")) else { return nil }
        // A bare number before a city isn't a time unless it looks like one ("21 tokyo" is fine, "5 tokyo" too).
        let to = right.isEmpty ? nil : zone(right.joined(separator: " "))
        if !right.isEmpty && to == nil { return nil }

        var calendar = Calendar(identifier: .gregorian)
        let local = TimeZone.current
        func format(_ date: Date, _ zone: TimeZone, day: Bool = false) -> String {
            var style = Date.FormatStyle(date: day ? .abbreviated : .omitted, time: .shortened).locale(Format.locale)
            style.timeZone = zone
            return date.formatted(style)
        }
        func offset(_ a: TimeZone, _ b: TimeZone, at date: Date) -> String {
            let hours = Double(b.secondsFromGMT(for: date) - a.secondsFromGMT(for: date)) / 3600
            if hours == 0 { return L("aynı saat", "same time") }
            let text = hours.rounded() == hours ? String(Int(hours)) : String(format: "%.1f", hours)
            return (hours > 0 ? "+" : "") + text + L(" sa", " h")
        }

        if let time {
            // That clock time in `from`, shown in `to` (or here).
            calendar.timeZone = from
            guard let moment = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now) else { return nil }
            let target = to ?? local
            let dayShift = dayDifference(moment, from, target)
            let shift = dayShift == 0 ? "" : (dayShift > 0 ? L(" (ertesi gün)", " (next day)") : L(" (önceki gün)", " (day before)"))
            let text = "\(format(moment, from)) \(name(from)) = \(format(moment, target)) \(name(target))\(shift)"
            return [Calculator.Result(text: text, copy: format(moment, target), note: offset(from, target, at: moment))]
        }
        if let to {
            let text = "\(name(from)) \(format(now, from)) · \(name(to)) \(format(now, to))"
            return [Calculator.Result(text: text, copy: format(now, to), note: offset(from, to, at: now))]
        }
        var weekday = Date.FormatStyle().weekday(.wide).day().month(.abbreviated).locale(Format.locale)
        weekday.timeZone = from
        let text = "\(name(from)) \(format(now, from)) · \(now.formatted(weekday))"
        return [Calculator.Result(text: text, copy: format(now, from), note: offset(local, from, at: now))]
    }

    /// Reads "15:00", "9:30pm", "9am" or "9" followed by "am"/"pm".
    private static func clock(_ word: String, next: String?) -> (time: (hour: Int, minute: Int), used: Int)? {
        let pattern = #"^(\d{1,2})(?:[:.](\d{2}))?(am|pm)?$"#
        guard let match = word.firstMatch(of: try! Regex(pattern)) else { return nil }
        guard var hour = match.output[1].substring.flatMap({ Int($0) }) else { return nil }
        let minute = match.output[2].substring.flatMap { Int($0) } ?? 0
        var meridiem = match.output[3].substring.map(String.init)
        var used = 1
        if meridiem == nil, let next, next == "am" || next == "pm" { meridiem = next; used = 2 }
        // A lone small number ("5 tokyo") is too vague to be a time; it needs ":mm" or am/pm, or be 13–23.
        if match.output[2].substring == nil && meridiem == nil && hour < 13 { return nil }
        if meridiem == "pm" && hour < 12 { hour += 12 }
        if meridiem == "am" && hour == 12 { hour = 0 }
        guard hour < 24, minute < 60 else { return nil }
        return ((hour, minute), used)
    }

    private static func dayDifference(_ date: Date, _ a: TimeZone, _ b: TimeZone) -> Int {
        var ca = Calendar(identifier: .gregorian), cb = Calendar(identifier: .gregorian)
        ca.timeZone = a
        cb.timeZone = b
        let da = ca.dateComponents([.year, .month, .day], from: date), db = cb.dateComponents([.year, .month, .day], from: date)
        guard let x = Calendar(identifier: .gregorian).date(from: da), let y = Calendar(identifier: .gregorian).date(from: db) else { return 0 }
        return Int((y.timeIntervalSince(x) / 86_400).rounded())
    }
}

/// "today + 30 days", "bugün + 3 hafta", "2026-12-31 - today", "days until 2027-01-01", "1.1.2027'ye kaç gün",
/// "31.12.2026" (its weekday and how far away), "today" (the date and week number).
@MainActor
enum DateMath {
    private static let datePattern = #"(today|bugun|now|simdi|tomorrow|yarin|yesterday|dun|\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[./]\d{1,2}[./]\d{4})"#
    private static let unitPattern = #"(days?|gun|weeks?|hafta|months?|ay|years?|yil)"#

    static func evaluate(_ input: String, now: Date = Date()) -> [Calculator.Result]? {
        let text = Fuzzy.fold(input).replacingOccurrences(of: "'", with: " ").replacingOccurrences(of: "?", with: " ")
            .split(separator: " ").joined(separator: " ")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        // date ± n units
        if let match = text.firstMatch(of: try! Regex("^\(datePattern)\\s*([+-])\\s*(\\d{1,5})\\s*\(unitPattern)$")),
           let base = date(String(match.output[1].substring ?? ""), today: today),
           let amount = Int(match.output[3].substring ?? "") {
            let sign = match.output[2].substring == "-" ? -1 : 1
            let component: Calendar.Component = switch String(match.output[4].substring ?? "") {
            case "week", "weeks", "hafta": .weekOfYear
            case "month", "months", "ay": .month
            case "year", "years", "yil": .year
            default: .day
            }
            guard let result = calendar.date(byAdding: component, value: sign * amount, to: base) else { return nil }
            return [describe(result, today: today)]
        }
        // date - date
        if let match = text.firstMatch(of: try! Regex("^\(datePattern)\\s*-\\s*\(datePattern)$")),
           let a = date(String(match.output[1].substring ?? ""), today: today),
           let b = date(String(match.output[2].substring ?? ""), today: today) {
            return [span(days(from: b, to: a), detail: nil)]
        }
        // days until a date: "days until X", "until X", "X kac gun", "X ye kac gun", "X e kac gun kaldi"
        let untilBefore = try! Regex("^(?:how many days until|days until|until|kac gun var|kac gun)\\s+\(datePattern)$")
        let untilAfter = try! Regex("^\(datePattern)\\s*(?:a|e|ya|ye|na|ne)?\\s*(?:kac gun(?: var| kaldi)?|kalan gun|until)$")
        if let match = text.firstMatch(of: untilBefore) ?? text.firstMatch(of: untilAfter),
           let target = date(String(match.output[1].substring ?? ""), today: today) {
            let count = days(from: today, to: target)
            return [span(count, detail: target.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(Format.locale)))]
        }
        // a date on its own
        if let match = text.firstMatch(of: try! Regex("^\(datePattern)$")) {
            let word = String(match.output[1].substring ?? "")
            guard let target = date(word, today: today) else { return nil }
            if word == "today" || word == "bugun" || word == "now" || word == "simdi" {
                let week = calendar.component(.weekOfYear, from: target)
                let day = calendar.ordinality(of: .day, in: .year, for: target) ?? 0
                let text = target.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(Format.locale))
                return [Calculator.Result(text: text, copy: target.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(Format.locale)),
                                          note: L("\(week). hafta · yılın \(day). günü", "week \(week) · day \(day)"))]
            }
            return [describe(target, today: today)]
        }
        return nil
    }

    private static func date(_ word: String, today: Date) -> Date? {
        let calendar = Calendar.current
        switch word {
        case "today", "bugun", "now", "simdi": return today
        case "tomorrow", "yarin": return calendar.date(byAdding: .day, value: 1, to: today)
        case "yesterday", "dun": return calendar.date(byAdding: .day, value: -1, to: today)
        default: break
        }
        let parts = word.split(whereSeparator: { "-./".contains($0) }).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let (year, month, day) = word.contains("-") ? (parts[0], parts[1], parts[2]) : (parts[2], parts[1], parts[0])
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components), calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    private static func days(from a: Date, to b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: a), to: Calendar.current.startOfDay(for: b)).day ?? 0
    }

    private static func describe(_ date: Date, today: Date) -> Calculator.Result {
        let count = days(from: today, to: date)
        let when = count == 0 ? L("bugün", "today") : count > 0 ? L("\(count) gün sonra", "in \(count) days") : L("\(-count) gün önce", "\(-count) days ago")
        return Calculator.Result(text: date.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(Format.locale)),
                                 copy: date.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(Format.locale)), note: when)
    }

    private static func span(_ count: Int, detail: String?) -> Calculator.Result {
        let weeks = abs(count) / 7, rest = abs(count) % 7
        let breakdown = weeks > 0 ? L(" (\(weeks) hafta \(rest) gün)", " (\(weeks) weeks \(rest) day\(rest == 1 ? "" : "s"))") : ""
        return Calculator.Result(text: L("\(count) gün", "\(count) days") + (rest == 0 && weeks > 0 ? L(" (\(weeks) hafta)", " (\(weeks) weeks)") : breakdown),
                                 copy: "\(count)", raw: "\(count)", note: detail)
    }
}
