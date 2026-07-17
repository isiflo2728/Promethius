import Foundation
import Observation

/// Drives the primary agent list on both platforms. On the Mac the list is
/// interactive; on the iPhone it is read-only + Intent-driven.
@MainActor
@Observable
public final class MissionControlViewModel {
    public private(set) var agents: [Agent] = []
    public private(set) var pendingApprovals: [PendingApproval] = []
    public var errorMessage: String?

    private let repository: AgentRepository

    public init(repository: AgentRepository) {
        self.repository = repository
    }

    public func load() {
        do {
            // Every agent, running ones first — the same population as the
            // sidebar's Agents section, so the two never disagree. (A
            // running-only filter here previously made freshly created idle
            // agents invisible on the very screen that creates them.)
            agents = try repository.allAgents().sorted {
                ($0.status == .running ? 0 : 1, $0.name) < ($1.status == .running ? 0 : 1, $1.name)
            }
            pendingApprovals = try repository.pendingApprovals()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes the agents and, by the schema's cascade rules, their run logs,
    /// pending approvals, permissions, triggers, and sub-agents.
    ///
    /// Batched deliberately: one `save()` and one re-fetch regardless of how
    /// many agents were selected.
    public func delete(_ agents: [Agent]) {
        do {
            try repository.delete(agents)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
