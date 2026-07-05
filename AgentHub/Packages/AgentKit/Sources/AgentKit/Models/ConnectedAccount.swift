import Foundation
import SwiftData

/// Non-secret metadata about a third-party account the user connected through
/// Composio. Composio holds the actual OAuth tokens server-side — this record
/// only tracks *that* a connection exists and its status, so it is safe to
/// sync via CloudKit and display on the iPhone.
///
/// The Composio API key that authorizes calls to Composio lives ONLY on the
/// Mac (Keychain), never in this model and never on device.
@Model
public final class ConnectedAccount {
    public var id: UUID = UUID()
    /// Which Composio app this represents (Gmail, Slack, ...).
    public var providerRaw: String = PermissionScope.composioGmail.rawValue
    /// Composio's identifier for this connection. NOT a secret — it names the
    /// connection so the Mac can ask Composio to act on it.
    public var composioConnectionId: String = ""
    /// The account label Composio reports (e.g. the connected email address).
    public var accountLabel: String = ""
    public var statusRaw: String = ConnectionStatus.disconnected.rawValue
    public var connectedAt: Date?

    public var provider: PermissionScope {
        get { PermissionScope(rawValue: providerRaw) ?? .composioGmail }
        set { providerRaw = newValue.rawValue }
    }

    public var status: ConnectionStatus {
        get { ConnectionStatus(rawValue: statusRaw) ?? .disconnected }
        set { statusRaw = newValue.rawValue }
    }

    public init(provider: PermissionScope, composioConnectionId: String = "", accountLabel: String = "") {
        self.id = UUID()
        self.providerRaw = provider.rawValue
        self.composioConnectionId = composioConnectionId
        self.accountLabel = accountLabel
    }
}

public enum ConnectionStatus: String, Codable, CaseIterable, Sendable {
    case disconnected
    case connecting
    case connected
    case error
}
