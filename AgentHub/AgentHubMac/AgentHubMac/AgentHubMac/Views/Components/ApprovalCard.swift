import SwiftUI
import SwiftData
import AgentKit

/// A human-in-the-loop prompt shown when an agent wants to run a gated action
/// (e.g. sending email via Composio). Approve/Discard resolve the underlying
/// `PendingApproval`; on the Mac this directly unblocks the runner.
struct ApprovalCard: View {
    let approval: PendingApproval
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(approval.title).font(.headline)
                Text(approval.detail).font(.callout).foregroundStyle(.secondary)
                Text(approval.proposedToolName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack {
                Button("Approve") { resolve(.approved) }
                    .buttonStyle(.borderedProminent)
                Button("Discard") { resolve(.discarded) }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func resolve(_ status: ApprovalStatus) {
        let repository = AgentRepository(context: modelContext)
        try? repository.resolve(approval, as: status)
    }
}
