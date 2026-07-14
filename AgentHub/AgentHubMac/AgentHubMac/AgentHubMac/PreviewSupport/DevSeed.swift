#if DEBUG
import Foundation
import SwiftData
import AgentKit
import OSLog

/// One-time development seed so the *running* app shows sample content without
/// waiting on the agent runner (which is still a stub). Compiled only in DEBUG.
/// Each record type is seeded independently and only when that type is empty,
/// so it fills gaps even if the store already has some data (e.g. agents you
/// created by hand) and never duplicates on relaunch.
@MainActor
enum DevSeed {
    private static let log = Logger(subsystem: "AgentHubMac", category: "DevSeed")

    static func seedIfNeeded(_ context: ModelContext) {
        let agents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        var inbox = agents.first { $0.name == "Inbox Triage" }
        var standup = agents.first { $0.name == "Standup Notes" }

        // Agents (only if there are none at all).
        if agents.isEmpty {
            let newInbox = Agent(name: "Inbox Triage",
                                 summary: "Sorts new mail and drafts quick replies for review.",
                                 status: .running)
            let newStandup = Agent(name: "Standup Notes",
                                   summary: "Summarizes yesterday's activity into a morning digest.",
                                   status: .idle)
            let prWatcher = Agent(name: "PR Watcher",
                                  summary: "Watches the repo and pings you when a review is requested.",
                                  status: .waitingApproval)
            [newInbox, newStandup, prWatcher].forEach(context.insert)
            inbox = newInbox
            standup = newStandup
            log.debug("Seeded 3 agents")
        }

        // "Needs you" — re-seed whenever nothing is *pending*, so the section
        // reappears on relaunch after you approve/discard the sample card.
        // Filter in Swift (not via #Predicate) to avoid captured-value quirks.
        let allApprovals = (try? context.fetch(FetchDescriptor<PendingApproval>())) ?? []
        let hasPending = allApprovals.contains { $0.status == .pending }
        if !hasPending {
            let reply = PendingApproval(
                title: "Reply ready to send",
                detail: "\u{201C}Q3 budget review\u{201D} from Sam — drafted: \u{201C}Revised numbers by Friday, can we push the call to Monday?\u{201D}",
                proposedToolName: "composio.gmail.send"
            )
            reply.agent = inbox
            context.insert(reply)
            log.debug("Seeded 1 pending approval")
        }

        // "Recent insights".
        let insights = (try? context.fetch(FetchDescriptor<Insight>())) ?? []
        if insights.isEmpty {
            let summary = Insight(
                title: "Design Sync — summary",
                source: "Meeting Notes",
                kind: .summary,
                iconName: "clock",
                detail: "Agreed to ship the new onboarding by Friday; Sam owns the copy pass.",
                bullets: ["Finalize onboarding copy — Sam",
                          "Revised budget numbers by Fri",
                          "Book follow-up for Monday"]
            )
            summary.agent = standup

            let digest = Insight(
                title: "This week",
                source: "Calendar watch",
                kind: .digest,
                iconName: "calendar",
                detail: "4 upcoming items. Next: Design Sync at 2:30 PM, then a PR review due at 5:00 PM."
            )
            context.insert(summary)
            context.insert(digest)
            log.debug("Seeded 2 insights")
        }

        do {
            try context.save()
            log.debug("DevSeed save OK — approvals now, insights now")
        } catch {
            log.error("DevSeed save FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
