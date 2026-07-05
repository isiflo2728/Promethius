import SwiftUI
import SwiftData
import AgentKit

@main
struct AgentHubMacApp: App {
    /// The shared CloudKit-backed container. The Mac is the executor, so this
    /// is where the real agent runs happen.
    let container = AgentStore.makeShared()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

/// Top-level split view: sidebar + mission control detail.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            MissionControlView(
                viewModel: MissionControlViewModel(
                    repository: AgentRepository(context: modelContext)
                )
            )
        }
    }
}
