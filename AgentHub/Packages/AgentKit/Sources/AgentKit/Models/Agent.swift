import Foundation
import SwiftData

/// The top-level agent a user creates and runs.
///
/// CloudKit note: for the schema to sync, every stored property must have a
/// default value (or be optional) and every relationship must be optional.
@Model
public final class Agent {
    public var id: UUID = UUID()
    public var name: String = ""
    public var summary: String = ""
    public var statusRaw: String = AgentStatus.idle.rawValue
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \SubAgent.parent)
    public var subAgents: [SubAgent]? = []

    @Relationship(deleteRule: .cascade, inverse: \RunLogEntry.agent)
    public var runLog: [RunLogEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \PendingApproval.agent)
    public var pendingApprovals: [PendingApproval]? = []

    @Relationship(deleteRule: .cascade, inverse: \Insight.agent)
    public var insights: [Insight]? = []

    @Relationship(deleteRule: .cascade, inverse: \Permission.agent)
    public var permissions: [Permission]? = []

    @Relationship(deleteRule: .cascade, inverse: \Trigger.agent)
    public var triggers: [Trigger]? = []

    /// Convenience accessor over the persisted `statusRaw`.
    public var status: AgentStatus {
        get { AgentStatus(rawValue: statusRaw) ?? .idle }
        set { statusRaw = newValue.rawValue }
    }

    public init(name: String, summary: String = "", status: AgentStatus = .idle) {
        self.id = UUID()
        self.name = name
        self.summary = summary
        self.statusRaw = status.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

public enum AgentStatus: String, Codable, CaseIterable, Sendable {
    case idle
    case running
    case waitingApproval
    case paused
    case failed
}
