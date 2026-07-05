import Foundation
import SwiftData

/// What causes an agent to run: a schedule, an incoming event from a
/// connected Composio app (e.g. new Gmail message), a local file change, or
/// a manual tap.
@Model
public final class Trigger {
    public var id: UUID = UUID()
    public var kindRaw: String = TriggerKind.manual.rawValue
    public var isEnabled: Bool = true

    /// Inverse of `Agent.triggers`. Every SwiftData relationship needs an
    /// inverse for a valid CloudKit-backed schema.
    public var agent: Agent?
    /// For `.schedule`: a cron-ish expression. For `.composioEvent`: the
    /// Composio trigger slug. For `.fileChange`: a watched path.
    public var configuration: String = ""

    public var kind: TriggerKind {
        get { TriggerKind(rawValue: kindRaw) ?? .manual }
        set { kindRaw = newValue.rawValue }
    }

    public init(kind: TriggerKind, configuration: String = "", isEnabled: Bool = true) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.configuration = configuration
        self.isEnabled = isEnabled
    }
}

public enum TriggerKind: String, Codable, CaseIterable, Sendable {
    case manual
    case schedule
    case composioEvent
    case fileChange
}
