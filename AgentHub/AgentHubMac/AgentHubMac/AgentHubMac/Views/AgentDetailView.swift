import SwiftUI
import AgentKit

/// A single agent's detail: run log timeline, controls, and pending approvals.
struct AgentDetailView: View {
    @State var viewModel: AgentDetailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(viewModel.agent.name).font(.title2).bold()
                    Text(viewModel.agent.summary).foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(status: viewModel.agent.status)
            }

            HStack {
                Button("Run") { viewModel.run() }
                Button("Pause") { viewModel.pause() }
            }

            Divider()

            List(viewModel.runLog) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.kind.rawValue)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(entry.message)
                }
            }
        }
        .padding()
        .navigationTitle(viewModel.agent.name)
    }
}
