import Foundation
import SwiftData
import AgentKit

/// Executes an agent's run on the Mac by driving the agent-harness backend
/// (`agent-harness/server.py`): the Python side owns the ReAct loop, the
/// model, and the Composio tools; this runner streams the loop's events into
/// the agent's persisted `RunLogEntry` timeline and status transitions, so a
/// run is watchable live from the detail view (and, via CloudKit, the iPhone).
///
/// The local-tool dispatch below (`invoke`/`execute`) predates the harness and
/// is kept for the planned in-process tools (files, calendar, git); it is also
/// where the approval guardrail is enforced: before running any tool whose
/// `requiresApproval` is true, the runner creates a `PendingApproval`, pauses,
/// and only proceeds once resolved. Pre-execution approval for *harness* tool
/// calls needs backend support (the loop currently dispatches immediately) —
/// until then harness tool calls are logged as they happen, not gated.
@MainActor
final class AgentRunner {
    private let repository: AgentRepository
    private let inference: InferenceService
    private let composio: ComposioClient?
    private let harness: HarnessClient
    private let tools: [String: any AgentTool]

    init(
        repository: AgentRepository,
        inference: InferenceService = InferenceService(),
        composio: ComposioClient? = nil,
        harness: HarnessClient = HarnessClient()
    ) {
        self.repository = repository
        self.inference = inference
        self.composio = composio
        self.harness = harness

        let all: [any AgentTool] = [
            MailTool(), CalendarTool(), FileWatcherTool(), GitTool(), WebFetchTool(),
        ]
        self.tools = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
    }

    /// One agent run = one harness conversation turn. The agent's summary is
    /// its task; every streamed event becomes a run-log row as it arrives.
    func run(_ agent: Agent) async {
        guard agent.status != .running else { return }

        let task = agent.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else {
            log(.error, "This agent has no summary describing what it should do — edit it and add one.", to: agent)
            try? repository.update(agent) { $0.status = .failed }
            return
        }

        try? repository.update(agent) { $0.status = .running }
        log(.system, "Run started", to: agent)

        // Fresh session per run: an agent run is a self-contained job, not a
        // conversation — carrying history across runs would grow the context
        // unboundedly and make runs non-repeatable.
        let sessionID = "agent-\(agent.id.uuidString)-run-\(UUID().uuidString)"
        let prompt = "You are \"\(agent.name)\", an autonomous agent. Complete this task now, using your tools as needed, then report the outcome: \(task)"

        var outcome: AgentStatus?
        do {
            for try await event in harness.chat(sessionID: sessionID, message: prompt) {
                switch event {
                case .turnStart, .thinkingStatus, .toolRunning:
                    break  // transient status, not worth persisting
                case .thinking(let text):
                    log(.thought, text, to: agent)
                case .toolCall(_, let name, let arguments):
                    log(.toolCall, "Calling \(name) \(arguments)", to: agent, tool: name)
                    fileDraftApprovals(inArguments: arguments, toolName: name, for: agent)
                case .toolResult(_, let name, let result):
                    log(.toolResult, String(result.prefix(500)), to: agent, tool: name)
                    fileAuthApprovals(inResult: result, toolName: name, for: agent)
                case .final(let text):
                    log(.system, text, to: agent)
                    outcome = .idle
                case .maxTurns:
                    log(.error, "Stopped: hit the turn limit before finishing.", to: agent)
                    outcome = .failed
                case .error(let message):
                    log(.error, message, to: agent)
                    outcome = .failed
                }
            }
            if outcome == nil {
                log(.error, "The run ended without a result — the backend may have stopped mid-run.", to: agent)
            }
        } catch {
            log(.error, error.localizedDescription, to: agent)
        }

        try? repository.update(agent) { $0.status = outcome ?? .failed }
    }

    private func log(_ kind: LogKind, _ message: String, to agent: Agent, tool: String? = nil) {
        try? repository.appendLog(RunLogEntry(kind: kind, message: message, toolName: tool), to: agent)
    }

    // MARK: - Surfacing approvals from harness events

    /// Composio reports a not-yet-connected account by returning a
    /// `redirect_url` OAuth link inside the tool result. Buried in the
    /// activity log it's plain, unclickable text — file it as a
    /// `PendingApproval` instead so it lands in Today's "Needs you" and Pulse
    /// with an Open Link button.
    private func fileAuthApprovals(inResult result: String, toolName: String, for agent: Agent) {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return }

        for hit in Self.redirectURLs(in: json) {
            let service = hit.toolkit.capitalized
            fileApprovalIfNew(
                title: "Connect \(service)",
                detail: "\(agent.name) needs access to your \(service) account. Open the link to sign in, then run the agent again.",
                toolName: toolName,
                argumentsJSON: Self.encode(["redirect_url": hit.url]),
                for: agent
            )
        }
    }

    /// Recursively collect `redirect_url` values (with the toolkit that owns
    /// each) from anywhere inside a tool-result JSON payload.
    private static func redirectURLs(in json: Any, keyHint: String = "account") -> [(toolkit: String, url: String)] {
        if let dict = json as? [String: Any] {
            if let url = dict["redirect_url"] as? String {
                return [((dict["toolkit"] as? String) ?? keyHint, url)]
            }
            return dict.flatMap { key, value in redirectURLs(in: value, keyHint: key) }
        }
        if let array = json as? [Any] {
            return array.flatMap { redirectURLs(in: $0, keyHint: keyHint) }
        }
        return []
    }

    /// When the agent creates a draft (e.g. GMAIL_CREATE_EMAIL_DRAFT inside a
    /// COMPOSIO_MULTI_EXECUTE_TOOL call), surface it as an approval so the
    /// user reviews the text before sending. Note: the backend has already
    /// executed the draft-creation by the time this event arrives — this
    /// reviews a saved draft, it does not gate its creation.
    private func fileDraftApprovals(inArguments arguments: String, toolName: String, for agent: Agent) {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tools = json["tools"] as? [[String: Any]] else { return }

        for tool in tools {
            guard let slug = tool["tool_slug"] as? String,
                  slug.localizedCaseInsensitiveContains("draft") else { continue }
            let args = tool["arguments"] as? [String: Any] ?? [:]
            let body = (args["body"] as? String)
                ?? (args["message_body"] as? String)
                ?? (args["message"] as? String) ?? ""
            let recipient = (args["recipient_email"] as? String) ?? (args["to"] as? String) ?? ""
            guard !body.isEmpty else { continue }

            fileApprovalIfNew(
                title: recipient.isEmpty ? "Review draft" : "Review draft to \(recipient)",
                detail: "\(agent.name) drafted this via \(slug). Review or edit it before sending.",
                draftBody: body,
                toolName: slug,
                for: agent
            )
        }
    }

    /// Skips filing when an identically-titled approval is already pending on
    /// this agent — reruns of a blocked agent re-detect the same auth link.
    private func fileApprovalIfNew(
        title: String, detail: String, draftBody: String = "",
        toolName: String, argumentsJSON: String = "{}", for agent: Agent
    ) {
        let alreadyPending = (agent.pendingApprovals ?? [])
            .contains { $0.status == .pending && $0.title == title }
        guard !alreadyPending else { return }

        let approval = PendingApproval(
            title: title,
            detail: detail,
            draftBody: draftBody,
            proposedToolName: toolName,
            proposedArgumentsJSON: argumentsJSON
        )
        try? repository.addApproval(approval, to: agent)
        log(.system, "Waiting on you: \(title) — see Needs You on the Today screen.", to: agent)
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
            guard let composio else { throw ComposioError.notConnected(provider: tool.requiredScope) }
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
