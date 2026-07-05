import Foundation
import AgentKit

/// Maps AgentHub's permission scopes to the Composio actions the agent may
/// invoke, and lists what's available. This is the single source of truth for
/// "which remote tools exist and what are their real Composio slugs."
///
/// The MailTool guardrail keys off this: the SEND action is marked
/// `requiresApproval`, so `AgentRunner` must route it through a
/// `PendingApproval` before it ever reaches `ComposioClient.executeAction`.
struct RemoteToolCatalog {
    struct RemoteAction {
        let slug: String
        let displayName: String
        let provider: PermissionScope
        let requiresApproval: Bool
    }

    /// Placeholder slugs — verify against Composio's live catalog before use.
    static let actions: [RemoteAction] = [
        RemoteAction(slug: "GMAIL_CREATE_EMAIL_DRAFT", displayName: "Create Gmail draft", provider: .composioGmail, requiresApproval: false),
        RemoteAction(slug: "GMAIL_SEND_EMAIL", displayName: "Send Gmail email", provider: .composioGmail, requiresApproval: true),
        RemoteAction(slug: "GMAIL_FETCH_EMAILS", displayName: "Search Gmail", provider: .composioGmail, requiresApproval: false),
        RemoteAction(slug: "SLACK_SENDS_A_MESSAGE_TO_A_SLACK_CHANNEL", displayName: "Post to Slack", provider: .composioSlack, requiresApproval: true),
        RemoteAction(slug: "NOTION_CREATE_PAGE", displayName: "Create Notion page", provider: .composioNotion, requiresApproval: false),
    ]

    static func actions(for provider: PermissionScope) -> [RemoteAction] {
        actions.filter { $0.provider == provider }
    }

    static func action(slug: String) -> RemoteAction? {
        actions.first { $0.slug == slug }
    }
}
