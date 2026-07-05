import Foundation
import AgentKit
// import CoreServices  // FSEvents — Mac-only.

/// LOCAL tool: watches a directory for changes via FSEvents and can read file
/// contents. Purely on-device; never routed through Composio.
struct FileWatcherTool: AgentTool {
    let name = "files"
    let summary = "Watch a folder and read local files on the Mac."
    let requiredScope: PermissionScope = .localFiles
    let executionSite: ToolExecutionSite = .local

    func requiresApproval(for arguments: [String: Any]) -> Bool {
        // Reading/watching is safe; writing/deleting should be gated.
        let action = (arguments["action"] as? String) ?? "read"
        return action == "write" || action == "delete"
    }

    func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        // TODO: FSEventStream for watching; FileManager for reads.
        ToolResult(summary: "file watcher stub", payloadJSON: "{}")
    }
}
