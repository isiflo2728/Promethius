import Foundation
import Observation

/// Lightweight, at-a-glance summary — how many agents are running, how many
/// approvals are waiting. Feeds the iPhone Glance screen and the widget.
@MainActor
@Observable
public final class GlanceViewModel {
    public private(set) var runningCount: Int = 0
    public private(set) var waitingApprovalCount: Int = 0
    public private(set) var failedCount: Int = 0

    private let repository: AgentRepository

    public init(repository: AgentRepository) {
        self.repository = repository
    }

    public func refresh() {
        guard let agents = try? repository.allAgents() else { return }
        runningCount = agents.filter { $0.status == .running }.count
        waitingApprovalCount = agents.filter { $0.status == .waitingApproval }.count
        failedCount = agents.filter { $0.status == .failed }.count
    }
}
