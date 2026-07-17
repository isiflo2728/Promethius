import Foundation
import SwiftData

/// A human-in-the-loop gate. The Mac pauses the agent and records one of
/// these; the user can approve/discard from either device. This is the
/// enforcement point for guardrails like "email drafts require approval
/// before Composio's send action runs."
@Model
public final class PendingApproval {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var title: String = ""
    public var detail: String = ""
    /// The proposed message body the user can edit before approving — e.g. a
    /// drafted email or Slack reply. Empty for approvals with nothing to edit
    /// (a calendar invite, a permission grant). This is what actually gets
    /// sent once approved, so editing it changes the outgoing content.
    public var draftBody: String = ""
    /// The tool + arguments the agent wants to run once approved.
    public var proposedToolName: String = ""
    public var proposedArgumentsJSON: String = "{}"
    public var statusRaw: String = ApprovalStatus.pending.rawValue

    public var agent: Agent?

    public var status: ApprovalStatus {
        get { ApprovalStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public init(title: String, detail: String = "", draftBody: String = "", proposedToolName: String, proposedArgumentsJSON: String = "{}") {
        self.id = UUID()
        self.createdAt = Date()
        self.title = title
        self.detail = detail
        self.draftBody = draftBody
        self.proposedToolName = proposedToolName
        self.proposedArgumentsJSON = proposedArgumentsJSON
    }
}

public enum ApprovalStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case approved
    case discarded
}

public extension PendingApproval {
    /// A link the user must open to resolve this approval — e.g. a Composio
    /// OAuth page when an agent run hit a not-yet-connected account. Stored
    /// as `redirect_url` inside `proposedArgumentsJSON` (the shape Composio's
    /// MANAGE_CONNECTIONS results use). Nil for draft-review approvals.
    var actionURL: URL? {
        guard let data = proposedArgumentsJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = dict["redirect_url"] as? String else { return nil }
        return URL(string: raw)
    }
}
