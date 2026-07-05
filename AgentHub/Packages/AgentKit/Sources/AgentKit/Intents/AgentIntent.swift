import Foundation
import SwiftData

/// A cross-device command: the iPhone enqueues one, the Mac applies it.
///
/// Because CloudKit delivery is delayed, unordered, and can duplicate, every
/// command is designed to be **idempotent** — identified by `id`, stamped with
/// `appliedAt` once the Mac executes it. Re-delivering an already-applied
/// command is a no-op. Design this in now; retrofitting it later is painful.
@Model
public final class AgentIntent {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    /// The agent this command targets.
    public var agentID: UUID = UUID()
    public var actionRaw: String = IntentAction.run.rawValue
    /// Optional payload (e.g. the approval id for `.approve`).
    public var payload: String = ""
    /// Set by the Mac the first time it applies this command. Non-nil ⇒ done.
    public var appliedAt: Date?
    /// Device that issued the command, for debugging/audit.
    public var originDevice: String = ""

    public var action: IntentAction {
        get { IntentAction(rawValue: actionRaw) ?? .run }
        set { actionRaw = newValue.rawValue }
    }

    public var isApplied: Bool { appliedAt != nil }

    public init(agentID: UUID, action: IntentAction, payload: String = "", originDevice: String = "") {
        self.id = UUID()
        self.createdAt = Date()
        self.agentID = agentID
        self.actionRaw = action.rawValue
        self.payload = payload
        self.originDevice = originDevice
    }
}

public enum IntentAction: String, Codable, CaseIterable, Sendable {
    case run
    case pause
    case approve
    case discard
}
