import SwiftUI
import AgentKit

/// Compact status summary reused as a menu-bar / at-a-glance panel on the Mac.
struct GlanceView: View {
    @State var viewModel: GlanceViewModel

    var body: some View {
        HStack(spacing: 24) {
            stat("Running", value: viewModel.runningCount, color: .green)
            stat("Waiting", value: viewModel.waitingApprovalCount, color: .orange)
            stat("Failed", value: viewModel.failedCount, color: .red)
        }
        .padding()
        .onAppear { viewModel.refresh() }
    }

    private func stat(_ title: String, value: Int, color: Color) -> some View {
        VStack {
            Text("\(value)").font(.title.bold()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
