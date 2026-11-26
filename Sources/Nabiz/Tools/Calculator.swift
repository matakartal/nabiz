// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation

/// Maths, money and units from one line of text, the way you'd say it:
/// "12*4", "√2 * 3", "sin 30", "20% of 150", "200 + %18", "10!", "17 mod 5", "ans * 2",
/// "100 usd", "250 € tl", "0.5 btc", "1000 tl eth", "5 km mi", "120 km/h mph", "3 dönüm m2", "2 gb mb",
/// "255 hex", "0xff", "tokyo", "15:00 istanbul to new york", "today + 30 days", "days until 2027-01-01".
@MainActor
enum Calculator {
    struct Result: Equatable, Sendable {
        let text: String
        /// What Return copies: the number as people write it ("2,048", "1.234,56").
        let copy: String
        /// Full precision without grouping, for spreadsheets and code: "2048", "3.1068559611866697".
        var raw: String?
        /// What this row is, shown on the right: "EUR", "Hex", "+6 h".
        var note: String?
    }

    fileprivate enum Token: Equatable {
        case number(Double)
        /// pi, e and ans: they can follow a number without "*" ("2pi").
        case constant(Double)
        /// + - * / ^ % ( ) ! and "m" for mod.
        case op(Character)
        case function(String)
        case currency(String)
        case unit(String)
        /// "hex", "bin", "oct", "dec": the base to show the result in.
        case base(Int)
    }

    private enum Dimension { case length, mass, data, time, temperature, speed, area, volume, energy }

    /// Unit words (English and Turkish) → canonical unit.
    private static let unitWords: [String: String] = [
        "mm": "mm", "cm": "cm", "m": "m", "metre": "m", "meter": "m", "km": "km", "kilometre": "km", "kilometer": "km",
        "inch": "in", "inches": "in", "inç": "in", "ft": "ft", "feet": "ft", "foot": "ft", "yd": "yd", "yard": "yd",
        "mi": "mi", "mile": "mi", "miles": "mi", "mil": "mi", "nmi": "nmi",
        "mg": "mg", "g": "g", "gr": "g", "gram": "g", "kg": "kg", "kilo": "kg", "lb": "lb", "lbs": "lb", "pound": "lb",
        "oz": "oz", "ounce": "oz", "ton": "t",
        "b": "B", "byte": "B", "kb": "KB", "mb": "MB", "gb": "GB", "tb": "TB",
        "ms": "ms", "s": "s", "sn": "s", "sec": "s", "saniye": "s", "min": "min", "dk": "min", "dakika": "min",
        "h": "h", "hr": "h", "hour": "h", "hours": "h", "saat": "h", "day": "day", "days": "day", "gün": "day",
        "week": "week", "weeks": "week", "hafta": "week", "year": "year", "years": "year", "yıl": "year",
        "c": "°C", "celsius": "°C", "f": "°F", "fahrenheit": "°F", "kelvin": "K",
        "kmh": "km/h", "kph": "km/h", "mph": "mph", "mps": "m/s", "knot": "kn", "knots": "kn", "kn": "kn", "knot.": "kn",
        "sqm": "m²", "m2": "m²", "sqkm": "km²", "km2": "km²", "sqcm": "cm²", "cm2": "cm²", "sqft": "ft²", "ft2": "ft²",
        "ha": "ha", "hektar": "ha", "hectare": "ha", "acre": "acre", "acres": "acre", "dönüm": "dönüm", "donum": "dönüm", "dekar": "dönüm",
        "ml": "ml", "cl": "cl", "l": "l", "lt": "l", "litre": "l", "liter": "l", "gal": "gal", "gallon": "gal", "gallons": "gal",
        "cup": "cup", "cups": "cup", "bardak": "cup",
        "j": "J", "kj": "kJ", "cal": "kcal", "kcal": "kcal", "kalori": "kcal", "wh": "Wh", "kwh": "kWh",
    ]

