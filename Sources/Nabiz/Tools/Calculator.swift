import Foundation

/// Arithmetic, currency and unit conversion from one line of text:
/// "12*4", "(3+4)^2", "200 + %18", "100 usd", "250 € tl", "1.500,50 eur to usd", "5 km mi", "100 f c", "2 gb mb".
@MainActor
enum Calculator {
    struct Result: Equatable {
        let text: String
        /// What Enter copies: the bare number.
        let copy: String
    }

    fileprivate enum Token {
        case number(Double)
        case op(Character)
        case currency(String)
        case unit(String)
    }

    private enum Dimension { case length, mass, data, time, temperature }

    /// Unit words (English and Turkish) → canonical unit.
    private static let unitWords: [String: String] = [
        "mm": "mm", "cm": "cm", "m": "m", "metre": "m", "meter": "m", "km": "km", "kilometre": "km", "kilometer": "km",
        "inch": "in", "inches": "in", "inç": "in", "ft": "ft", "feet": "ft", "foot": "ft", "yd": "yd", "yard": "yd",
        "mi": "mi", "mile": "mi", "miles": "mi", "mil": "mi",
        "mg": "mg", "g": "g", "gr": "g", "gram": "g", "kg": "kg", "kilo": "kg", "lb": "lb", "lbs": "lb", "pound": "lb",
        "oz": "oz", "ounce": "oz", "ton": "t",
        "b": "B", "byte": "B", "kb": "KB", "mb": "MB", "gb": "GB", "tb": "TB",
        "ms": "ms", "s": "s", "sn": "s", "sec": "s", "saniye": "s", "min": "min", "dk": "min", "dakika": "min",
        "h": "h", "hr": "h", "hour": "h", "hours": "h", "saat": "h", "day": "day", "days": "day", "gün": "day",
        "week": "week", "weeks": "week", "hafta": "week",
        "c": "°C", "celsius": "°C", "f": "°F", "fahrenheit": "°F", "kelvin": "K",
    ]

    /// Canonical unit → dimension and size in the dimension's base unit (m, g, B, s; temperature is special).
    private static let units: [String: (Dimension, Double)] = [
        "mm": (.length, 0.001), "cm": (.length, 0.01), "m": (.length, 1), "km": (.length, 1000),
        "in": (.length, 0.0254), "ft": (.length, 0.3048), "yd": (.length, 0.9144), "mi": (.length, 1609.344),
        "mg": (.mass, 0.001), "g": (.mass, 1), "kg": (.mass, 1000), "t": (.mass, 1_000_000),
        "lb": (.mass, 453.59237), "oz": (.mass, 28.349523125),
        "B": (.data, 1), "KB": (.data, 1024), "MB": (.data, 1_048_576), "GB": (.data, 1_073_741_824), "TB": (.data, 1_099_511_627_776),
        "ms": (.time, 0.001), "s": (.time, 1), "min": (.time, 60), "h": (.time, 3600), "day": (.time, 86_400), "week": (.time, 604_800),
        "°C": (.temperature, 1), "°F": (.temperature, 1), "K": (.temperature, 1),
    ]

    /// Where a lone unit converts to: "5 km" → miles, "100 f" → °C.
    private static let defaultTarget: [String: String] = [
        "km": "mi", "mi": "km", "m": "ft", "ft": "m", "cm": "in", "in": "cm", "mm": "in", "yd": "m",
        "kg": "lb", "lb": "kg", "g": "oz", "oz": "g", "mg": "g", "t": "kg",
        "°C": "°F", "°F": "°C", "K": "°C",
        "TB": "GB", "GB": "MB", "MB": "GB", "KB": "MB", "B": "KB",
        "week": "day", "day": "h", "h": "min", "min": "s", "s": "min", "ms": "s",
    ]

