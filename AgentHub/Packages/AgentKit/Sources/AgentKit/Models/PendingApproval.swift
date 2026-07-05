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
    /// The tool + arguments the agent wants to run once approved.
    public var proposedToolName: String = ""
    public var proposedArgumentsJSON: String = "{}"
    public var statusRaw: String = ApprovalStatus.pending.rawValue

    public var agent: Agent?

    public var status: ApprovalStatus {
        get { ApprovalStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public init(title: String, detail: String = "", proposedToolName: String, proposedArgumentsJSON: String = "{}") {
        self.id = UUID()
        self.createdAt = Date()
        self.title = title
        self.detail = detail
        self.proposedToolName = proposedToolName
        self.proposedArgumentsJSON = proposedArgumentsJSON
    }
}

public enum ApprovalStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case approved
    case discarded
}
