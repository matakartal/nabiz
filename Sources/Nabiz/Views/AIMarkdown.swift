// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import SwiftUI

// MARK: - Parsing

/// One block of an answer. Parsed again as the answer streams in, so an unfinished code block still shows as code.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([MarkdownListItem])
    case code(language: String, code: String, closed: Bool)
    case quote(String)
    case table(header: [String], rows: [[String]])
    case rule
}

struct MarkdownListItem: Equatable {
    /// "•" or the number as written ("1.").
    var marker: String
    var text: String
    var level = 0
    /// For "- [ ]" and "- [x]".
    var checked: Bool?
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var list: [MarkdownListItem] = []
        var quote: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        func flushList() {
            if !list.isEmpty { blocks.append(.list(list)) }
            list = []
        }
        func flushQuote() {
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))) }
            quote = []
        }
        func flushAll() {
            flushParagraph()
            flushList()
            flushQuote()
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushAll()
                let fence = String(trimmed.prefix(3))
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                var closed = false
                index += 1
                while index < lines.count {
                    if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                        closed = true
                        break
                    }
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.code(language: language, code: code.joined(separator: "\n"), closed: closed))
                index += 1
                continue
            }
            if trimmed.isEmpty {
                flushAll()
                index += 1
                continue
            }
            if let heading = heading(trimmed) {
                flushAll()
                blocks.append(heading)
                index += 1
                continue
            }
            if isRule(trimmed) {
                flushAll()
                blocks.append(.rule)
                index += 1
                continue
            }
            if trimmed.contains("|"), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
                flushAll()
                let header = cells(trimmed)
                var rows: [[String]] = []
                index += 2
                while index < lines.count {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    guard !row.isEmpty, row.contains("|") else { break }
                    rows.append(cells(row))
                    index += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                index += 1
                continue
            }
            if let item = listItem(line) {
                flushParagraph()
                flushQuote()
                list.append(item)
                index += 1
                continue
            }
            // An indented line under a list item belongs to it.
            if !list.isEmpty, line.hasPrefix("  ") || line.hasPrefix("\t") {
                list[list.count - 1].text += "\n" + trimmed
                index += 1
                continue
            }
            flushList()
            flushQuote()
            paragraph.append(trimmed)
            index += 1
        }
        flushAll()
        return blocks
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return .heading(level: hashes, text: line.dropFirst(hashes).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") || trimmed.hasPrefix("-") || trimmed.hasPrefix(":") else { return false }
        return trimmed.allSatisfy { "|-: ".contains($0) }
    }

    private static func cells(_ line: String) -> [String] {
        var parts = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.first?.isEmpty == true { parts.removeFirst() }
        if parts.last?.isEmpty == true { parts.removeLast() }
        return parts
    }

    private static func listItem(_ line: String) -> MarkdownListItem? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let rest = line.drop { $0 == " " || $0 == "\t" }
        var marker: String
        var body: Substring
        if let first = rest.first, "-*+".contains(first), rest.dropFirst().first == " " {
            marker = "•"
            body = rest.dropFirst(2)
        } else {
            let digits = rest.prefix { $0.isNumber }
            guard !digits.isEmpty, digits.count <= 3, let dot = rest.dropFirst(digits.count).first, dot == "." || dot == ")",
                  rest.dropFirst(digits.count + 1).first == " " else { return nil }
            marker = digits + "."
            body = rest.dropFirst(digits.count + 2)
        }
        var checked: Bool?
        if body.hasPrefix("[ ] ") || body.hasPrefix("[x] ") || body.hasPrefix("[X] ") {
            checked = !body.hasPrefix("[ ]")
            body = body.dropFirst(4)
            marker = ""
        }
        return MarkdownListItem(marker: marker, text: String(body), level: min(indent / 2, 3), checked: checked)
    }
}

// MARK: - Inline

