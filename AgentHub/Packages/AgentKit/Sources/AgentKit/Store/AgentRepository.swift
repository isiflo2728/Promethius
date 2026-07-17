import Foundation
import SwiftData

/// CRUD over the SwiftData store. View models talk to this instead of poking
/// the `ModelContext` directly, so persistence logic stays in one place and
/// is testable with an in-memory container.
@MainActor
public final class AgentRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Agents

    public func allAgents() throws -> [Agent] {
        let descriptor = FetchDescriptor<Agent>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    @discardableResult
    public func createAgent(name: String, summary: String = "") throws -> Agent {
        let agent = Agent(name: name, summary: summary)
        context.insert(agent)
        try context.save()
        return agent
    }

    public func update(_ agent: Agent, mutate: (Agent) -> Void) throws {
        mutate(agent)
        agent.updatedAt = Date()
        try context.save()
    }

    public func delete(_ agent: Agent) throws {
        context.delete(agent)
        try context.save()
    }

    /// Deletes several agents in one transaction — a single `save()` rather
    /// than one per agent.
    public func delete(_ agents: [Agent]) throws {
        guard !agents.isEmpty else { return }
        for agent in agents { context.delete(agent) }
        try context.save()
    }

    // MARK: - Run log

    public func appendLog(_ entry: RunLogEntry, to agent: Agent) throws {
        entry.agent = agent
        context.insert(entry)
        try context.save()
    }

    // MARK: - Approvals

    public func addApproval(_ approval: PendingApproval, to agent: Agent) throws {
        approval.agent = agent
        context.insert(approval)
        try context.save()
    }

    public func pendingApprovals() throws -> [PendingApproval] {
        let pendingRaw = ApprovalStatus.pending.rawValue
        let descriptor = FetchDescriptor<PendingApproval>(
            predicate: #Predicate { $0.statusRaw == pendingRaw },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    public func resolve(_ approval: PendingApproval, as status: ApprovalStatus) throws {
        approval.status = status
        try context.save()
    }

    /// Persist an edited draft body (e.g. after the user tweaks a proposed
    /// email reply) without resolving the approval.
    public func updateDraft(_ approval: PendingApproval, to body: String) throws {
        approval.draftBody = body
        try context.save()
    }

    // MARK: - Insights

    /// Most recent insights first, capped so the Glance view doesn't unbound.
    public func recentInsights(limit: Int = 10) throws -> [Insight] {
        var descriptor = FetchDescriptor<Insight>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    // MARK: - Activity

    /// Most recent run-log entries across every agent, newest first — the
    /// cross-agent activity feed the Today view's "Right now" section shows.
    public func recentRunLog(limit: Int = 20) throws -> [RunLogEntry] {
        var descriptor = FetchDescriptor<RunLogEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// Every run-log entry since `date`, newest first — the raw material for
    /// the Today view's weekly recap.
    public func runLog(since date: Date) throws -> [RunLogEntry] {
        let descriptor = FetchDescriptor<RunLogEntry>(
            predicate: #Predicate { $0.timestamp >= date },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Connected accounts

    public func connectedAccounts() throws -> [ConnectedAccount] {
        try context.fetch(FetchDescriptor<ConnectedAccount>())
    }
}
