import Foundation
import SwiftData

/// A single line in an agent's activity timeline — thought, tool call,
/// tool result, or error. Synced so the iPhone can replay the run.
@Model
public final class RunLogEntry {
    public var id: UUID = UUID()
    public var timestamp: Date = Date()
    public var kindRaw: String = LogKind.thought.rawValue
    public var message: String = ""
    /// Name of the tool involved, when `kind` is `.toolCall` / `.toolResult`.
    public var toolName: String?

    public var agent: Agent?

    public var kind: LogKind {
        get { LogKind(rawValue: kindRaw) ?? .thought }
        set { kindRaw = newValue.rawValue }
    }

    public init(kind: LogKind, message: String, toolName: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.kindRaw = kind.rawValue
        self.message = message
        self.toolName = toolName
    }
}

public enum LogKind: String, Codable, CaseIterable, Sendable {
    case thought
    case toolCall
    case toolResult
    case error
    case system
}