enum MarkdownInline {
    /// Bold, italics, strikethrough, `code` and links; line breaks stay as written.
    static func render(_ text: String, size: CGFloat, tint: Color) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                             failurePolicy: .returnPartiallyParsedIfPossible)
        var result = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        var code: [Range<AttributedString.Index>] = []
        var links: [Range<AttributedString.Index>] = []
        for run in result.runs {
            if run.inlinePresentationIntent?.contains(.code) == true { code.append(run.range) }
            if run.link != nil { links.append(run.range) }
        }
        for range in code {
            result[range].font = .system(size: size * 0.92, design: .monospaced)
            result[range].backgroundColor = Theme.track
        }
        for range in links {
            result[range].foregroundColor = tint
            result[range].underlineStyle = .single
        }
        return result
    }
}

// MARK: - Views

/// An answer as the AI apps show it: headings, lists, quotes, tables and code blocks with a copy button.
struct MarkdownView: View {
    let text: String
    var size: CGFloat = 14
    var tint: Color = Theme.accent

    var body: some View {
        let blocks = MarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: size * 0.8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: blocks.count)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(.system(size: size + CGFloat(max(0, 4 - level)) * 2, weight: level <= 2 ? .bold : .semibold))
                .padding(.top, level <= 2 ? size * 0.3 : 0)
        case .paragraph(let text):
            inline(text).font(.system(size: size))
        case .list(let items):
            VStack(alignment: .leading, spacing: size * 0.35) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: size * 0.5) {
                        if let checked = item.checked {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .font(.system(size: size * 0.9))
                                .foregroundStyle(checked ? tint : Theme.textMuted)
                        } else {
                            Text(verbatim: item.marker)
                                .font(.system(size: size, weight: item.marker == "•" ? .bold : .regular).monospacedDigit())
                                .foregroundStyle(Theme.textMuted)
                                .frame(minWidth: size * 0.8, alignment: .trailing)
                        }
                        inline(item.text).font(.system(size: size))
                    }
                    .padding(.leading, CGFloat(item.level) * size * 1.3)
                }
            }
        case .code(let language, let code, _):
            CodeBlockView(language: language, code: code, size: size)
        case .quote(let text):
            HStack(spacing: size * 0.7) {
                Capsule().fill(tint.opacity(0.6)).frame(width: 3)
                inline(text).font(.system(size: size)).foregroundStyle(Theme.textMuted)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .table(let header, let rows):
            TableBlockView(header: header, rows: rows, size: size, tint: tint)
        case .rule:
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, size * 0.3)
        }
    }

    private func inline(_ text: String) -> some View {
        Text(MarkdownInline.render(text, size: size, tint: tint))
            .foregroundStyle(Theme.text)
            .lineSpacing(size * 0.22)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A fenced code block: its language, a copy button and coloured code that scrolls sideways.
struct CodeBlockView: View {
    let language: String
    let code: String
    var size: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: language.isEmpty ? L("kod", "code") : language)
                    .font(.system(size: size * 0.8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                AICopyButton(text: code, size: size * 0.8)
            }
            .padding(.horizontal, size * 0.85)
            .padding(.vertical, size * 0.4)
            .background(Theme.track)
            ScrollView(.horizontal) {
                Text(SyntaxHighlighter.highlight(code, language: language))
                    .font(.system(size: size * 0.88, design: .monospaced))
                    .lineSpacing(size * 0.18)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(size * 0.85)
            }
            .scrollIndicators(.never)
        }
        .background(Theme.track.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline) }
    }
}

/// A Markdown table, scrolling sideways when wide.
struct TableBlockView: View {
    let header: [String]
    let rows: [[String]]
    var size: CGFloat = 14
    var tint: Color = Theme.accent

    var body: some View {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: size * 1.2, verticalSpacing: size * 0.5) {
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        cell(column < header.count ? header[column] : "").fontWeight(.semibold)
                    }
                }
                Rectangle().fill(Theme.hairline).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in cell(column < row.count ? row[column] : "") }
                    }
                }
            }
            .padding(size * 0.85)
        }
        .scrollIndicators(.never)
        .background(Theme.track.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline) }
    }

    private func cell(_ text: String) -> Text {
        Text(MarkdownInline.render(text, size: size * 0.93, tint: tint)).font(.system(size: size * 0.93)).foregroundStyle(Theme.text)
    }
}

