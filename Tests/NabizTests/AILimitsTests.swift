// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

/// What the AI limits keep, pick and announce when readings fail, accounts compete or windows reset.
@Suite("AI limits")
struct AILimitsTests {
    private func status(_ account: AIAccount, used: [Double], problem: String? = nil) -> AIStatus {
        var status = AIStatus(account: account)
        status.limits = used.enumerated().map { AILimit(id: "l\($0.offset)", label: "L", used: $0.element, resetsAt: nil, primary: $0.offset == 0) }
        status.problem = problem
        return status
    }

    @Test func aFailedReadingKeepsTheLastGoodLimits() {
        let account = AIAccount(provider: .claude)
        var good = status(account, used: [0.4])
        good.plan = "Max"
        good.readAt = Date(timeIntervalSince1970: 1_000)
        let failed = status(account, used: [], problem: "Could not connect")
        let kept = failed.keepingLimits(of: good)
        #expect(kept.limits.map(\.used) == [0.4])
        #expect(kept.stale)
        #expect(kept.plan == "Max")
        #expect(kept.readAt == good.readAt)
        #expect(kept.problem == "Could not connect")
        // Nothing to keep, or a good reading: unchanged.
        #expect(!failed.keepingLimits(of: nil).stale)
        #expect(!good.keepingLimits(of: good).stale)
    }

    @Test func theMenuBarFollowsTheTightestAccountUnlessOneIsPicked() {
        let personal = AIAccount(provider: .claude)
        let work = AIAccount(provider: .codex)
        let statuses = [status(personal, used: [0.3]), status(work, used: [0.8]), status(AIAccount(provider: .gemini), used: [])]
        #expect(AIFeatured.pick(statuses, account: AIFeatured.tightest)?.status.id == work.id)
        #expect(AIFeatured.pick(statuses, account: personal.id)?.status.id == personal.id)
        // An account that is gone falls back on the tightest.
        #expect(AIFeatured.pick(statuses, account: "gone")?.status.id == work.id)
        #expect(AIFeatured.pick([], account: AIFeatured.tightest) == nil)
    }

    @Test func claudeLimitsAreKeyedByWhatTheyAre() {
        var taken: Set<String> = []
        let all = AIFetch.claudeLimitID(group: "weekly", kind: "weekly_all", model: nil, taken: &taken)
        let opus = AIFetch.claudeLimitID(group: "weekly", kind: "weekly_model", model: "Claude Opus 4", taken: &taken)
        let again = AIFetch.claudeLimitID(group: "weekly", kind: "weekly_model", model: "Claude Opus 4", taken: &taken)
        #expect(all == "claude.weekly.weekly_all")
        #expect(opus == "claude.weekly.weekly_model.claude-opus-4")
        #expect(again == "claude.weekly.weekly_model.claude-opus-4.2")
    }

    @Test func burningFastNeedsEnoughOfTheWindowAndHalfTheLimitGone() {
        let now = Date()
        let week: TimeInterval = 7 * 86_400
        func limit(used: Double, hoursIn: Double) -> AILimit {
            let resets = now.addingTimeInterval(week - hoursIn * 3600)
            var limit = AILimit(id: "x", label: "W", used: used, resetsAt: resets, period: week)
            limit.pace = PaceModel.read(used: used, resetsAt: resets, period: week, recentRate: nil, now: now)
            return limit
        }
        // 4 hours into the week (2%) with 60% used: on pace to run out, but too early to be sure.
        let early = limit(used: 0.6, hoursIn: 4)
        #expect(early.pace?.status == .behind)
        #expect(!early.burningFast)
        // A day in (14%) with 60% used: sure.
        #expect(limit(used: 0.6, hoursIn: 24).burningFast)
        // A day in with 30% used: behind, but more than half is left.
        let light = limit(used: 0.3, hoursIn: 24)
        #expect(light.pace?.status == .behind)
        #expect(!light.burningFast)
    }

    @Test func aResetIsAnnouncedOnlyWhenItMatters() {
        let old = Date(timeIntervalSince1970: 1_000_000)
        let next = old.addingTimeInterval(7 * 86_400)
        #expect(AIResetRule.didReset(before: (0.9, old), now: (0.02, next)))
        // Barely used before: nothing worth saying.
        #expect(!AIResetRule.didReset(before: (0.3, old), now: (0, next)))
        // The provider corrected the number in the same window.
        #expect(!AIResetRule.didReset(before: (0.9, old), now: (0.5, old.addingTimeInterval(60))))
        // Still climbing.
        #expect(!AIResetRule.didReset(before: (0.6, old), now: (0.7, old)))
    }

    @Test func agesReadShort() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        UserDefaults.standard.set("en", forKey: Prefs.language)
        #expect(Format.ago(now.addingTimeInterval(-20), now: now) == "just now")
        #expect(Format.ago(now.addingTimeInterval(-12 * 60), now: now) == "12m ago")
        #expect(Format.ago(now.addingTimeInterval(-3 * 3600), now: now) == "3h ago")
    }
}