    /// Words that end in digits ("m2", "log10"); read whole instead of as a word and a number.
    private static let digitWords: Set<String> = ["m2", "km2", "cm2", "ft2", "log2", "log10"]

    /// Canonical unit → dimension and size in the dimension's base unit (m, g, B, s, m/s, m², l, J).
    private static let units: [String: (Dimension, Double)] = [
        "mm": (.length, 0.001), "cm": (.length, 0.01), "m": (.length, 1), "km": (.length, 1000),
        "in": (.length, 0.0254), "ft": (.length, 0.3048), "yd": (.length, 0.9144), "mi": (.length, 1609.344), "nmi": (.length, 1852),
        "mg": (.mass, 0.001), "g": (.mass, 1), "kg": (.mass, 1000), "t": (.mass, 1_000_000),
        "lb": (.mass, 453.59237), "oz": (.mass, 28.349523125),
        "B": (.data, 1), "KB": (.data, 1024), "MB": (.data, 1_048_576), "GB": (.data, 1_073_741_824), "TB": (.data, 1_099_511_627_776),
        "ms": (.time, 0.001), "s": (.time, 1), "min": (.time, 60), "h": (.time, 3600), "day": (.time, 86_400),
        "week": (.time, 604_800), "year": (.time, 31_557_600),
        "°C": (.temperature, 1), "°F": (.temperature, 1), "K": (.temperature, 1),
        "km/h": (.speed, 1 / 3.6), "mph": (.speed, 0.44704), "m/s": (.speed, 1), "kn": (.speed, 1852.0 / 3600),
        "m²": (.area, 1), "km²": (.area, 1_000_000), "cm²": (.area, 0.0001), "ft²": (.area, 0.09290304),
        "ha": (.area, 10_000), "acre": (.area, 4046.8564224), "dönüm": (.area, 1000),
        "ml": (.volume, 0.001), "cl": (.volume, 0.01), "l": (.volume, 1), "gal": (.volume, 3.785411784), "cup": (.volume, 0.2365882365),
        "J": (.energy, 1), "kJ": (.energy, 1000), "kcal": (.energy, 4184), "Wh": (.energy, 3600), "kWh": (.energy, 3_600_000),
    ]

    /// Where a lone unit converts to: "5 km" → miles, "100 f" → °C.
    private static let defaultTarget: [String: String] = [
        "km": "mi", "mi": "km", "m": "ft", "ft": "m", "cm": "in", "in": "cm", "mm": "in", "yd": "m", "nmi": "km",
        "kg": "lb", "lb": "kg", "g": "oz", "oz": "g", "mg": "g", "t": "kg",
        "°C": "°F", "°F": "°C", "K": "°C",
        "TB": "GB", "GB": "MB", "MB": "GB", "KB": "MB", "B": "KB",
        "year": "day", "week": "day", "day": "h", "h": "min", "min": "s", "s": "min", "ms": "s",
        "km/h": "mph", "mph": "km/h", "m/s": "km/h", "kn": "km/h",
        "m²": "ft²", "km²": "ha", "cm²": "m²", "ft²": "m²", "ha": "dönüm", "acre": "ha", "dönüm": "m²",
        "l": "gal", "gal": "l", "ml": "l", "cl": "ml", "cup": "ml",
        "kcal": "kJ", "kJ": "kcal", "J": "kJ", "Wh": "kJ", "kWh": "kcal",
    ]

    /// A few more targets shown under the main answer when no target was typed.
    private static let popular: [Dimension: [String]] = [
        .length: ["km", "m", "cm", "mi", "ft", "in"], .mass: ["kg", "g", "lb", "oz"], .data: ["TB", "GB", "MB", "KB"],
        .time: ["day", "h", "min", "s"], .temperature: ["°C", "°F", "K"], .speed: ["km/h", "mph", "m/s", "kn"],
        .area: ["m²", "dönüm", "ha", "acre", "ft²"], .volume: ["l", "ml", "gal", "cup"], .energy: ["kcal", "kJ", "kWh"],
    ]

