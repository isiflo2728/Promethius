import SwiftUI
import SwiftData
import AgentKit

@main
struct AgentHubMacApp: App {
    /// The shared CloudKit-backed container. The Mac is the executor, so this
    /// is where the real agent runs happen.
    let container = AgentStore.makeShared()

    init() {
        #if DEBUG
        DevSeed.seedIfNeeded(container.mainContext)
        #endif
    }

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
    @State private var selection: NavSelection = .missionControl

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            detail
        }
    }

    private var repository: AgentRepository {
        AgentRepository(context: modelContext)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .missionControl:
            MissionControlView(
                viewModel: MissionControlViewModel(repository: repository)
            )
        case .overView:
            GlanceView(viewModel: GlanceViewModel(repository: repository))
        case .models:
            ContentUnavailableView("Models", systemImage: "sparkles")
        case .agent1, .agent2:
            ContentUnavailableView("Agent", systemImage: "brain.head.profile")
        }
    }
}
