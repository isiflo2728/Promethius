import Foundation
import AgentKit

/// Email tool — now a thin wrapper over Composio's Gmail actions rather than a
/// direct Gmail API client. Composio owns the OAuth token.
///
/// GUARDRAIL: this tool NEVER sends directly. Creating a draft is allowed
/// freely; sending is marked `requiresApproval` so `AgentRunner` must route it
/// through a `PendingApproval` before `ComposioClient.executeAction` runs the
/// send slug. Enforced here in code, not just by convention.
struct MailTool: AgentTool {
    let name = "mail"
    let summary = "Draft and (with approval) send email via the connected Gmail account."
    let requiredScope: PermissionScope = .composioGmail
    let executionSite: ToolExecutionSite = .composio

    func requiresApproval(for arguments: [String: Any]) -> Bool {
        // Any send-type action must be approved; drafting never is.
        let intent = (arguments["intent"] as? String) ?? "draft"
        return intent == "send"
    }

    func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let composio = context.composio, let connectionId = context.connectionId else {
            throw ComposioError.notConnected(provider: .composioGmail)
        }
        let intent = (arguments["intent"] as? String) ?? "draft"
        let slug = intent == "send" ? "GMAIL_SEND_EMAIL" : "GMAIL_CREATE_EMAIL_DRAFT"

        // Defense in depth: even if a caller bypassed the runner, refuse to
        // send without having been through approval.
        if intent == "send", (arguments["_approved"] as? Bool) != true {
            throw ComposioError.executionFailed(slug: slug)
        }

        let data = try await composio.executeAction(slug: slug, connectionId: connectionId, arguments: arguments)
        return ToolResult(summary: intent == "send" ? "Email sent" : "Draft created",
                          payloadJSON: String(data: data, encoding: .utf8) ?? "{}")
    }
}
