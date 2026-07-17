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
    @State private var selection: NavSelection = .today

    /// Lives here rather than in TodayView so the "ask anything" conversation
    /// (transcript + server session ID) survives tab switches — the detail
    /// switch below destroys TodayView every time the user navigates away.
    @State private var todayChat = ChatViewModel()

    /// Mirrors the sidebar's live agent list so a `.agent(id)` selection can be
    /// resolved back to its model for the detail pane.
    @Query private var agents: [Agent]

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            detail
        }
        // Warm the "On your plate" briefing at launch so the slow agent run
        // is already underway (or done) before the user first looks at
        // Today. Deduped with TodayView's own load via a shared task.
        .task { await TodayViewModel.warmBriefing() }
        // The schedule engine: checks every agent's schedule trigger once a
        // minute for the window's lifetime and starts due runs. Lives here
        // (not in a service singleton) so it uses the same modelContext as
        // the rest of the UI.
        .task {
            let scheduler = AgentScheduler(context: modelContext)
            while !Task.isCancelled {
                scheduler.tick()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private var repository: AgentRepository {
        AgentRepository(context: modelContext)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .today:
            TodayView(viewModel: TodayViewModel(
                repository: repository,
                eventProvider: CalendarService()
            ), chat: todayChat)
        case .missionControl:
            MissionControlView(
                viewModel: MissionControlViewModel(repository: repository),
                navSelection: $selection
            )
        case .overView:
            GlanceView(viewModel: GlanceViewModel(repository: repository))
        case .models:
            ContentUnavailableView("Models", systemImage: "sparkles")
        case .agent(let id):
            if let agent = agents.first(where: { $0.id == id }) {
                AgentDetailView(
                    viewModel: AgentDetailViewModel(agent: agent, repository: repository)
                )
                // Tie the view's identity to the agent so switching between
                // agents rebuilds it — otherwise SwiftUI reuses the instance
                // and its @State view model keeps pointing at the first agent.
                .id(agent.id)
            } else {
                ContentUnavailableView("Agent not found", systemImage: "brain.head.profile")
            }
        }
    }
}
