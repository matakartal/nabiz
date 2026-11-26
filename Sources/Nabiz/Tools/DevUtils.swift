// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import CryptoKit
import Security
import Foundation

/// Small developer answers, computed on this Mac (nothing is sent anywhere): JWTs, Unix time, hashes, ids,
/// identifier cases, colours, cron and HTTP status codes. Pure functions, tested.
enum DevUtils {
    // MARK: JWT

    struct JWT: Equatable {
        let header: String
        let payload: String
        let algorithm: String?
        let expires: Date?
        let issued: Date?
        let subject: String?
        let issuer: String?
    }

    /// Decodes the header and payload (the signature isn't checked: there's no key here).
    static func jwt(_ text: String) -> JWT? {
        var token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") { token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, token.hasPrefix("eyJ"), let header = base64URL(String(parts[0])), let payload = base64URL(String(parts[1])),
              let headerJSON = try? JSONSerialization.jsonObject(with: header) as? [String: Any],
              let payloadJSON = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        func date(_ key: String) -> Date? { (payloadJSON[key] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } }
        return JWT(header: pretty(headerJSON), payload: pretty(payloadJSON), algorithm: headerJSON["alg"] as? String,
                   expires: date("exp"), issued: date("iat"), subject: payloadJSON["sub"] as? String, issuer: payloadJSON["iss"] as? String)
    }

    static func base64URL(_ text: String) -> Data? {
        var base = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base.count % 4 != 0 { base += "=" }
        return Data(base64Encoded: base)
    }

