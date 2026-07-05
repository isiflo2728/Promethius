import SwiftUI
import AgentKit

/// iOS mission control: a READ-ONLY list of agents synced from the Mac. Tapping
/// an agent opens a detail screen where actions are enqueued as Intents.
struct MissionControlView: View {
    @State var viewModel: MissionControlViewModel

    var body: some View {
        NavigationStack {
            List(viewModel.agents) { agent in
                NavigationLink(value: agent.id) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(agent.name).font(.headline)
                            Text(agent.summary).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(agent.status.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Agents")
            .navigationDestination(for: UUID.self) { agentID in
                if let agent = viewModel.agents.first(where: { $0.id == agentID }) {
                    AgentDetailView(agent: agent)
                }
            }
            .onAppear { viewModel.load() }
        }
    }
}
