import Foundation
import AgentKit

/// Coordinates a parent agent and its sub-agent chain: decides which sub-agent
/// handles the next step, threads results between them, and hands individual
/// tool calls to `AgentRunner`. Consumes the ordering set on the orchestration
/// canvas (`SubAgent.orderIndex`).
@MainActor
final class Orchestrator {
    private let runner: AgentRunner
    private let repository: AgentRepository

    init(runner: AgentRunner, repository: AgentRepository) {
        self.runner = runner
        self.repository = repository
    }

    func execute(_ agent: Agent) async {
        let subAgents = (agent.subAgents ?? []).sorted { $0.orderIndex < $1.orderIndex }
        if subAgents.isEmpty {
            await runner.run(agent)
            return
        }
        // TODO: step through sub-agents in order, passing each one's output as
        // context to the next, invoking tools via `runner` as needed.
    }
}
