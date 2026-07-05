import SwiftUI
import SwiftData
import AgentKit

/// iOS agent detail. This device does NOT execute anything — Run/Pause/Approve
/// enqueue an `AgentIntent` that the Mac applies when CloudKit delivers it.
///
/// CloudKit sync can lag seconds-to-minutes, so the UI is built around that:
/// - buttons flip to an optimistic "Requested…" state via `isRequestInFlight`
/// - the duplicate-guard in `IntentQueue` means a second tap reuses the same
///   pending command instead of stacking a second one
/// - copy tells the user the Mac will pick it up, so a lagging sync doesn't
///   read as a broken button
struct AgentDetailView: View {
    let agent: Agent
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: AgentDetailViewModel?

    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: agent.status.rawValue)
            }

            Section("Remote control") {
                intentButton(title: "Run", action: .run) { viewModel?.run() }
                intentButton(title: "Pause", action: .pause) { viewModel?.pause() }
            }

            Section("Pending approvals") {
                let approvals = (agent.pendingApprovals ?? []).filter { $0.status == .pending }
                if approvals.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(approvals) { approval in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(approval.title).font(.headline)
                            Text(approval.proposedToolName).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Button("Approve") { viewModel?.approve(approval) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            Section {
                Label("Actions are sent to your Mac and may take a moment to apply.",
                      systemImage: "arrow.triangle.2.circlepath.icloud")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(agent.name)
        .onAppear {
            if viewModel == nil {
                viewModel = AgentDetailViewModel(
                    agent: agent,
                    repository: AgentRepository(context: modelContext),
                    intentQueue: IntentQueue(context: modelContext),
                    originDevice: "iOS"
                )
            }
        }
    }

    @ViewBuilder
    private func intentButton(title: String, action: IntentAction, perform: @escaping () -> Void) -> some View {
        let inFlight = viewModel?.isRequestInFlight(action) ?? false
        Button(action: perform) {
            HStack {
                Text(inFlight ? "\(title) — Requested…" : title)
                Spacer()
                if inFlight { ProgressView() }
            }
        }
        // Disable while in flight: the command is already queued; the duplicate
        // guard would no-op a second tap anyway, but this makes it visible.
        .disabled(inFlight)
    }
}
