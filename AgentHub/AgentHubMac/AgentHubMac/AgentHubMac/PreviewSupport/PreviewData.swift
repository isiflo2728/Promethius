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
        for agent in sampleAgents {
            container.mainContext.insert(agent)
        }
        return container
    }()

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
