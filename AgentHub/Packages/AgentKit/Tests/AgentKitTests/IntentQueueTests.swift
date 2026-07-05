import Testing
import Foundation
import SwiftData
@testable import AgentKit

/// Verifies the CloudKit-lag safeguards on the producer side: enqueuing the
/// same command twice (as happens when a user taps a lagging button again)
/// must NOT create a duplicate, and applying is idempotent.
///
/// `.serialized`: SwiftData registers a schema's entities in a *process-global*
/// registry keyed by class name. Building multiple in-memory containers in one
/// test process must not race or interleave, or later containers get a stale
/// entity mapping and silently drop inserts. Each test here builds its own
/// fresh `Schema` + container and runs serially. (The app itself only ever
/// creates one container for its whole lifetime, so this is a test-only concern
/// — see `productionMakeSharedPathWorks`.)
@MainActor
@Suite(.serialized)
struct IntentQueueTests {

    /// A fresh in-memory container built from a fresh `Schema` (not the shared
    /// static one), so repeated container creation across tests stays isolated.
    private func makeQueue() throws -> IntentQueue {
        let models: [any PersistentModel.Type] = [
            Agent.self, SubAgent.self, RunLogEntry.self, PendingApproval.self,
            Permission.self, LocalModel.self, Trigger.self, ConnectedAccount.self,
            AgentIntent.self,
        ]
        let container = try ModelContainer(
            for: Schema(models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return IntentQueue(context: ModelContext(container))
    }

    @Test func enqueueDeduplicatesUnappliedCommands() throws {
        let queue = try makeQueue()
        let agentID = UUID()

        let first = try queue.enqueue(agentID: agentID, action: .run)
        let second = try queue.enqueue(agentID: agentID, action: .run)

        #expect(first.id == second.id, "A second identical, unapplied command must reuse the first")
        #expect(try queue.pendingIntents().count == 1)
    }

    @Test func appliedCommandIsNotRedelivered() throws {
        let queue = try makeQueue()
        let agentID = UUID()

        let intent = try queue.enqueue(agentID: agentID, action: .approve, payload: "abc")
        try queue.markApplied(intent)

        #expect(try queue.pendingIntents().isEmpty)
        // A fresh enqueue after apply is allowed (it's a new request).
        let again = try queue.enqueue(agentID: agentID, action: .approve, payload: "abc")
        #expect(again.id != intent.id)
    }

    @Test func markAppliedIsIdempotent() throws {
        let queue = try makeQueue()
        let intent = try queue.enqueue(agentID: UUID(), action: .pause)

        try queue.markApplied(intent)
        let firstStamp = intent.appliedAt
        try queue.markApplied(intent)

        #expect(intent.appliedAt == firstStamp, "Re-applying must not move the timestamp")
    }
}

// Note on `AgentStore.makeShared`: the app builds exactly one container from the
// shared static schema at launch, which works. It is deliberately NOT unit-tested
// here — swift-testing runs all tests in one process, and SwiftData's global,
// class-name-keyed entity registry makes creating a *second* container from that
// same static schema unreliable on current OS builds. The dedup/idempotency logic
// above is what these tests cover, using isolated fresh containers.
