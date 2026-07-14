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
        VStack(alignment: .leading, spacing: 14) {
            // Header: icon · title/provenance · action-type pill
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(approval.title)
                        .font(.headline)
                    Text(provenance)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Approve")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(.green.opacity(0.5)))
            }

            // Detail
            Text(approval.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Actions
            HStack(spacing: 10) {
                Button("Approve") { resolve(.approved) }
                    .buttonStyle(.borderedProminent)
                Button("Discard") { resolve(.discarded) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Approval needed: \(approval.title). \(approval.detail)")
    }

    /// "via <agent> · <time> ago" line beneath the title.
    private var provenance: String {
        let source = approval.agent?.name.isEmpty == false ? approval.agent!.name : "an agent"
        let ago = approval.createdAt.formatted(.relative(presentation: .named))
        return "via \(source) · \(ago)"
    }

    private func resolve(_ status: ApprovalStatus) {
        let repository = AgentRepository(context: modelContext)
        try? repository.resolve(approval, as: status)
    }
}

#Preview {
    ApprovalCard(
        approval: PendingApproval(
            title: "Reply ready to send",
            detail: "\u{201C}Q3 budget review\u{201D} from Sam — drafted: \u{201C}Revised numbers by Friday, can we push the call to Monday?\u{201D}",
            proposedToolName: "composio.gmail.send"
        )
    )
    .padding()
    .frame(width: 380)
    .modelContainer(for: PendingApproval.self, inMemory: true)
}
