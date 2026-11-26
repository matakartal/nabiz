// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import Foundation
import Testing
@testable import Nabiz

/// Site blocking, the volume query and aliases.
@MainActor
@Suite("Focus sites, sound, aliases")
struct QuickWinsTests {
    init() {
        Prefs.registerDefaults()
        UserDefaults.standard.set("en", forKey: Prefs.language)
    }

    @Test func blocksSiteAndSubdomains() {
        let sites = ["youtube.com", "www.x.com"]
        #expect(SiteBlocker.isBlocked(host: "youtube.com", in: sites))
        #expect(SiteBlocker.isBlocked(host: "m.YouTube.com", in: sites))
        #expect(SiteBlocker.isBlocked(host: "x.com", in: sites))
        #expect(!SiteBlocker.isBlocked(host: "notyoutube.com", in: sites))
        #expect(!SiteBlocker.isBlocked(host: "github.com", in: sites))
    }

    @Test func readsHosts() {
        #expect(SiteBlocker.host(of: "https://www.youtube.com/watch?v=1") == "www.youtube.com")
        #expect(SiteBlocker.host(of: "reddit.com") == "reddit.com")
        #expect(SiteBlocker.host(of: " news.ycombinator.com/item ") == "news.ycombinator.com")
    }

    @Test func volumeQuery() {
        #expect(SoundOutput.level(in: "ses 40") == 40)
        #expect(SoundOutput.level(in: "volume 100%") == 100)
        #expect(SoundOutput.level(in: "vol %5") == 5)
        #expect(SoundOutput.level(in: "ses 140") == nil)
        #expect(SoundOutput.level(in: "sesame") == nil)
    }

    @Test func layoutFrames() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let left = WindowLayout(name: "", x: 0, y: 0, width: 67, height: 100).frame(in: screen)
        #expect(left == CGRect(x: 0, y: 0, width: 670, height: 800))
        let topRight = WindowLayout(name: "", x: 50, y: 0, width: 50, height: 50).frame(in: screen)
        #expect(topRight == CGRect(x: 500, y: 400, width: 500, height: 400))
        // Never past the screen's edge.
        let wide = WindowLayout(name: "", x: 80, y: 90, width: 50, height: 50).frame(in: screen)
        #expect(wide.maxX <= 1000 && wide.minY >= 0)
    }

    @Test func aiCommandPrompt() {
        let inline = AICommand(name: "x", prompt: "Reply to: {text}").fullPrompt("hi")
        #expect(inline.hasPrefix("Reply to: hi"))
        let appended = AICommand(name: "x", prompt: "Shorten it.").fullPrompt("hello")
        #expect(appended.contains("<text>\nhello\n</text>"))
    }

    @Test func translateQuery() {
        #expect(TranslateQuery.text(in: "çevir good morning") == "good morning")
        #expect(TranslateQuery.text(in: "translate merhaba") == "merhaba")
        #expect(TranslateQuery.text(in: "çevir") == nil)
        #expect(TranslateQuery.text(in: "cevap") == nil)
        #expect(TranslateQuery.task(for: "günaydın, nasılsın?") == .toEnglish)
        #expect(TranslateQuery.task(for: "good morning, how are you?") == .toTurkish)
    }

    @Test func aliasMatchesWholeQuery() {
        let store = ItemBindings.shared
        store.setAlias("ZZq", id: "cmd:test-alias", title: "Test")
        defer { store.remove("cmd:test-alias") }
        #expect(store.id(forAlias: "zzq") == "cmd:test-alias")
        #expect(store.id(forAlias: " ZZQ ") == "cmd:test-alias")
        #expect(store.id(forAlias: "zz") == nil)
    }
}
