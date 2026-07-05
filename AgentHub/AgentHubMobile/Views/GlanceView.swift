import SwiftUI
import AgentKit

/// iOS at-a-glance summary — mirrors the widget content in-app.
struct GlanceView: View {
    @State var viewModel: GlanceViewModel

    var body: some View {
        HStack(spacing: 20) {
            badge("\(viewModel.runningCount)", "Running", .green)
            badge("\(viewModel.waitingApprovalCount)", "Waiting", .orange)
            badge("\(viewModel.failedCount)", "Failed", .red)
        }
        .onAppear { viewModel.refresh() }
    }

    private func badge(_ value: String, _ title: String, _ color: Color) -> some View {
        VStack {
            Text(value).font(.title2.bold()).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