/// "Copy", then a tick for a moment.
struct AICopyButton: View {
    let text: String
    var size: CGFloat = 12
    var label = true
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                if label { Text(copied ? L("Kopyalandı", "Copied") : L("Kopyala", "Copy")) }
            }
            .font(.system(size: size))
            .foregroundStyle(Theme.textMuted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Kopyala", "Copy"))
    }
}

// MARK: - Code colours

/// Light colouring for code: comments, strings, numbers and common keywords, in any language.
@MainActor
enum SyntaxHighlighter {
    private static var cache: [String: AttributedString] = [:]

    private static let keyword = Theme.dynamic(light: .hex(0xA626A4), dark: .hex(0xC678DD))
    private static let string = Theme.dynamic(light: .hex(0x50A14F), dark: .hex(0x98C379))
    private static let number = Theme.dynamic(light: .hex(0x986801), dark: .hex(0xD19A66))
    private static let type = Theme.dynamic(light: .hex(0x4078F2), dark: .hex(0x61AFEF))

    private static let keywords = [
        "func", "function", "fn", "def", "let", "var", "const", "val", "mut", "if", "else", "elif", "for", "while", "do", "return",
        "import", "from", "export", "default", "class", "struct", "enum", "protocol", "interface", "extension", "impl", "trait",
        "type", "async", "await", "try", "catch", "throw", "throws", "guard", "switch", "case", "break", "continue", "in", "of",
        "new", "true", "false", "nil", "null", "None", "True", "False", "self", "Self", "this", "super", "public", "private",
        "static", "final", "override", "init", "lambda", "with", "as", "is", "not", "and", "or", "yield", "pass", "raise", "except",
        "finally", "package", "go", "pub", "use", "mod", "match", "where", "then", "fi", "echo", "export", "select", "insert",
        "update", "delete", "create", "table", "into", "values", "join", "on", "group", "by", "order", "limit",
    ]

    static func highlight(_ code: String, language: String) -> AttributedString {
        let key = language + "\u{0}" + code
        if let cached = cache[key] { return cached }
        var result = AttributedString(code)
        let lang = language.lowercased()
        let hashComments = ["python", "py", "sh", "bash", "zsh", "shell", "ruby", "rb", "yaml", "yml", "toml", "r", "perl", "makefile", "dockerfile", "conf"].contains(lang)
        let dashComments = ["sql", "lua", "haskell", "hs"].contains(lang)
        let caseless = ["sql"].contains(lang)

        // Later passes win: a keyword inside a string or comment takes the string's or comment's colour.
        func paint(_ pattern: String, _ color: Color, italic: Bool = false, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                guard let range = Range(match.range, in: result) else { continue }
                result[range].foregroundColor = color
            }
        }

        paint("\\b[A-Z][A-Za-z0-9_]*\\b", type)
        paint("(?<![.\\w])(?:" + keywords.joined(separator: "|") + ")\\b", keyword, options: caseless ? [.caseInsensitive] : [])
        paint("\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b", number)
        paint("\"(?:\\\\.|[^\"\\\\\\n])*\"|'(?:\\\\.|[^'\\\\\\n])*'|`(?:\\\\.|[^`\\\\])*`", string)
        if hashComments { paint("(?m)#.*$", Theme.textMuted, italic: true) }
        if dashComments { paint("(?m)--.*$", Theme.textMuted, italic: true) }
        if !hashComments { paint("(?m)//.*$|/\\*[\\s\\S]*?\\*/", Theme.textMuted, italic: true) }
        if lang == "html" || lang == "xml" { paint("<!--[\\s\\S]*?-->", Theme.textMuted, italic: true) }

        if cache.count > 64 { cache.removeAll() }
        cache[key] = result
        return result
    }
}