    private static let aliases: [String: String] = [
        "tl": "TRY", "lira": "TRY", "dolar": "USD", "dollar": "USD", "dollars": "USD", "euro": "EUR", "avro": "EUR",
        "sterlin": "GBP", "pound": "GBP", "yen": "JPY", "frank": "CHF",
    ]
    private static let functions: Set<String> = [
        "sqrt", "karekök", "kok", "sin", "cos", "tan", "asin", "acos", "atan", "log", "log10", "log2", "ln", "abs",
        "round", "floor", "ceil", "exp",
    ]
    private static let bases: [String: Int] = [
        "hex": 16, "hexadecimal": 16, "onaltılık": 16, "binary": 2, "ikilik": 2,
        "oct": 8, "octal": 8, "sekizlik": 8, "dec": 10, "decimal": 10, "onluk": 10,
    ]
    private static let fillers: Set<String> = ["to", "in", "into", "as", "kaç", "kac", "ne", "eder", "kaçtır", "nedir", "is", "what", "how", "much"]
    /// Applied before reading the line, longest first where one contains another.
    private static let symbols: [(String, String)] = [
        ("km/sa", " kmh "), ("km/h", " kmh "), ("m/s", " mps "),
        ("km²", " sqkm "), ("cm²", " sqcm "), ("ft²", " sqft "), ("m²", " sqm "),
        ("->", " "), ("=>", " "), ("=", " "), ("?", " "), ("√", " sqrt "), ("π", " pi "),
        ("$", " usd "), ("€", " eur "), ("£", " gbp "), ("₺", " try "), ("¥", " jpy "), ("×", "*"), ("÷", "/"), ("·", "*"),
    ]

    static func evaluate(_ input: String) -> Result? { evaluateAll(input).first }

    /// The answer first, then a few useful alternatives (other currencies, units or bases).
    static func evaluateAll(_ input: String) -> [Result] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let clock = WorldClock.evaluate(trimmed) { return clock }
        if let date = DateMath.evaluate(trimmed) { return date }
        guard let (tokens, special) = tokenize(trimmed) else { return [] }
        let currencies = tokens.compactMap { token -> String? in
            if case .currency(let code) = token { return code }
            return nil
        }
        let unitList = tokens.compactMap { token -> String? in
            if case .unit(let unit) = token { return unit }
            return nil
        }
        let base = tokens.compactMap { token -> Int? in
            if case .base(let base) = token { return base }
            return nil
        }.first
        let math = tokens.filter {
            switch $0 {
            case .currency, .unit, .base: false
            default: true
            }
        }
        var parser = Parser(tokens: math)
        guard !math.isEmpty, let value = parser.parse(), value.isFinite else { return [] }

