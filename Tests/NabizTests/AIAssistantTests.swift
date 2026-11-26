import Foundation
import Testing
@testable import Nabiz

/// Reading the CLIs' output and errors, building chat prompts and parsing answers. The CLIs themselves need a
/// sign-in, so they are left to the app (`Nabiz --ask`).
@MainActor
@Suite("AI assistant")
struct AIAssistantTests {
    init() {
        Prefs.registerDefaults()
        UserDefaults.standard.set("en", forKey: Prefs.language)
    }

    private func line(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object) + Data([0x0A])
    }

    private func delta(_ type: String, _ key: String, _ text: String) -> Data {
        line(["type": "stream_event", "event": ["type": "content_block_delta", "delta": ["type": type, key: text]]])
    }

    @Test func claudeStreamsTextThinkingAndModelAcrossSplitChunks() {
        let parser = StreamParser(engine: .claude)
        let data = line(["type": "system", "subtype": "init", "model": "claude-opus-5-5"])
            + delta("thinking_delta", "thinking", "Let me see")
            + delta("text_delta", "text", "Mer") + delta("text_delta", "text", "haba")
            + line(["type": "result", "result": "Merhaba", "is_error": false])
        let split = data.count / 2
        parser.feed(data.prefix(split))
        parser.feed(data.suffix(from: split))
        #expect(parser.progress.text == "Merhaba")
        #expect(parser.progress.thinking == "Let me see")
        #expect(parser.progress.model == "claude-opus-5-5")
        #expect(parser.failure == nil)
    }

    @Test func claudeUsesResultWhenNothingStreamed() {
        let parser = StreamParser(engine: .claude)
        parser.feed(line(["type": "system"]) + line(["type": "result", "result": "Four.", "is_error": false]))
        #expect(parser.progress.text == "Four.")
    }

    @Test func claudeReportsErrors() {
        let parser = StreamParser(engine: .claude)
        parser.feed(line(["type": "result", "result": "Not logged in · Please run /login", "is_error": true]))
        #expect(parser.failure != nil)
        #expect(AIRunner.explain(parser.failure ?? "", engine: .claude).contains("signed in"))
    }

    @Test func codexJoinsMessagesAndReasoning() {
        let parser = StreamParser(engine: .codex)
        parser.feed(line(["type": "thread.started", "thread_id": "x"])
            + line(["type": "item.completed", "item": ["id": "item_0", "type": "reasoning", "text": "Adding up"]])
            + line(["type": "item.completed", "item": ["id": "item_1", "type": "error", "message": "plugin config"]])
            + line(["type": "item.completed", "item": ["id": "item_2", "type": "agent_message", "text": "17 × 23 = 391"]])
            + line(["type": "turn.completed"]))
        #expect(parser.progress.text == "17 × 23 = 391")
        #expect(parser.progress.thinking == "Adding up")
        #expect(parser.failure == nil)
    }

    @Test func codexReportsAFailedTurn() {
        let parser = StreamParser(engine: .codex)
        parser.feed(line(["type": "turn.failed", "error": ["message": "429 Too Many Requests: usage limit"]]))
        #expect(AIRunner.explain(parser.failure ?? "", engine: .codex).contains("limit"))
    }

    @Test func geminiIsPlainText() {
        let parser = StreamParser(engine: .gemini)
        parser.feed(Data("Hello ".utf8))
        parser.feed(Data("there".utf8))
        #expect(parser.progress.text == "Hello there")
    }

    @Test func explainsCommonErrors() {
        #expect(AIRunner.explain("IneligibleTierError: This client is no longer supported", engine: .gemini).contains("no longer supports"))
        #expect(AIRunner.explain("", engine: .codex) == "Codex couldn't answer")
        #expect(AIRunner.explain("Error: model 'x' not found", engine: .claude).contains("model"))
    }

    @Test func claudeAsksAsAChatWithTheChosenModel() {
        let request = AIRequest(engine: .claude, model: "opus", effort: "high", system: "SYS", prompt: "Hi")
        let arguments = AIRunner.arguments(request, compatible: false)
        #expect(arguments.contains("--system-prompt") && arguments.contains("SYS"))
        #expect(arguments.contains("--tools") && arguments.contains("--safe-mode"))
        #expect(arguments.contains("opus") && arguments.contains("high"))
        #expect(AIRunner.input(request) == "Hi")
        // An older CLI gets only the basic flags.
        #expect(!AIRunner.arguments(request, compatible: true).contains("--safe-mode"))
        let codex = AIRequest(engine: .codex, model: "gpt-6-luna", effort: "low", system: "SYS", prompt: "Hi")
        #expect(AIRunner.arguments(codex, compatible: false).contains("model_reasoning_effort=\"low\""))
        #expect(AIRunner.input(codex).hasPrefix("SYS"))
    }

    @Test func defaultModelNamesDoNotLoop() {
        let engines = AIEngines.shared
        for engine in AIEngine.allCases {
            _ = engines.displayName("", engine: engine)
            _ = engines.models(for: engine)
        }
        #expect(engines.displayName("opus", engine: .claude).hasPrefix("Opus"))
    }

    @Test func grokStreamsTextAndAsksOneReadOnlyTurn() {
        let parser = StreamParser(engine: .grok)
        parser.feed(line(["type": "available_commands"]) + line(["type": "text", "data": "D"]) + line(["type": "text", "data": "ört."])
            + line(["type": "end", "stopReason": "end_turn"]))
        #expect(parser.progress.text == "Dört.")
        #expect(parser.failure == nil)
        let request = AIRequest(engine: .grok, model: "grok-4.6", effort: "xhigh", system: "SYS", prompt: "Hi")
        let arguments = AIRunner.arguments(request, compatible: false)
        #expect(arguments.contains("--prompt-file") && arguments.contains("plan") && arguments.contains("1"))
        #expect(arguments.contains("grok-4.6") && arguments.contains("xhigh"))
        if let index = arguments.firstIndex(of: "--prompt-file") { try? FileManager.default.removeItem(atPath: arguments[index + 1]) }
    }

    @Test func effortLevelsFollowEachProvider() {
        let engines = AIEngines.shared
        let claude = engines.efforts(for: .claude, model: "")
        #expect(claude.map(\.id) == ["low", "medium", "high", "xhigh", "max"])
        #expect(claude.first(where: \.recommended)?.id == "medium")
        #expect(claude.last?.warning != nil)
        #expect(engines.efforts(for: .grok, model: "").map(\.id) == ["low", "medium", "high", "xhigh"])
        #expect(engines.efforts(for: .onDevice, model: "").isEmpty)
        #expect(engines.efforts(for: .gemini, model: "").isEmpty)
    }

    @Test func modelNamesReadLikeTheApps() {
        #expect(AIEngines.claudeName("claude-opus-5-5") == "Opus 5.5")
        #expect(AIEngines.claudeName("claude-sonnet-4-5-20250929") == "Sonnet 4.5")
        #expect(AIEngines.claudeName("claude-haiku-5-5") == "Haiku 5.5")
    }

    @Test func followUpsCarryTheChat() {
        let messages = [
            AIMessage(role: .user, text: "My name is Ata."),
            AIMessage(role: .assistant, text: "Hi Ata!"),
            AIMessage(role: .assistant, text: "", error: "failed"),
            AIMessage(role: .user, text: "What's my name?"),
        ]
        let prompt = AIAssistant.prompt(for: messages, engine: .claude)
        #expect(prompt.contains("<user>\nMy name is Ata.\n</user>"))
        #expect(prompt.contains("<assistant>\nHi Ata!\n</assistant>"))
        #expect(!prompt.contains("failed"))
        #expect(prompt.hasSuffix("What's my name?"))
        #expect(AIAssistant.prompt(for: [messages[0]], engine: .claude) == "My name is Ata.")
        let task = AIMessage(role: .user, text: "Summarise", attachment: "long text")
        #expect(AIAssistant.content(of: task).contains("<text>\nlong text\n</text>"))
    }

    @Test func secretsAreNotOffered() {
        #expect(SecretText.looksSecret("sk-ant-api03-abcdefghijklmnop"))
        #expect(SecretText.looksSecret("a1b2c3d4e5f6g7h8i9j0k1l2"))
        #expect(!SecretText.looksSecret("Toplantı yarın saat 3'te, 2. katta."))
        #expect(!SecretText.looksSecret("https://example.com/a1b2c3d4e5f6g7h8i9"))
    }

    @Test func taskPromptsCarryTheText() {
        for task in AITextTask.allCases {
            #expect(task.prompt("selam dünya").contains("selam dünya"))
        }
    }

    @Test func chatTitles() {
        #expect(AIConversation.title("Hello there\nsecond line", attachment: nil) == "Hello there")
        #expect(AIConversation.title("Summarise", attachment: "Quarterly report\nmore") == "Summarise: Quarterly report")
    }
}

