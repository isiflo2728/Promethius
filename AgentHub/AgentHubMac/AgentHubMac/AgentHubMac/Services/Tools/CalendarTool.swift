import Foundation
import AgentKit
// import EventKit  // Local calendar access — Mac-only, not via Composio.

/// LOCAL tool: reads/writes the user's calendar through EventKit on the Mac.
/// Composio can't touch the local calendar, so this stays a first-party tool.
struct CalendarTool: AgentTool {
    let name = "calendar"
    let summary = "Read and create events in the local macOS calendar."
    let requiredScope: PermissionScope = .localCalendar
    let executionSite: ToolExecutionSite = .local

    func requiresApproval(for arguments: [String: Any]) -> Bool {
        // Creating/modifying events is a write; reading is not.
        let action = (arguments["action"] as? String) ?? "read"
        return action != "read"
    }

    func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        // TODO: EKEventStore requestAccess + fetch/create events.
        ToolResult(summary: "calendar tool stub", payloadJSON: "{}")
    }
}
