import Foundation
import SwiftData

/// Enqueues and drains `AgentIntent` commands across devices via the shared
/// (CloudKit-backed) store.
///
/// - iPhone: calls `enqueue(...)` — writes the command; CloudKit syncs it.
/// - Mac: calls `pendingIntents()` on launch and on each remote-change push,
///   applies each unapplied command, then stamps `appliedAt` so a duplicate
///   delivery is ignored. Application must itself be idempotent.
@MainActor
public final class IntentQueue {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Producer side (typically the iPhone).
    ///
    /// Duplicate guard: because CloudKit lags, a user may tap "Run" again before
    /// the Mac has applied the first command and flipped the agent's status.
    /// Rather than enqueue a second identical command, we reuse the existing
    /// un-applied one. Combined with the Mac's `appliedAt` stamping, this keeps
    /// the pipeline idempotent from producer through consumer.
    @discardableResult
    public func enqueue(agentID: UUID, action: IntentAction, payload: String = "", originDevice: String = "") throws -> AgentIntent {
        if let existing = try pendingIntent(agentID: agentID, action: action, payload: payload) {
            return existing
        }
        let intent = AgentIntent(agentID: agentID, action: action, payload: payload, originDevice: originDevice)
        context.insert(intent)
        try context.save()
        return intent
    }

    /// A not-yet-applied command matching this exact target, for de-duplication
    /// and for driving optimistic "requested — waiting for Mac" UI on the phone.
    ///
    /// Note: the `agentID` (UUID) match is done in Swift, not in the
    /// `#Predicate`. SwiftData can't reliably translate UUID equality inside a
    /// predicate and traps at runtime, so we narrow to un-applied intents in
    /// the store and filter the rest in memory. The pending queue is small.
    public func pendingIntent(agentID: UUID, action: IntentAction, payload: String = "") throws -> AgentIntent? {
        try pendingIntents().first {
            $0.agentID == agentID && $0.action == action && $0.payload == payload
        }
    }

    /// Consumer side (the Mac): commands not yet applied, oldest first.
    ///
    /// The `appliedAt == nil` filter is applied in Swift rather than in a
    /// `#Predicate`: SwiftData on current OS builds traps translating an
    /// optional-to-`nil` comparison. Fetching the (small) intent set and
    /// filtering in memory is safe and avoids that landmine.
    public func pendingIntents() throws -> [AgentIntent] {
        let descriptor = FetchDescriptor<AgentIntent>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor).filter { $0.appliedAt == nil }
    }

    /// Mark a command applied. Safe to call once per command; stamping is the
    /// idempotency guard against duplicate CloudKit delivery.
    public func markApplied(_ intent: AgentIntent) throws {
        guard intent.appliedAt == nil else { return }
        intent.appliedAt = Date()
        try context.save()
    }
}
