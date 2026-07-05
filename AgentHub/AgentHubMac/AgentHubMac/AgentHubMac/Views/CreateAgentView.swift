import SwiftUI
import AgentKit

/// Form to create an agent: name, summary, and the permission scopes it may
/// use. Remote (Composio) scopes surface a "needs connection" hint.
struct CreateAgentView: View {
    @State var viewModel: CreateAgentViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Basics") {
                TextField("Name", text: $viewModel.name)
                TextField("Summary", text: $viewModel.summary, axis: .vertical)
            }

            Section("Permissions") {
                ForEach(PermissionScope.allCases, id: \.self) { scope in
                    Toggle(isOn: binding(for: scope)) {
                        HStack {
                            Text(scope.rawValue)
                            if scope.isRemote {
                                Text("Composio").font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.blue.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                }
            }

            if !viewModel.remoteScopesNeedingConnection.isEmpty {
                Section {
                    Label("Connect these accounts in Setup before the agent can use them.",
                          systemImage: "link")
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("New Agent")
        .toolbar {
            Button("Save") {
                if viewModel.save() != nil { dismiss() }
            }
            .disabled(!viewModel.canSave)
        }
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
