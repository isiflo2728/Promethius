import Foundation
import Observation

/// Backs the orchestration canvas: how an agent's sub-agents are arranged and
/// wired into a chain. Node positions are UI state; the ordering is persisted
/// via each `SubAgent.orderIndex`.
@MainActor
@Observable
public final class OrchestrationViewModel {
    public let agent: Agent

    /// Canvas positions keyed by sub-agent id. Not synced — purely local view
    /// state for the Mac's drag-to-arrange canvas.
    public var nodePositions: [UUID: CGPoint] = [:]

    private let repository: AgentRepository

    public init(agent: Agent, repository: AgentRepository) {
        self.agent = agent
        self.repository = repository
    }

    public var subAgents: [SubAgent] {
        (agent.subAgents ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    public func addSubAgent(name: String, role: String) {
        let next = (subAgents.map(\.orderIndex).max() ?? -1) + 1
        let sub = SubAgent(name: name, role: role, orderIndex: next)
        try? repository.update(agent) { agent in
            var current = agent.subAgents ?? []
            sub.parent = agent
            current.append(sub)
            agent.subAgents = current
        }
    }
}
