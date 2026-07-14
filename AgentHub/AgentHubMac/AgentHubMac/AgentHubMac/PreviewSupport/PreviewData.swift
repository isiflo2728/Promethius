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
        seedApprovals(into: container.mainContext, agents: agents)
        seedInsights(into: container.mainContext, agents: agents)
        return container
    }()

    /// A couple of pending approvals for the "Needs you" section.
    private static func seedApprovals(into context: ModelContext, agents: [Agent]) {
        let reply = PendingApproval(
            title: "Reply ready to send",
            detail: "\u{201C}Q3 budget review\u{201D} from Sam — drafted: \u{201C}Revised numbers by Friday, can we push the call to Monday?\u{201D}",
            proposedToolName: "composio.gmail.send"
        )
        reply.agent = agents.first { $0.name == "Inbox Triage" }
        context.insert(reply)
    }

    /// A summary + a digest for the "Recent insights" section.
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
            detail: "4 upcoming items. Next: Design Sync at 2:30 PM, then a PR review due at 5:00 PM."
        )

        context.insert(summary)
        context.insert(digest)
    }

    /// The in-memory context, if a view needs it directly.
    static var context: ModelContext { container.mainContext }

    /// A repository backed by the in-memory store — the usual thing view models need.
    static var repository: AgentRepository { AgentRepository(context: context) }

    /// A handful of agents in varied states for previewing cards and lists.
    static var sampleAgents: [Agent] {
        [
            Agent(name: "Inbox Triage",
                  summary: "Sorts new mail and drafts quick replies for review.",
                  status: .running),
            Agent(name: "Standup Notes",
                  summary: "Summarizes yesterday's activity into a morning digest.",
                  status: .idle),
            Agent(name: "PR Watcher",
                  summary: "Watches the repo and pings you when a review is requested.",
                  status: .waitingApproval),
        ]
    }
}

extension Agent {
    /// A single sample agent for previews that only need one (e.g. `AgentCard`).
    @MainActor static var sample: Agent { PreviewData.sampleAgents[0] }
}
#endif