        if let base { return baseResults(value, first: base) }
        if currencies.isEmpty, let from = unitList.first {
            return convertUnits(value, from: from, to: unitList.count > 1 ? unitList[1] : nil)
        }
        guard let from = currencies.first else {
            guard math.count > 1 || special else { return [] }
            let text = Format.number(value, maxDigits: 8)
            var results = [Result(text: "= " + text, copy: text, raw: raw(value))]
            // "0xff" on its own: also show it in the other bases.
            if trimmed.lowercased().contains("0x") || trimmed.lowercased().contains("0b") {
                results += baseResults(value, first: 10).dropFirst()
            }
            return results
        }
        return convertMoney(value, from: from, to: currencies.count > 1 ? currencies[1] : nil)
    }

    // MARK: Money

    private static func convertMoney(_ value: Double, from: String, to explicit: String?) -> [Result] {
        let base = Prefs.string(Prefs.baseCurrency)
        let to = explicit ?? (from == base ? (Prefs.watched.first { $0 != base } ?? "USD") : base)
        if (Crypto.isCrypto(from) || Crypto.isCrypto(to)) && (Crypto.price(from) == nil && Crypto.isCrypto(from) || Crypto.price(to) == nil && Crypto.isCrypto(to)) {
            MarketStore.shared.refreshCrypto()
            return [Result(text: L("Kripto fiyatı yükleniyor…", "Loading crypto price…"), copy: "")]
        }
        guard let converted = money(value, from: from, to: to) else {
            return RateStore.shared.table == nil ? [Result(text: L("Kurlar yükleniyor…", "Loading rates…"), copy: "")] : []
        }
        var results = [moneyResult(value, from: from, converted, to: to)]
        if explicit == nil {
            var others = Prefs.watched + [base, "USD", "EUR"]
            if Crypto.isCrypto(from) { others = ["USD", base] + others }
            var seen: Set<String> = [from, to]
            for code in others where !seen.contains(code) && results.count < 4 {
                seen.insert(code)
                if let amount = money(value, from: from, to: code) { results.append(moneyResult(value, from: from, amount, to: code)) }
            }
        }
        return results
    }

    /// Any two of fiat (ECB rates) and crypto (Hyperliquid prices, in USD).
    static func money(_ value: Double, from: String, to: String) -> Double? {
        if from == to { return value }
        if !Crypto.isCrypto(from) && !Crypto.isCrypto(to) { return RateStore.shared.convert(value, from: from, to: to) }
        func usd(_ amount: Double, _ code: String) -> Double? {
            if Crypto.isCrypto(code) { return Crypto.price(code).map { amount * $0 } }
            return code == "USD" ? amount : RateStore.shared.convert(amount, from: code, to: "USD")
        }
        guard let inUSD = usd(value, from) else { return nil }
        if Crypto.isCrypto(to) { return Crypto.price(to).map { inUSD / $0 } }
        return to == "USD" ? inUSD : RateStore.shared.convert(inUSD, from: "USD", to: to)
    }

    private static func moneyResult(_ value: Double, from: String, _ converted: Double, to: String) -> Result {
        let digits = Crypto.isCrypto(to) ? (converted < 1 ? 8 : 6) : 2
        return Result(text: "\(moneyText(value, from)) = \(moneyText(converted, to))",
                      copy: Format.number(converted, maxDigits: digits, minDigits: Crypto.isCrypto(to) ? 0 : 2),
                      raw: raw(converted), note: to)
    }

    private static func moneyText(_ value: Double, _ code: String) -> String {
        Crypto.isCrypto(code) ? Format.number(value, maxDigits: value < 1 ? 8 : 4) + " " + code : Format.money(value, code)
    }

    // MARK: Bases

    private static func baseResults(_ value: Double, first: Int) -> [Result] {
        guard value.rounded() == value, abs(value) < 9e15 else { return [] }
        let n = Int64(value)
        func text(_ base: Int) -> String {
            switch base {
            case 16: (n < 0 ? "-0x" : "0x") + String(n.magnitude, radix: 16).uppercased()
            case 2: (n < 0 ? "-0b" : "0b") + String(n.magnitude, radix: 2)
            case 8: (n < 0 ? "-0o" : "0o") + String(n.magnitude, radix: 8)
            default: "\(n)"
            }
        }
        let names = [16: "Hex", 2: L("İkilik", "Binary"), 8: L("Sekizlik", "Octal"), 10: L("Onluk", "Decimal")]
        return ([first] + [10, 16, 2, 8].filter { $0 != first }).map { base in
            Result(text: "\(n) = \(text(base))", copy: text(base), raw: text(base), note: names[base])
        }
    }

    // MARK: Units

    private static func convertUnits(_ value: Double, from: String, to explicit: String?) -> [Result] {
        guard let (dimension, _) = units[from] else { return [] }
        let to = explicit ?? defaultTarget[from]
        guard let to, let main = convert(value, from: from, to: to) else { return [] }
        var results = [main]
        if explicit == nil {
            for unit in popular[dimension] ?? [] where unit != from && unit != to && results.count < 4 {
                if let result = convert(value, from: from, to: unit) { results.append(result) }
            }
        }
        return results
    }

    private static func convert(_ value: Double, from: String, to: String) -> Result? {
        guard let (dimension, fromSize) = units[from], let (targetDimension, toSize) = units[to], dimension == targetDimension else { return nil }
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
        return Result(text: "\(Format.number(value, maxDigits: 4)) \(from) = \(number) \(to)", copy: number, raw: raw(converted), note: to)
    }

    // MARK: Reading

    /// Full precision without grouping.
    static func raw(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
        return String(value)
    }

    /// The tokens, and whether anything beyond a bare number was typed (a function, a constant, a hex literal),
    /// so "pi" or "0xff" answer on their own while "42" doesn't.
    private static func tokenize(_ input: String) -> ([Token], Bool)? {
        var text = input.lowercased()
        for (symbol, replacement) in symbols { text = text.replacingOccurrences(of: symbol, with: replacement) }
        text = text.replacingOccurrences(of: "°", with: " ")
        let codes = Set(RateStore.shared.codes)
        let chars = Array(text)
        var tokens: [Token] = []
        var special = false
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            // 0xFF, 0b1010, 0o17
            if c == "0", i + 2 < chars.count, let radix = ["x": 16, "b": 2, "o": 8][String(chars[i + 1])],
               chars[i + 2].isHexDigit {
                var j = i + 2
                while j < chars.count, chars[j].isHexDigit { j += 1 }
                guard let value = Int64(String(chars[(i + 2)..<j]), radix: radix) else { return nil }
                tokens.append(.number(Double(value)))
                special = true
                i = j
                continue
            }
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
                var word = String(chars[i..<j])
                var k = j
                while k < chars.count, chars[k].isNumber { k += 1 }
                if k > j, digitWords.contains(word + String(chars[j..<k])) { word += String(chars[j..<k]); j = k }
                i = j
                switch word {
                case "x": tokens.append(.op("*")); continue
                case "mod": tokens.append(.op("m")); continue
                case "of": tokens.append(.op("*")); continue
                case "yüzde": tokens.append(.op("%")); continue
                case "pi": tokens.append(.constant(.pi)); special = true; continue
                // "5 bin tl", "2,5 milyon", "10k usd"
                case "bin", "thousand", "k": tokens.append(.constant(1000)); continue
                case "milyon", "million", "mn": tokens.append(.constant(1_000_000)); continue
                case "milyar", "billion", "bn": tokens.append(.constant(1_000_000_000)); continue
                case "e": tokens.append(.constant(M_E)); special = true; continue
                case "ans":
                    guard let last = CalcHistory.lastValue else { return nil }
                    tokens.append(.constant(last))
                    special = true
                    continue
                default: break
                }
                if functions.contains(word) { tokens.append(.function(word)); special = true; continue }
                if let base = bases[word] { tokens.append(.base(base)); continue }
                if let code = aliases[word] ?? (codes.contains(word.uppercased()) ? word.uppercased() : nil) {
                    tokens.append(.currency(code))
                    continue
                }
                if let unit = unitWords[word] { tokens.append(.unit(unit)); continue }
                if let crypto = Crypto.code(word) { tokens.append(.currency(crypto)); continue }
                if fillers.contains(word) { continue }
                return nil
            }
            if "+-*/^%()!".contains(c) { tokens.append(.op(c)); i += 1; continue }
            return nil
        }
        // "2pi", "3(4+1)", "2 sqrt 9": multiply without the "*".
        var joined: [Token] = []
        for token in tokens {
            if let last = joined.last {
                let endsValue: Bool = switch last {
                case .number, .constant, .op(")"), .op("!"): true
                default: false
                }
                let startsValue: Bool = switch token {
                case .constant, .function, .op("("): true
                default: false
                }
                if endsValue && startsValue { joined.append(.op("*")) }
            }
            joined.append(token)
        }
        return (joined, special)
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

