import Foundation
import AgentKit

/// LOCAL tool: runs git operations against a repository on the Mac's disk.
/// Stays local because it operates on local working copies, not a hosted API.
/// (Hosted GitHub actions — PRs, issues — would instead go through Composio's
/// GitHub app as a remote tool.)
struct GitTool: AgentTool {
    let name = "git"
    let summary = "Run read/status/diff and gated write operations on a local git repo."
    let requiredScope: PermissionScope = .localGit
    let executionSite: ToolExecutionSite = .local

    func requiresApproval(for arguments: [String: Any]) -> Bool {
        // status/diff/log are safe; commit/push/reset must be approved.
        let command = (arguments["command"] as? String) ?? "status"
        let safe: Set<String> = ["status", "diff", "log", "show"]
        return !safe.contains(command)
    }

    func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        // TODO: shell out to git via Process against arguments["path"].
        ToolResult(summary: "git tool stub", payloadJSON: "{}")
    }
}
