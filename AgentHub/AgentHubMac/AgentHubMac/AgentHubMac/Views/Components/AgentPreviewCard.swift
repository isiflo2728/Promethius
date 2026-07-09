import SwiftUI
import AgentKit

/// A read-only rendering of the agent the create form would produce right now.
/// Deliberately mirrors `AgentCard` so the user recognizes what they're making.
struct AgentPreviewCard: View {
    let name: String
    let summary: String
    let trigger: TriggerKind
    let modelName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "diamond.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(.headline)
                        .foregroundStyle(name.isEmpty ? .secondary : .primary)
                    Text(trigger.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                StatusPill(status: .idle)
            }

            Text(displaySummary)
                .font(.callout)
                .foregroundStyle(summary.isEmpty ? .tertiary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            HStack {
                Text("Not run yet")
                Spacer()
                Text(modelName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview of \(displayName), triggered \(trigger.displayName), using \(modelName)")
    }

    private var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled Agent" : name
    }

    private var displaySummary: String {
        summary.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Describe what this agent should do on the left."
            : summary
    }
}

#Preview {
    VStack(spacing: 16) {
        AgentPreviewCard(name: "", summary: "", trigger: .manual, modelName: "Llama 3.1 8B")
        AgentPreviewCard(name: "Inbox Triage",
                         summary: "Sorts new mail and drafts quick replies for review.",
                         trigger: .composioEvent,
                         modelName: "Phi-3 Mini")
    }
    .padding()
    .frame(width: 320)
}
