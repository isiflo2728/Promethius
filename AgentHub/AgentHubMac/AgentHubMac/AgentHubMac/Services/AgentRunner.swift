import Foundation
import SwiftData
import AgentKit

/// Executes an agent's run loop on the Mac: prompt the local model, parse tool
/// calls, and **dispatch each call to the right place** —
/// - `.local` tools run in-process (files, calendar, git, web)
/// - `.composio` tools delegate to `ComposioClient`
///
/// This dispatcher is the seam the Composio switch introduced. It's also where
/// the approval guardrail is enforced: before running any tool whose
/// `requiresApproval` is true, the runner creates a `PendingApproval`, pauses,
/// and only proceeds once resolved.
@MainActor
final class AgentRunner {
    private let repository: AgentRepository
    private let inference: InferenceService
    private let composio: ComposioClient
    private let tools: [String: any AgentTool]

    init(repository: AgentRepository, inference: InferenceService, composio: ComposioClient) {
        self.repository = repository
        self.inference = inference
        self.composio = composio

        let all: [any AgentTool] = [
            MailTool(), CalendarTool(), FileWatcherTool(), GitTool(), WebFetchTool(),
        ]
        self.tools = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
    }

    func run(_ agent: Agent) async {
        try? repository.update(agent) { $0.status = .running }
        // TODO: real loop — inference.complete(...) → parse tool calls →
        // invoke(...) → append RunLogEntry → repeat until done.
    }

    /// Route a single tool call. Returns nil if the call was gated on approval.
    func invoke(toolNamed name: String, arguments: [String: Any], for agent: Agent) async throws -> ToolResult? {
        guard let tool = tools[name] else { throw RunnerError.unknownTool(name) }

        // Guardrail: gate approval-requiring calls behind a PendingApproval.
        if tool.requiresApproval(for: arguments) {
            let approval = PendingApproval(
                title: "Approve \(tool.name)",
                detail: tool.summary,
                proposedToolName: name,
                proposedArgumentsJSON: Self.encode(arguments)
            )
            try repository.update(agent) { $0.status = .waitingApproval }
            approval.agent = agent
            return nil  // execution resumes when the approval is resolved
        }

        return try await execute(tool, arguments: arguments)
    }

    private func execute(_ tool: any AgentTool, arguments: [String: Any]) async throws -> ToolResult {
        switch tool.executionSite {
        case .local:
            return try await tool.execute(arguments: arguments, context: ToolContext(composio: nil, connectionId: nil))
        case .composio:
            let connectionId = try connectionId(for: tool.requiredScope)
            let context = ToolContext(composio: composio, connectionId: connectionId)
            return try await tool.execute(arguments: arguments, context: context)
        }
    }

    private func connectionId(for scope: PermissionScope) throws -> String {
        let accounts = (try? repository.connectedAccounts()) ?? []
        guard let account = accounts.first(where: { $0.provider == scope && $0.status == .connected }) else {
            throw ComposioError.notConnected(provider: scope)
        }
        return account.composioConnectionId
    }

    private static func encode(_ arguments: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
}

enum RunnerError: Error {
    case unknownTool(String)
}
