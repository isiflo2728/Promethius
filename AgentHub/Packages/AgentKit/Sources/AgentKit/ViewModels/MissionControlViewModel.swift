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

    public func createAgent(named name: String) {
        do {
            try repository.createAgent(name: name)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
