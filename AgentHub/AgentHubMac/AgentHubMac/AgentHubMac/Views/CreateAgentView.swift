import SwiftUI
import AgentKit

/// Create sheet for a new agent. The form sits on the left; the right column
/// previews the agent it will produce and summarizes what it's allowed to do.
///
/// Permissions are granted at the scope level (`PermissionScope`), which is the
/// granularity the schema and the tool layer actually enforce.
struct CreateAgentView: View {
    @State var viewModel: CreateAgentViewModel
    @Environment(\.dismiss) private var dismiss

    /// Called with the newly created agent just before the sheet dismisses.
    /// Mission Control's grid shows running agents only, so without this the
    /// fresh (idle) agent is invisible from where it was created — the caller
    /// uses it to navigate straight to the new agent's detail.
    var onCreated: (Agent) -> Void = { _ in }

    /// Shown but not persisted — `Agent` has no model relationship yet.
    private let modelChoices = [
        "Llama 3.1 8B", "Phi-3 Mini", "DeepSeek Coder 6.7B", "Whisper + Llama 3 8B",
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                form
                sidebar.frame(width: 300)
            }
            .padding(20)

            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 880, minHeight: 640)
    }

    // MARK: - Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("New Agent").font(.title2.bold())

                field("Name") {
                    TextField("e.g. Podcast Summarizer", text: $viewModel.name)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Name")
                        .inputFieldBackground()
                }

                field("What should it do?") {
                    TextField("Describe the task in plain language…",
                              text: $viewModel.summary,
                              axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(4 ... 8)
                        .accessibilityLabel("What should it do?")
                        .inputFieldBackground()
                }

                field("Trigger") {
                    HStack(spacing: 8) {
                        ForEach(TriggerKind.allCases, id: \.self) { kind in
                            Chip(title: kind.displayName, isSelected: viewModel.trigger == kind) {
                                viewModel.trigger = kind
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Trigger")
                }

                field("Model") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
                              alignment: .leading, spacing: 8) {
                        ForEach(modelChoices, id: \.self) { name in
                            Chip(title: name, isSelected: viewModel.modelName == name) {
                                viewModel.modelName = name
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Model")
                }

                tools
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("Tools")
                Spacer()
                Text("\(viewModel.selectedScopes.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Pick only what this agent needs. Each tool requests its own permission — least privilege by default.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(ToolGroup.allCases) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Label(group.title, systemImage: group.symbolName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(group.scopes, id: \.self) { scope in
                        ToolRow(scope: scope, isOn: binding(for: scope))
                    }
                }
            }
        }
    }

    // MARK: - Preview column

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Live Preview")
                AgentPreviewCard(name: viewModel.name,
                                 summary: viewModel.summary,
                                 trigger: viewModel.trigger,
                                 modelName: viewModel.modelName)
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Tools & Access")
                accessSummary
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var accessSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.selectedScopes.isEmpty {
                Text("No tools yet — this agent can think and summarize, but can't take action until you add tools.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedSelection, id: \.self) { scope in
                    Label(scope.displayName, systemImage: scope.symbolName)
                        .font(.callout)
                }

                if !viewModel.remoteScopesNeedingConnection.isEmpty {
                    Divider()
                    Label("Connect these accounts in Setup before the agent can use them.",
                          systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Spacer()

            Button("Create Agent") {
                if let agent = viewModel.save() {
                    onCreated(agent)
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSave)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Building blocks

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .kerning(0.6)
            .foregroundStyle(.secondary)
    }

    private func field<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sortedSelection: [PermissionScope] {
        viewModel.selectedScopes.sorted { $0.displayName < $1.displayName }
    }

    private func binding(for scope: PermissionScope) -> Binding<Bool> {
        Binding(
            get: { viewModel.selectedScopes.contains(scope) },
            set: { isOn in
                if isOn { viewModel.selectedScopes.insert(scope) }
                else { viewModel.selectedScopes.remove(scope) }
            }
        )
    }
}

private extension View {
    /// The recessed capsule-less input treatment shared by the text fields.
    func inputFieldBackground() -> some View {
        padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }
}

#Preview {
    CreateAgentView(viewModel: CreateAgentViewModel(repository: PreviewData.repository))
}