@Suite("Markdown")
struct MarkdownTests {
    @Test func blocks() {
        let text = """
            # Title
            Some **bold** text
            on two lines.

            - one
            - [x] done
              more about done
            1. first
            2) second

            > quoted

            ```swift
            let a = 1
            ```

            | A | B |
            |---|:-:|
            | 1 | 2 |

            ---
            """
        let blocks = MarkdownParser.parse(text)
        #expect(blocks.count == 7)
        #expect(blocks[0] == .heading(level: 1, text: "Title"))
        #expect(blocks[1] == .paragraph("Some **bold** text\non two lines."))
        guard case .list(let items) = blocks[2] else { Issue.record("no list"); return }
        #expect(items.map(\.marker) == ["•", "", "1.", "2."])
        #expect(items[1].checked == true && items[1].text == "done\nmore about done")
        #expect(blocks[3] == .quote("quoted"))
        #expect(blocks[4] == .code(language: "swift", code: "let a = 1", closed: true))
        #expect(blocks[5] == .table(header: ["A", "B"], rows: [["1", "2"]]))
        #expect(blocks[6] == .rule)
    }

    @Test func unfinishedCodeBlockWhileStreaming() {
        let blocks = MarkdownParser.parse("Here:\n```python\nprint(1)")
        #expect(blocks.last == .code(language: "python", code: "print(1)", closed: false))
    }

    @Test func boldIsNotAList() {
        #expect(MarkdownParser.parse("**Note:** this") == [.paragraph("**Note:** this")])
    }
}
