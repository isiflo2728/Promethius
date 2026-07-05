import Foundation
import Observation

/// Backs the create-agent form. Collects a name/summary, an initial set of
/// permissions (local + Composio remote), and sub-agents, then persists.
@MainActor
@Observable
public final class CreateAgentViewModel {
    public var name: String = ""
    public var summary: String = ""
    public var selectedScopes: Set<PermissionScope> = []
    public var errorMessage: String?

    private let repository: AgentRepository

    public init(repository: AgentRepository) {
        self.repository = repository
    }

    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Scopes the user picked that require a Composio connection before the
    /// agent can actually use them.
    public var remoteScopesNeedingConnection: [PermissionScope] {
        selectedScopes.filter { $0.isRemote }.sorted { $0.rawValue < $1.rawValue }
    }

    @discardableResult
    public func save() -> Agent? {
        guard canSave else { return nil }
        do {
            let agent = try repository.createAgent(name: name, summary: summary)
            try repository.update(agent) { agent in
                agent.permissions = selectedScopes.map { Permission(scope: $0) }
            }
            return agent
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
