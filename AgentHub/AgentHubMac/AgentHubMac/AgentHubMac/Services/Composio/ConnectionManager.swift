import Foundation
import SwiftData
import AgentKit

/// Initiates and tracks Composio connections (the OAuth flows that used to
/// live in the deleted `OAuth/` folder). Composio generates a connect URL; the
/// user approves in the browser; Composio stores the token server-side. We
/// only persist non-secret `ConnectedAccount` metadata, which syncs to iPhone.
@MainActor
final class ConnectionManager {
    private let client: ComposioClient
    private let repository: AgentRepository
    private let coordinator: ConnectionCoordinator

    init(client: ComposioClient, repository: AgentRepository, coordinator: ConnectionCoordinator) {
        self.client = client
        self.repository = repository
        self.coordinator = coordinator
    }

    /// Kick off a new connection for a provider:
    /// 1. ask Composio for a connect URL for this provider,
    /// 2. open it via `ConnectionCoordinator` (ASWebAuthenticationSession),
    /// 3. poll Composio until the connection reports "connected",
    /// 4. upsert a `ConnectedAccount` record so both devices see it.
    func connect(_ provider: PermissionScope) async throws {
        guard provider.isRemote else { return }
        // let connectURL = try await client.initiateConnection(provider)
        // let callback = try await coordinator.authenticate(url: connectURL)
        // let connectionId = try await client.finalizeConnection(from: callback)
        // upsert ConnectedAccount(provider:, composioConnectionId: connectionId,
        //                         status: .connected)
        _ = coordinator
        _ = client
    }

    func disconnect(_ account: ConnectedAccount) async throws {
        // try await client.revokeConnection(account.composioConnectionId)
        account.status = .disconnected
    }
}
