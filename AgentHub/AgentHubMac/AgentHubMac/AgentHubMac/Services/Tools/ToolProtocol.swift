import Foundation
import AgentKit

/// A capability the agent can invoke during a run. Two implementations exist:
/// - **local** tools that run on the Mac (files, calendar, git, web fetch)
/// - **remote** tools that delegate to Composio (mail, slack, notion, ...)
///
/// `AgentRunner` dispatches on `executionSite` to decide the path.
protocol AgentTool: Sendable {
    /// Stable identifier the model uses to call the tool.
    var name: String { get }
    var summary: String { get }
    /// Permission this tool requires to run.
    var requiredScope: PermissionScope { get }
    /// Where the work happens.
    var executionSite: ToolExecutionSite { get }
    /// Whether an invocation must be gated by a `PendingApproval` first.
    func requiresApproval(for arguments: [String: Any]) -> Bool

    func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult
}

enum ToolExecutionSite: Sendable {
    case local
    case composio
}

struct ToolResult: Sendable {
    var summary: String
    var payloadJSON: String
}

/// Everything a tool might need at call time — injected by `AgentRunner`.
struct ToolContext {
    /// nil for local tools; provided for Composio-backed tools.
    let composio: ComposioClient?
    /// The connected account to act on, for remote tools.
    let connectionId: String?
}
