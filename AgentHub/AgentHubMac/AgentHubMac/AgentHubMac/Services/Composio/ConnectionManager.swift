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

        // 1. Ask the service to start a connect flow and hand back Composio's URL.
        let connection = try await client.initiateConnection(provider)

        // 2. Open Composio's connect URL; the user approves in the browser.
        _ = try await coordinator.authenticate(url: connection.connectUrl)

        // 3. Ask the service whether the connection is now live.
        let status = try await client.connectionStatus(provider)

        // 4. Persist non-secret metadata so both devices see it via CloudKit.
        try repository.upsertConnectedAccount(
            provider: provider,
            connectionId: status.connectionId ?? connection.connectionId,
            accountLabel: status.accountLabel ?? "",
            status: status.connectionStatus
        )
    }

    func disconnect(_ account: ConnectedAccount) async throws {
        // The service revokes the token in Composio; here we only flip local
        // metadata. Wire `client.revokeConnection(...)` once the service adds it.
        account.status = .disconnected
    }
}
