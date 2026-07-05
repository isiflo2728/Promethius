import Foundation
import SwiftData

/// A capability an agent has been granted. Two flavors:
/// - local scopes (files, calendar) executed on the Mac
/// - remote scopes (a Composio app like Gmail/Slack) executed via Composio
@Model
public final class Permission {
    public var id: UUID = UUID()
    public var scopeRaw: String = PermissionScope.localFiles.rawValue
    public var grantedAt: Date = Date()
    public var isEnabled: Bool = true

    /// Inverse of `Agent.permissions`. Every SwiftData relationship needs an
    /// inverse for a valid CloudKit-backed schema.
    public var agent: Agent?

    public var scope: PermissionScope {
        get { PermissionScope(rawValue: scopeRaw) ?? .localFiles }
        set { scopeRaw = newValue.rawValue }
    }

    public init(scope: PermissionScope, isEnabled: Bool = true) {
        self.id = UUID()
        self.scopeRaw = scope.rawValue
        self.grantedAt = Date()
        self.isEnabled = isEnabled
    }
}

public enum PermissionScope: String, Codable, CaseIterable, Sendable {
    // Local, executed on the Mac.
    case localFiles
    case localCalendar
    case localGit
    case webFetch
    // Remote, executed through Composio.
    case composioGmail
    case composioSlack
    case composioNotion
    case composioGitHub

    public var isRemote: Bool {
        switch self {
        case .composioGmail, .composioSlack, .composioNotion, .composioGitHub:
            return true
        default:
            return false
        }
    }
}
