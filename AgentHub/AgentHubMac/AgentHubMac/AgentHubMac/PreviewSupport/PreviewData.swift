#if DEBUG
import SwiftUI
import SwiftData
import AgentKit

/// Shared, in-memory setup for SwiftUI previews so any view-model preview is a
/// one-liner. Debug-only — never compiled into release builds.
///
/// Usage:
/// ```swift
/// #Preview {
///     CreateAgentView(viewModel: CreateAgentViewModel(repository: PreviewData.repository))
/// }
/// ```
@MainActor
enum PreviewData {
    /// A throwaway in-memory store — no disk, no CloudKit — seeded with a few
    /// sample agents so grids/lists have something to show.
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: Agent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agents = sampleAgents
        for agent in agents {
            container.mainContext.insert(agent)
        }
        // Fill each agent's model / trigger / permissions / run log so the
        // detail view renders fully — same seed the running app uses.
        for agent in agents {
            DevSeed.applyDetail(to: agent, context: container.mainContext)
        }
        seedApprovals(into: container.mainContext, agents: agents)
        seedInsights(into: container.mainContext, agents: agents)
        return container
    }()

    /// A fully-populated agent for the `AgentDetailView` preview — the one that
    /// matches the reference mockup (git-commit trigger, DeepSeek model).
    static var detailedAgent: Agent {
        (try? context.fetch(FetchDescriptor<Agent>()))?
            .first { $0.name == "Repo Sentinel" } ?? sampleAgents[0]
    }

    /// A couple of pending approvals for the "Needs you" section.
    private static func seedApprovals(into context: ModelContext, agents: [Agent]) {
        let inbox = agents.first { $0.name == "Inbox Triage" }
        let standup = agents.first { $0.name == "Standup Notes" }

        let reply = PendingApproval(
            title: "Reply ready to send",
            detail: "Re: \u{201C}Q3 budget review\u{201D} — to Sam",
            draftBody: "Revised numbers by Friday. Can we push the call to Monday?",
            proposedToolName: "composio.gmail.send"
        )
        reply.agent = inbox

        let slack = PendingApproval(
            title: "Post standup to Slack",
            detail: "To #engineering",
            draftBody: "Yesterday: shipped sidebar nav. Today: wiring the agent runner. No blockers so far.",
            proposedToolName: "composio.slack.send"
        )
        slack.agent = standup

        let invite = PendingApproval(
            title: "Send calendar invite",
            detail: "\u{201C}Design review\u{201D} Thursday 3:00–3:30 PM with Sam and Alex — agenda: sign off the onboarding copy.",
            proposedToolName: "composio.googlecalendar.create"
        )
        invite.agent = inbox

        [reply, slack, invite].forEach(context.insert)
    }

    /// A spread of insights for the "Recent insights" section — each with a
    /// body and three bullets so the grid tiles stay uniform.
    private static func seedInsights(into context: ModelContext, agents: [Agent]) {
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
        summary.agent = agents.first { $0.name == "Standup Notes" }

        let digest = Insight(
            title: "This week",
            source: "Calendar watch",
            kind: .digest,
            iconName: "calendar",
            detail: "4 upcoming items across the week — here's what's next.",
            bullets: ["Design Sync — today 2:30 PM",
                      "PR review due — today 5:00 PM",
                      "1:1 with Sam — Thu 11:00 AM"]
        )

        let prNote = Insight(
            title: "PR #142 needs a nudge",
            source: "PR Watcher",
            kind: .note,
            iconName: "arrow.triangle.pull",
            detail: "Open two days with no review, and you're the requested reviewer.",
            bullets: ["Touches AgentRunner + tools",
                      "1 failing check: unit tests",
                      "Author pinged twice"]
        )

        let inboxInsight = Insight(
            title: "Inbox triaged",
            source: "Inbox Triage",
            kind: .summary,
            iconName: "tray.full",
            detail: "Sorted 18 new messages; a few need you, the rest are handled.",
            bullets: ["3 flagged for a reply",
                      "2 drafts ready to review",
                      "13 archived automatically"]
        )

        let metrics = Insight(
            title: "Weekly metrics",
            source: "Standup Notes",
            kind: .digest,
            iconName: "chart.bar",
            detail: "Activity is up week-over-week; here's the shape of it.",
            bullets: ["12 PRs merged (+3)",
                      "4 agents active",
                      "0 failed runs"]
        )

        [summary, digest, prNote, inboxInsight, metrics].forEach(context.insert)
    }

    /// The in-memory context, if a view needs it directly.
    static var context: ModelContext { container.mainContext }

    /// A repository backed by the in-memory store — the usual thing view models need.
    static var repository: AgentRepository { AgentRepository(context: context) }

    /// A handful of agents in varied states for previewing cards and lists.
    /// Most are `.running` so Mission Control (running-only) has a full grid;
    /// a couple stay idle/waiting to exercise Pulse.
    static var sampleAgents: [Agent] {
        [
            Agent(name: "Inbox Triage",
                  summary: "Sorts new mail and drafts quick replies for review.",
                  status: .running),
            Agent(name: "Meeting Notetaker",
                  summary: "Joins calls and turns them into shared summaries.",
                  status: .running),
            Agent(name: "Repo Sentinel",
                  summary: "Watches CI and surfaces failing checks as they land.",
                  status: .running),
            Agent(name: "Expense Sorter",
                  summary: "Categorizes receipts and flags anything over budget.",
                  status: .running),
            Agent(name: "Standup Notes",
                  summary: "Summarizes yesterday's activity into a morning digest.",
                  status: .idle),
            Agent(name: "PR Watcher",
                  summary: "Watches the repo and pings you when a review is requested.",
                  status: .waitingApproval),
            Agent(name: "Code Reviewer",
                  summary: "Reviews staged diffs before push and flags risky changes.",
                  status: .failed),
        ]
    }
}

extension Agent {
    /// A single sample agent for previews that only need one (e.g. `AgentCard`).
    @MainActor static var sample: Agent { PreviewData.sampleAgents[0] }
}
#endif