    private static let aliases: [String: String] = [
        "tl": "TRY", "lira": "TRY", "dolar": "USD", "dollar": "USD", "dollars": "USD", "euro": "EUR", "avro": "EUR",
        "sterlin": "GBP", "pound": "GBP", "yen": "JPY", "frank": "CHF",
    ]
    private static let fillers: Set<String> = ["to", "in", "into", "as", "kaç", "kac", "ne", "eder", "kaçtır", "nedir"]
    private static let symbols: [(String, String)] = [
        ("->", " "), ("=>", " "), ("=", " "), ("?", " "),
        ("$", " usd "), ("€", " eur "), ("£", " gbp "), ("₺", " try "), ("¥", " jpy "), ("×", "*"), ("÷", "/"),
    ]

    static func evaluate(_ input: String) -> Result? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let tokens = tokenize(trimmed) else { return nil }
        let currencies = tokens.compactMap { token -> String? in
            if case .currency(let code) = token { return code }
            return nil
        }
        let unitList = tokens.compactMap { token -> String? in
            if case .unit(let unit) = token { return unit }
            return nil
        }
        let math = tokens.filter {
            switch $0 {
            case .currency, .unit: false
            default: true
            }
        }
        var parser = Parser(tokens: math)
        guard !math.isEmpty, let value = parser.parse(), value.isFinite else { return nil }

        if currencies.isEmpty, let from = unitList.first {
            return convertUnits(value, from: from, to: unitList.count > 1 ? unitList[1] : defaultTarget[from])
        }

        guard let from = currencies.first else {
            guard math.count > 1 else { return nil }
            let text = Format.number(value, maxDigits: 8)
            return Result(text: "= " + text, copy: text)
        }
        let base = Prefs.string(Prefs.baseCurrency)
        let to = currencies.count > 1 ? currencies[1] : (from == base ? (Prefs.watched.first { $0 != base } ?? "USD") : base)
        let store = RateStore.shared
        guard let converted = store.convert(value, from: from, to: to) else {
            return store.table == nil ? Result(text: L("Kurlar yükleniyor…", "Loading rates…"), copy: "") : nil
        }
        return Result(text: "\(Format.money(value, from)) = \(Format.money(converted, to))",
                      copy: Format.number(converted, maxDigits: 2, minDigits: 2))
    }

    private static func tokenize(_ input: String) -> [Token]? {
        var text = input.lowercased()
        for (symbol, replacement) in symbols { text = text.replacingOccurrences(of: symbol, with: replacement) }
        text = text.replacingOccurrences(of: "°", with: " ")
        let codes = Set(RateStore.shared.codes)
        let chars = Array(text)
        var tokens: [Token] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isNumber || ((c == "." || c == ",") && i + 1 < chars.count && chars[i + 1].isNumber) {
                var j = i
                while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "," { j += 1 }
                guard let value = number(String(chars[i..<j])) else { return nil }
                tokens.append(.number(value))
                i = j
                continue
            }
            if c.isLetter {
                var j = i
                while j < chars.count, chars[j].isLetter { j += 1 }
                let word = String(chars[i..<j])
                i = j
                if word == "x" { tokens.append(.op("*")); continue }
                if let code = aliases[word] ?? (codes.contains(word.uppercased()) ? word.uppercased() : nil) {
                    tokens.append(.currency(code))
                    continue
                }
                if let unit = unitWords[word] {
                    tokens.append(.unit(unit))
                    continue
                }
                if fillers.contains(word) { continue }
                return nil
            }
            if "+-*/^%()".contains(c) { tokens.append(.op(c)); i += 1; continue }
            return nil
        }
        return tokens
    }

    private static func convertUnits(_ value: Double, from: String, to: String?) -> Result? {
        guard let to, let (dimension, fromSize) = units[from], let (targetDimension, toSize) = units[to],
              dimension == targetDimension else { return nil }
        let converted: Double
        if dimension == .temperature {
            let kelvin = switch from {
            case "°C": value + 273.15
            case "°F": (value - 32) * 5 / 9 + 273.15
            default: value
            }
            converted = switch to {
            case "°C": kelvin - 273.15
            case "°F": (kelvin - 273.15) * 9 / 5 + 32
            default: kelvin
            }
        } else {
            converted = value * fromSize / toSize
        }
        let digits = abs(converted) >= 100 ? 2 : 4
        let number = Format.number(converted, maxDigits: digits)
        return Result(text: "\(Format.number(value, maxDigits: 4)) \(from) = \(number) \(to)", copy: number)
    }

    /// Accepts both "1.234,5" and "1,234.5". A lone separator followed by three digits is read the local way.
    private static func number(_ raw: String) -> Double? {
        var s = raw
        let dot = s.lastIndex(of: "."), comma = s.lastIndex(of: ",")
        if let dot, let comma {
            let decimal: Character = dot > comma ? "." : ","
            s.removeAll { $0 == (decimal == "." ? "," : ".") }
            s = s.replacingOccurrences(of: String(decimal), with: ".")
        } else if comma != nil {
            let parts = s.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count > 2 || (parts.count == 2 && parts[1].count == 3 && !Prefs.isTurkish) {
                s.removeAll { $0 == "," }
            } else {
                s = s.replacingOccurrences(of: ",", with: ".")
            }
        } else if dot != nil {
            let parts = s.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count > 2 || (parts.count == 2 && parts[1].count == 3 && Prefs.isTurkish) {
                s.removeAll { $0 == "." }
            }
        }
        return Double(s)
    }
}

