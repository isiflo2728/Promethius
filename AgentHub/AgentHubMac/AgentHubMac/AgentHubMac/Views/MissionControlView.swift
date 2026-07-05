import SwiftUI
import AgentKit

/// The Mac's primary screen: a grid of agent cards plus any pending approvals.
/// Fully interactive here (the iPhone version is read-only + Intent-driven).
struct MissionControlView: View {
    @State var viewModel: MissionControlViewModel

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 16)]

    var body: some View {
        ScrollView {
            if !viewModel.pendingApprovals.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Needs Attention")
                        .font(.headline)
                    ForEach(viewModel.pendingApprovals) { approval in
                        ApprovalCard(approval: approval)
                    }
                }
                .padding(.bottom, 24)
            }

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.agents) { agent in
                    AgentCard(agent: agent)
                }
            }
        }
        .padding()
        .navigationTitle("Mission Control")
        .toolbar {
            Button {
                viewModel.createAgent(named: "New Agent")
            } label: {
                Label("New Agent", systemImage: "plus")
            }
        }
        .onAppear { viewModel.load() }
    }
}
