import Foundation
import Observation

/// Backs a single agent's detail screen: its run log, pending approvals, and
/// the run/pause/approve controls. On the iPhone these controls enqueue an
/// `AgentIntent` rather than executing directly.
@MainActor
@Observable
public final class AgentDetailViewModel {
    public let agent: Agent
    public var errorMessage: String?

    private let repository: AgentRepository
    private let intentQueue: IntentQueue?
    private let originDevice: String

    /// - Parameter intentQueue: pass on the iPhone (remote control). Leave nil
    ///   on the Mac, where the executor acts on the agent directly.
    public init(agent: Agent, repository: AgentRepository, intentQueue: IntentQueue? = nil, originDevice: String = "") {
        self.agent = agent
        self.repository = repository
        self.intentQueue = intentQueue
        self.originDevice = originDevice
    }

    public var runLog: [RunLogEntry] {
        (agent.runLog ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    /// True while a command has been enqueued from this device but the Mac
    /// hasn't applied it yet (CloudKit still propagating). Drives an optimistic
    /// "Requested…" state so a lagging sync doesn't look like a dead button and
    /// tempt the user into tapping again.
    public func isRequestInFlight(_ action: IntentAction) -> Bool {
        guard let intentQueue else { return false }
        return (try? intentQueue.pendingIntent(agentID: agent.id, action: action)) != nil
    }

    public func run() { dispatch(.run) }
    public func pause() { dispatch(.pause) }

    public func approve(_ approval: PendingApproval) {
        if let intentQueue {
            _ = try? intentQueue.enqueue(agentID: agent.id, action: .approve, payload: approval.id.uuidString, originDevice: originDevice)
        } else {
            try? repository.resolve(approval, as: .approved)
        }
    }

    private func dispatch(_ action: IntentAction) {
        guard let intentQueue else {
            // Mac path: the AgentRunner observes status changes and executes.
            try? repository.update(agent) { $0.status = action == .run ? .running : .paused }
            return
        }
        _ = try? intentQueue.enqueue(agentID: agent.id, action: action, originDevice: originDevice)
    }
}