/// Recursive descent: + - over * / over ^ over unary minus and percent.
/// "200 + %18" and "200 + 18%" add 18 percent of 200; elsewhere a percent is a hundredth.
private struct Parser {
    typealias Term = (value: Double, percent: Bool)
    let tokens: [Calculator.Token]
    var i = 0

    mutating func parse() -> Double? {
        guard let value = expr(), i == tokens.count else { return nil }
        return value
    }

    private func peek() -> Character? {
        if i < tokens.count, case .op(let c) = tokens[i] { return c }
        return nil
    }

    private func plain(_ term: Term) -> Double { term.percent ? term.value / 100 : term.value }

    private mutating func expr() -> Double? {
        guard let first = term() else { return nil }
        var value = plain(first)
        while let c = peek(), c == "+" || c == "-" {
            i += 1
            guard let next = term() else { return nil }
            let delta = next.percent ? value * next.value / 100 : next.value
            value = c == "+" ? value + delta : value - delta
        }
        return value
    }

    private mutating func term() -> Term? {
        guard var left = power() else { return nil }
        while let c = peek(), c == "*" || c == "/" {
            i += 1
            guard let right = power() else { return nil }
            let r = plain(right)
            if c == "/" && r == 0 { return nil }
            left = (c == "*" ? plain(left) * r : plain(left) / r, false)
        }
        return left
    }

    private mutating func power() -> Term? {
        guard let base = unary() else { return nil }
        guard peek() == "^" else { return base }
        i += 1
        guard let exponent = power() else { return nil }
        return (pow(plain(base), plain(exponent)), false)
    }

    private mutating func unary() -> Term? {
        switch peek() {
        case "-":
            i += 1
            guard let inner = unary() else { return nil }
            return (-inner.value, inner.percent)
        case "+":
            i += 1
            return unary()
        case "%":
            i += 1
            guard let value = primary() else { return nil }
            return (value, true)
        default:
            guard let value = primary() else { return nil }
            if peek() == "%" { i += 1; return (value, true) }
            return (value, false)
        }
    }

    private mutating func primary() -> Double? {
        guard i < tokens.count else { return nil }
        switch tokens[i] {
        case .number(let value):
            i += 1
            return value
        case .op("("):
            i += 1
            guard let value = expr(), peek() == ")" else { return nil }
            i += 1
            return value
        default:
            return nil
        }
    }
}
