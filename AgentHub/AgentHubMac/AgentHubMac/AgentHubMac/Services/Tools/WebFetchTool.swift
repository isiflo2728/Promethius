import Foundation
import AgentKit

/// LOCAL tool: fetches a URL and returns text/HTML. Trivial enough to keep
/// on-device rather than paying a Composio round-trip.
struct WebFetchTool: AgentTool {
    let name = "web_fetch"
    let summary = "Fetch a web page and return its text."
    let requiredScope: PermissionScope = .webFetch
    let executionSite: ToolExecutionSite = .local

    func requiresApproval(for arguments: [String: Any]) -> Bool { false }

    func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let urlString = arguments["url"] as? String, let url = URL(string: urlString) else {
            return ToolResult(summary: "invalid url", payloadJSON: "{}")
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let text = String(data: data, encoding: .utf8) ?? ""
        return ToolResult(summary: "fetched \(url.host() ?? urlString)", payloadJSON: text)
    }
}