    private static func pretty(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Unix time

    /// 10 digits (seconds, 2001–2100) or 13 (milliseconds).
    static func epoch(_ text: String) -> Date? {
        let digits = text.trimmingCharacters(in: .whitespaces)
        guard digits.allSatisfy(\.isNumber), let value = Double(digits) else { return nil }
        switch digits.count {
        case 10 where value >= 978_307_200 && value < 4_102_444_800: return Date(timeIntervalSince1970: value)
        case 13 where value >= 978_307_200_000 && value < 4_102_444_800_000: return Date(timeIntervalSince1970: value / 1000)
        default: return nil
        }
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    // MARK: Hashes and ids

    enum HashKind: String, CaseIterable { case md5, sha1, sha256, sha512 }

    static func hash(_ text: String, _ kind: HashKind) -> String {
        let data = Data(text.utf8)
        let bytes: [UInt8] = switch kind {
        case .md5: Array(Insecure.MD5.hash(data: data))
        case .sha1: Array(Insecure.SHA1.hash(data: data))
        case .sha256: Array(SHA256.hash(data: data))
        case .sha512: Array(SHA512.hash(data: data))
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// A ULID: 48-bit time + 80 random bits, Crockford base32, sortable by creation time.
    static func ulid(date: Date = Date()) -> String {
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        var time = UInt64(date.timeIntervalSince1970 * 1000)
        var timePart = ""
        for _ in 0..<10 {
            timePart = String(alphabet[Int(time % 32)]) + timePart
            time /= 32
        }
        var random = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, random.count, &random)
        return timePart + String(random.map { alphabet[Int($0) % 32] })
    }

    /// nanoid's default: 21 URL-safe characters.
    static func nanoid(length: Int = 21) -> String {
        let alphabet = Array("useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { alphabet[Int($0) & 63] })
    }

    // MARK: Identifier cases

    enum Case: String, CaseIterable {
        case camel, pascal, snake, kebab, constant

        var title: String {
            switch self {
            case .camel: "camelCase"
            case .pascal: "PascalCase"
            case .snake: "snake_case"
            case .kebab: "kebab-case"
            case .constant: "CONSTANT_CASE"
            }
        }
    }

    /// "Hello world", "helloWorld", "hello_world", "HelloWorld" → ["hello", "world"].
    static func words(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for character in text {
            if character.isLetter || character.isNumber {
                if let previous, character.isUppercase, previous.isLowercase || previous.isNumber, !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                current.append(character)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
            previous = character
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.lowercased() }
    }

    static func convert(_ text: String, to style: Case) -> String {
        let list = words(text)
        guard !list.isEmpty else { return text }
        switch style {
        case .camel: return list[0] + list.dropFirst().map(\.capitalized).joined()
        case .pascal: return list.map(\.capitalized).joined()
        case .snake: return list.joined(separator: "_")
        case .kebab: return list.joined(separator: "-")
        case .constant: return list.joined(separator: "_").uppercased()
        }
    }

    // MARK: Colours

    struct RGB: Equatable {
        let red: Int, green: Int, blue: Int
        var alpha: Double = 1
    }

    /// "#1db954", "1DB954", "#fff", "rgb(29, 185, 84)", "rgba(29,185,84,0.5)".
    static func color(_ text: String) -> RGB? {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasPrefix("rgb") {
            guard let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")") else { return nil }
            let parts = value[value.index(after: open)..<close].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3, let r = Int(parts[0]), let g = Int(parts[1]), let b = Int(parts[2]),
                  [r, g, b].allSatisfy({ (0...255).contains($0) }) else { return nil }
            return RGB(red: r, green: g, blue: b, alpha: parts.count > 3 ? Double(parts[3]) ?? 1 : 1)
        }
        guard value.hasPrefix("#") else { return nil }
        var hex = String(value.dropFirst())
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let number = UInt64(hex, radix: 16) else { return nil }
        if hex.count == 8 {
            return RGB(red: Int(number >> 24 & 255), green: Int(number >> 16 & 255), blue: Int(number >> 8 & 255), alpha: Double(number & 255) / 255)
        }
        return RGB(red: Int(number >> 16 & 255), green: Int(number >> 8 & 255), blue: Int(number & 255))
    }

    static func formats(_ rgb: RGB) -> [(title: String, value: String)] {
        let r = Double(rgb.red) / 255, g = Double(rgb.green) / 255, b = Double(rgb.blue) / 255
        let hex = String(format: "#%02X%02X%02X", rgb.red, rgb.green, rgb.blue)
        let (h, s, l) = hsl(r, g, b)
        func n(_ value: Double) -> String { String(format: "%.3f", value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) }
        let alpha = rgb.alpha < 1 ? ", opacity: \(n(rgb.alpha))" : ""
        return [
            ("HEX", hex),
            ("RGB", rgb.alpha < 1 ? "rgba(\(rgb.red), \(rgb.green), \(rgb.blue), \(n(rgb.alpha)))" : "rgb(\(rgb.red), \(rgb.green), \(rgb.blue))"),
            ("HSL", "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"),
            ("SwiftUI", "Color(red: \(n(r)), green: \(n(g)), blue: \(n(b))\(alpha))"),
            ("UIKit", "UIColor(red: \(n(r)), green: \(n(g)), blue: \(n(b)), alpha: \(n(rgb.alpha)))"),
            ("Compose", String(format: "Color(0x%02X%02X%02X%02X)", Int((rgb.alpha * 255).rounded()), rgb.red, rgb.green, rgb.blue)),
        ]
    }

    private static func hsl(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        guard maxV != minV else { return (0, 0, l) }
        let d = maxV - minV
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double
        switch maxV {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h *= 60
        return (h, s, l)
    }

    // MARK: Cron

    /// "*/5 * * * *" → "Every 5 minutes". Five fields (minute hour day month weekday); nil when it isn't cron.
    static func cron(_ text: String) -> String? {
        let fields = text.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        guard fields.count == 5, fields.allSatisfy({ $0.allSatisfy { "0123456789*/,-".contains($0) } }),
              fields.contains(where: { $0.contains("*") }) else { return nil }
        let (minute, hour, day, month, weekday) = (fields[0], fields[1], fields[2], fields[3], fields[4])
        var parts: [String] = []

        if minute == "*" && hour == "*" {
            parts.append(L("Her dakika", "Every minute"))
        } else if minute.hasPrefix("*/"), hour == "*" {
            parts.append(L("\(minute.dropFirst(2)) dakikada bir", "Every \(minute.dropFirst(2)) minutes"))
        } else if let m = Int(minute), hour == "*" {
            parts.append(L("Her saat \(m). dakikada", "Every hour at minute \(m)"))
        } else if let m = Int(minute), hour.hasPrefix("*/") {
            parts.append(L("\(hour.dropFirst(2)) saatte bir, :\(String(format: "%02d", m))", "Every \(hour.dropFirst(2)) hours at :\(String(format: "%02d", m))"))
        } else if let m = Int(minute), let times = list(hour) {
            parts.append(L("Saat ", "At ") + times.map { String(format: "%02d:%02d", $0, m) }.joined(separator: ", "))
        } else {
            parts.append(L("Dakika \(minute), saat \(hour)", "Minute \(minute), hour \(hour)"))
        }

        if day != "*" { parts.append(L("ayın \(day). günü", "on day \(day) of the month")) }
        if month != "*" { parts.append(L("ay: \(names(month, months))", "in \(names(month, months))")) }
        if weekday != "*" {
            if weekday == "1-5" { parts.append(L("hafta içi", "on weekdays")) }
            else if weekday == "0,6" || weekday == "6,0" { parts.append(L("hafta sonu", "on weekends")) }
            else { parts.append(L("gün: \(names(weekday, days))", "on \(names(weekday, days))")) }
        }
        return parts.joined(separator: ", ")
    }

    private static func list(_ field: String) -> [Int]? {
        let values = field.split(separator: ",").compactMap { Int($0) }
        return values.count == field.split(separator: ",").count && !values.isEmpty ? values : nil
    }

    private static var days: [String] {
        Prefs.isTurkish ? ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]
                        : ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    }

    private static var months: [String] {
        let names = Prefs.isTurkish ? ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
                                    : ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        return [""] + names
    }

    /// "1-5" → "Monday–Friday", "1,3" → "Monday, Wednesday".
    private static func names(_ field: String, _ table: [String]) -> String {
        field.split(separator: ",").map { part -> String in
            let range = part.split(separator: "-").compactMap { Int($0) }
            if range.count == 2, table.indices.contains(range[0]), table.indices.contains(range[1]) { return "\(table[range[0]])–\(table[range[1]])" }
            if let value = Int(part), table.indices.contains(value) { return table[value] }
            return String(part)
        }.joined(separator: ", ")
    }

    // MARK: HTTP

    static func httpStatus(_ code: Int) -> String? {
        let tr: [Int: String] = [
            200: "OK", 201: "Oluşturuldu", 204: "İçerik yok", 301: "Kalıcı yönlendirme", 302: "Geçici yönlendirme", 304: "Değişmedi (önbellek)",
            307: "Geçici yönlendirme (yöntem korunur)", 308: "Kalıcı yönlendirme (yöntem korunur)", 400: "Hatalı istek", 401: "Kimlik doğrulama gerekli",
            403: "Yasak (yetki yok)", 404: "Bulunamadı", 405: "Yönteme izin yok", 408: "İstek zaman aşımı", 409: "Çakışma", 410: "Kalıcı olarak gitti",
            413: "İstek çok büyük", 415: "Desteklenmeyen içerik türü", 418: "Ben bir çaydanlığım", 422: "İşlenemeyen içerik (doğrulama hatası)",
            429: "Çok fazla istek (rate limit)", 500: "Sunucu hatası", 501: "Uygulanmadı", 502: "Hatalı ağ geçidi", 503: "Hizmet kullanılamıyor",
            504: "Ağ geçidi zaman aşımı",
        ]
        let en: [Int: String] = [
            200: "OK", 201: "Created", 204: "No Content", 301: "Moved Permanently", 302: "Found", 304: "Not Modified",
            307: "Temporary Redirect", 308: "Permanent Redirect", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
            405: "Method Not Allowed", 408: "Request Timeout", 409: "Conflict", 410: "Gone", 413: "Payload Too Large",
            415: "Unsupported Media Type", 418: "I'm a teapot", 422: "Unprocessable Content", 429: "Too Many Requests",
            500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway", 503: "Service Unavailable", 504: "Gateway Timeout",
        ]
        return Prefs.isTurkish ? tr[code] : en[code]
    }
}
