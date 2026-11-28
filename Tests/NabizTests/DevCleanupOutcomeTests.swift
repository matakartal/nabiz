// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

/// What a clean-up says it freed: measured, or the scan's size only when all of it went through, never a guess.
@Suite("Developer clean-up outcome")
struct DevCleanupOutcomeTests {
    @Test func measuredWhenThereAreFolders() {
        #expect(DevCleanup.freed(before: 900, after: 100, estimate: 5_000, skipped: 1, failed: false) == 800)
        // A folder that grew meanwhile frees nothing, not a negative number.
        #expect(DevCleanup.freed(before: 100, after: 300, estimate: 5_000, skipped: 0, failed: false) == 0)
    }

    @Test func noNumberWhenPartOfItFailed() {
        #expect(DevCleanup.freed(before: nil, after: nil, estimate: 5_000, skipped: 0, failed: false) == 5_000)
        #expect(DevCleanup.freed(before: nil, after: nil, estimate: 5_000, skipped: 2, failed: false) == nil)
        #expect(DevCleanup.freed(before: 900, after: 900, estimate: 5_000, skipped: 0, failed: true) == nil)
    }

    @Test func toolCleanUpsMeasureTheirFolders() {
        let npm = CleanupItem(kind: .npmCache, size: 1, targets: ["/tmp/npm"], detail: "")
        #expect(DevCleanup.measuredPaths(npm) == ["/tmp/npm"])
        let modules = CleanupItem(kind: .nodeModules, size: 1, targets: ["/p|/p/node_modules"], detail: "")
        #expect(DevCleanup.measuredPaths(modules) == ["/p/node_modules"])
        #expect(DevCleanup.measuredPaths(CleanupItem(kind: .dockerImages, size: 1, targets: [], detail: "")) == nil)
    }
}
