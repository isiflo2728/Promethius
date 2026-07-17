import SwiftUI
import SwiftData
import AgentKit

/// A human-in-the-loop prompt shown when an agent wants to run a gated action
/// (e.g. sending email via Composio). Approve/Discard resolve the underlying
/// `PendingApproval`; on the Mac this directly unblocks the runner.
struct ApprovalCard: View {
    let approval: PendingApproval
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var isEditing = false
    @State private var draftText = ""

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

            // Context line
            Text(approval.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // The editable draft the agent proposes to send.
            if !approval.draftBody.isEmpty {
                Text(approval.draftBody)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 10))
            }

            // Push actions to the bottom so cards with shorter detail still
            // line their buttons up with taller neighbours in the grid.
            Spacer(minLength: 12)

            // Actions. A connect-account approval carries an OAuth link the
            // user must open — approving means visiting it, not sending.
            HStack(spacing: 10) {
                if let url = approval.actionURL {
                    Button("Open Link") {
                        openURL(url)
                        resolve(.approved)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Approve") { resolve(.approved) }
                        .buttonStyle(.borderedProminent)
                }
                Button("Discard") { resolve(.discarded) }
                    .buttonStyle(.bordered)
                if !approval.draftBody.isEmpty {
                    Spacer(minLength: 0)
                    Button("Edit") { beginEditing() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        // Uniform tile size across the Glance grid — kept in sync with
        // InsightCard's frame so the two card types line up evenly. Taller
        // content grows past this; nothing renders shorter.
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Approval needed: \(approval.title). \(approval.detail)")
        .sheet(isPresented: $isEditing) {
            DraftEditor(
                title: approval.title,
                text: $draftText,
                onSave: saveDraft,
                onCancel: { isEditing = false }
            )
        }
    }

    /// "via <agent> · <time> ago" line beneath the title.
    private var provenance: String {
        let source = approval.agent?.name.isEmpty == false ? approval.agent!.name : "an agent"
        let ago = approval.createdAt.formatted(.relative(presentation: .named))
        return "via \(source) · \(ago)"
    }

    private func beginEditing() {
        draftText = approval.draftBody
        isEditing = true
    }

    private func saveDraft() {
        let repository = AgentRepository(context: modelContext)
        try? repository.updateDraft(approval, to: draftText)
        isEditing = false
    }

    private func resolve(_ status: ApprovalStatus) {
        let repository = AgentRepository(context: modelContext)
        try? repository.resolve(approval, as: status)
    }
}

/// A sheet for editing an approval's draft message before it's sent. Shared by
/// `ApprovalCard` (Pulse) and `TodayView`.
struct DraftEditor: View {
    let title: String
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text("Edit the draft before it's sent.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 180)
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

#Preview {
    ApprovalCard(
        approval: PendingApproval(
            title: "Reply ready to send",
            detail: "Re: \u{201C}Q3 budget review\u{201D} — to Sam",
            draftBody: "Revised numbers by Friday. Can we push the call to Monday?",
            proposedToolName: "composio.gmail.send"
        )
    )
    .padding()
    .frame(width: 380)
    .modelContainer(for: PendingApproval.self, inMemory: true)
}
