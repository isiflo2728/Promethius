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
            agents = try repository.allAgents()
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
