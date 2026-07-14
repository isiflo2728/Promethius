import Foundation
import SwiftData

public enum AgentStore {
    /// The full SwiftData schema shared by both apps. Keep every `@Model` in
    /// this list so the CloudKit schema matches across macOS and iOS.
    public static let schema = Schema([
        Agent.self,
        SubAgent.self,
        RunLogEntry.self,
        PendingApproval.self,
        Insight.self,
        Permission.self,
        LocalModel.self,
        Trigger.self,
        ConnectedAccount.self,
    ])

    /// A CloudKit-backed container shared between the Mac and iPhone apps.
    ///
    /// Both targets must declare the SAME iCloud container id in their
    /// entitlements (e.g. `iCloud.com.yourteam.agenthub`) for sync to work.
    public static func makeShared(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: inMemory ? .none : .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create shared ModelContainer: \(error)")
        }
    }
}
