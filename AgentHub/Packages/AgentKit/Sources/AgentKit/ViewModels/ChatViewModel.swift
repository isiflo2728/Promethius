import Foundation
import Observation

/// Backs the harness chat surface: sends user messages to the agent-harness
/// SSE backend and turns the streamed `HarnessEvent`s into a growing
/// transcript plus a live "what's it doing" status line.
@MainActor
@Observable
public final class ChatViewModel {
    public private(set) var transcript: [ChatEntry] = []
    public private(set) var isWorking = false
    /// One-line description of what the loop is doing right now ("Thinking…",
    /// "Running GMAIL_FETCH_EMAILS…"). Nil when idle.
    public private(set) var statusText: String?

    private let client: HarnessClient
    /// The server keys conversation history off this; one UUID per
    /// conversation, rotated only by clear().
    private var sessionID = UUID().uuidString
    private var streamTask: Task<Void, Never>?

    public init(client: HarnessClient = HarnessClient()) {
        self.client = client
    }

    public func send(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isWorking else { return }

        transcript.append(ChatEntry(kind: .user, text: message))
        isWorking = true
        statusText = "Contacting agent…"

        streamTask = Task {
            var sawOutcome = false
            do {
                for try await event in client.chat(sessionID: sessionID, message: message) {
                    handle(event, sawOutcome: &sawOutcome)
                }
                // The backend has no error event: a crash mid-run (model
                // server down, tool blew up the loop) just ends the stream.
                if !sawOutcome {
                    transcript.append(ChatEntry(
                        kind: .error,
                        text: "The agent stopped without answering — check that the model server (LM Studio/Ollama) is running, then try again."
                    ))
                }
            } catch is CancellationError {
                // cancel() already updated the transcript.
            } catch {
                transcript.append(ChatEntry(kind: .error, text: error.localizedDescription))
            }
            isWorking = false
            statusText = nil
        }
    }

    /// Stop the in-flight run. The server rolls an interrupted run's messages
    /// back out of the session history (see server.py), so the same session —
    /// and the conversation context — stays usable for the next message.
    public func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isWorking = false
        statusText = nil
        transcript.append(ChatEntry(kind: .notice, text: "Stopped."))
    }

    /// Wipe the transcript and start over with a new server-side session.
    public func clear() {
        streamTask?.cancel()
        streamTask = nil
        sessionID = UUID().uuidString
        transcript = []
        isWorking = false
        statusText = nil
    }

    private func handle(_ event: HarnessEvent, sawOutcome: inout Bool) {
        switch event {
        case .turnStart(let turn):
            statusText = turn == 1 ? "Thinking…" : "Thinking… (turn \(turn))"
        case .thinkingStatus:
            break  // turnStart already set the status line.
        case .toolRunning(let name):
            statusText = "Running \(name)…"
        case .thinking(let text):
            transcript.append(ChatEntry(kind: .thinking, text: text))
        case .toolCall(_, let name, let arguments):
            transcript.append(ChatEntry(kind: .toolCall, text: "\(name) \(arguments)", toolName: name))
        case .toolResult(_, let name, let result):
            transcript.append(ChatEntry(kind: .toolResult, text: result, toolName: name))
        case .final(let text):
            sawOutcome = true
            transcript.append(ChatEntry(kind: .assistant, text: text))
        case .maxTurns:
            sawOutcome = true
            transcript.append(ChatEntry(
                kind: .error,
                text: "The agent hit its turn limit before finishing. Try a more specific request."
            ))
        case .error(let message):
            sawOutcome = true
            transcript.append(ChatEntry(kind: .error, text: message))
        }
    }
}

/// One row of the chat transcript. A lightweight view value, not persisted.
public struct ChatEntry: Identifiable, Sendable {
    public enum Kind: Sendable {
        case user
        case assistant
        /// Model commentary that accompanied a tool call.
        case thinking
        case toolCall
        case toolResult
        case error
        /// Local bookkeeping ("Stopped."), not from the model.
        case notice
    }

    public let id = UUID()
    public let kind: Kind
    public let text: String
    public let toolName: String?
    public let timestamp = Date()

    public init(kind: Kind, text: String, toolName: String? = nil) {
        self.kind = kind
        self.text = text
        self.toolName = toolName
    }
}
