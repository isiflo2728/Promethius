import SwiftUI
import SwiftData
import AgentKit

@main
struct AgentHubMobileApp: App {
    /// Same CloudKit-backed schema as the Mac, but this app is a monitor +
    /// remote: it never runs agents or holds the Composio key. Actions are
    /// enqueued as `AgentIntent`s for the Mac to apply.
    let container = AgentStore.makeShared()

    var body: some Scene {
        WindowGroup {
            MissionControlView(
                viewModel: MissionControlViewModel(
                    repository: AgentRepository(context: container.mainContext)
                )
            )
        }
        .modelContainer(container)
    }
}