/// Crypto prices from Hyperliquid's main dex, in USD.
@MainActor
enum Crypto {
    private static let aliases = ["bitcoin": "BTC", "ethereum": "ETH", "ether": "ETH", "solana": "SOL"]
    /// Always understood, even before prices load.
    private static let common: Set<String> = ["BTC", "ETH", "SOL", "HYPE", "XRP", "DOGE", "BNB", "ADA", "AVAX", "LINK", "SUI", "TRX"]

    static func code(_ word: String) -> String? {
        let code = aliases[word] ?? word.uppercased()
        guard code.count >= 2, code.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return common.contains(code) || MarketStore.shared.markets[code] != nil ? code : nil
    }

    static func isCrypto(_ code: String) -> Bool {
        common.contains(code) || (MarketStore.shared.markets[code] != nil && !code.contains(":"))
    }

    static func price(_ code: String) -> Double? {
        MarketStore.shared.markets[code]?.price
    }
}

/// The last calculations copied from the launcher; "ans" is the latest one's value.
@MainActor
enum CalcHistory {
    struct Entry: Codable, Equatable {
        var expression: String
        var text: String
        var copy: String
        var raw: String?
        var date: Date
    }

    private static let key = "calcHistory"

    static var entries: [Entry] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    static var lastValue: Double? {
        entries.first.flatMap { $0.raw.flatMap(Double.init) }
    }

