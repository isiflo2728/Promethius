import SwiftUI
import AgentKit

// How AgentKit's scopes and triggers describe themselves in the create form.
// Kept in the app target so AgentKit stays free of presentation strings.

extension PermissionScope {
    var displayName: String {
        switch self {
        case .localFiles: "Files"
        case .localCalendar: "Calendar"
        case .localGit: "Git"
        case .webFetch: "Web"
        case .composioGmail: "Gmail"
        case .composioSlack: "Slack"
        case .composioNotion: "Notion"
        case .composioGitHub: "GitHub"
        }
    }

    /// What granting this scope actually lets the agent do, in the user's terms.
    var requestSummary: String {
        switch self {
        case .localFiles: "Read and write in folders you pick"
        case .localCalendar: "Read events and create new ones"
        case .localGit: "Run git commands in your repositories"
        case .webFetch: "Fetch public pages and APIs"
        case .composioGmail: "Read your mail and send on your behalf"
        case .composioSlack: "Read channels and post messages"
        case .composioNotion: "Read and edit pages"
        case .composioGitHub: "Read repositories and open pull requests"
        }
    }

    /// Scopes that can take an irreversible, outward-facing action pause the
    /// run for confirmation rather than acting on their own.
    var needsApproval: Bool {
        switch self {
        case .localGit, .composioGmail, .composioSlack, .composioGitHub: true
        case .localFiles, .localCalendar, .webFetch, .composioNotion: false
        }
    }

    var symbolName: String {
        switch self {
        case .localFiles: "folder"
        case .localCalendar: "calendar"
        case .localGit: "arrow.triangle.branch"
        case .webFetch: "globe"
        case .composioGmail: "envelope"
        case .composioSlack: "number"
        case .composioNotion: "doc.text"
        case .composioGitHub: "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// The two buckets the create form sorts tools into: things the Mac executes
/// itself, and things that round-trip through a connected Composio account.
enum ToolGroup: CaseIterable, Identifiable {
    case local
    case connected

    var id: Self { self }

    var title: String {
        switch self {
        case .local: "On This Mac"
        case .connected: "Connected Apps"
        }
    }

    var symbolName: String {
        switch self {
        case .local: "desktopcomputer"
        case .connected: "link"
        }
    }

    var scopes: [PermissionScope] {
        PermissionScope.allCases.filter { $0.isRemote == (self == .connected) }
    }
}

extension TriggerKind {
    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .schedule: "Schedule"
        case .fileChange: "Watch Folder"
        case .composioEvent: "On Event"
        }
    }
}
