import SwiftUI
import SwiftData
import AgentKit

/// Top-level navigation for the Mac window: a fixed "Work Space" section plus a
/// live list of the user's agents.
enum NavSelection: Hashable {
    case today
    case missionControl
    case overView
    case models
    /// A specific agent, identified by id so the selection survives list
    /// reordering and never holds an invalidated `Agent` reference.
    case agent(UUID)
}

struct SidebarView: View {

    @Binding var selection: NavSelection

    @Environment(\.modelContext) private var modelContext

    /// The user's agents, kept live by SwiftData — the list updates as agents
    /// are created or deleted, with no manual reload.
    @Query(sort: \Agent.name) private var agents: [Agent]

    /// Staged for deletion via the context menu, awaiting confirmation.
    /// The sidebar is the only surface that lists *every* agent (Mission
    /// Control shows running ones only), so it needs its own delete.
    @State private var agentPendingDeletion: Agent?

    var body: some View {
        List(selection: $selection) {
            Section("Work Space") {
                Label("Today", systemImage: "sun.max")
                    .tag(NavSelection.today)
                Label("Control", systemImage: "square.grid.2x2")
                    .tag(NavSelection.missionControl)
                Label("Pulse", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(NavSelection.overView)
                Label("Models", systemImage: "sparkles")
                    .tag(NavSelection.models)
            }
            Section("Agents") {
                if agents.isEmpty {
                    Text("No agents yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(agents) { agent in
                        Label(agent.name, systemImage: "brain.head.profile")
                            .tag(NavSelection.agent(agent.id))
                            .contextMenu {
                                Button("Delete…", role: .destructive) {
                                    agentPendingDeletion = agent
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("AgentHub")
        .confirmationDialog(
            "Delete “\(agentPendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { agentPendingDeletion != nil },
                set: { if !$0 { agentPendingDeletion = nil } }
            )
        ) {
            Button("Delete", role: .destructive) { confirmDeletion() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also removes run history, pending approvals, and permissions. It can't be undone.")
        }
    }

    private func confirmDeletion() {
        guard let agent = agentPendingDeletion else { return }
        agentPendingDeletion = nil
        // Don't leave the detail pane pointing at a deleted agent.
        if selection == .agent(agent.id) { selection = .today }
        try? AgentRepository(context: modelContext).delete(agent)
    }
}