    static func add(_ expression: String, _ result: Calculator.Result) {
        guard !result.copy.isEmpty else { return }
        var list = entries.filter { $0.expression != expression }
        list.insert(Entry(expression: expression, text: result.text, copy: result.copy, raw: result.raw, date: Date()), at: 0)
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(list.prefix(30))), forKey: key)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

/// Recursive descent: + - over * / mod over ^ over unary minus, percent, factorial and functions.
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
        while let c = peek(), c == "*" || c == "/" || c == "m" {
            i += 1
            guard let right = power() else { return nil }
            let r = plain(right)
            if c != "*" && r == 0 { return nil }
            left = (c == "*" ? plain(left) * r : c == "/" ? plain(left) / r : fmod(plain(left), r), false)
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
            guard let value = postfix() else { return nil }
            return (value, true)
        default:
            guard let value = postfix() else { return nil }
            if peek() == "%" { i += 1; return (value, true) }
            return (value, false)
        }
    }

    /// A value followed by "!" (factorial), any number of times.
    private mutating func postfix() -> Double? {
        guard var value = primary() else { return nil }
        while peek() == "!" {
            i += 1
            guard value >= 0, value <= 170, value.rounded() == value else { return nil }
            value = value == 0 ? 1 : (1...Int(value)).reduce(1.0) { $0 * Double($1) }
        }
        return value
    }

    private mutating func primary() -> Double? {
        guard i < tokens.count else { return nil }
        switch tokens[i] {
        case .number(let value), .constant(let value):
            i += 1
            return value
        case .op("("):
            i += 1
            guard let value = expr(), peek() == ")" else { return nil }
            i += 1
            return value
        case .function(let name):
            i += 1
            guard let argument = peek() == "(" ? primary() : unary().map({ $0.percent ? $0.value / 100 : $0.value }) else { return nil }
            return Self.apply(name, argument)
        default:
            return nil
        }
    }

    /// Trigonometry works in degrees: sin 30 = 0.5.
    private static func apply(_ name: String, _ x: Double) -> Double? {
        let radians = x * .pi / 180
        let value: Double = switch name {
        case "sqrt", "karekök", "kok": x >= 0 ? sqrt(x) : .nan
        case "sin": sin(radians)
        case "cos": cos(radians)
        case "tan": tan(radians)
        case "asin": asin(x) * 180 / .pi
        case "acos": acos(x) * 180 / .pi
        case "atan": atan(x) * 180 / .pi
        case "log", "log10": x > 0 ? log10(x) : .nan
        case "log2": x > 0 ? log2(x) : .nan
        case "ln": x > 0 ? log(x) : .nan
        case "abs": abs(x)
        case "round": x.rounded()
        case "floor": floor(x)
        case "ceil": ceil(x)
        case "exp": exp(x)
        default: .nan
        }
        guard value.isFinite else { return nil }
        // sin 180 is 1.2e-16 in floating point; show it as 0.
        return abs(value) < 1e-12 ? 0 : value
    }
}
