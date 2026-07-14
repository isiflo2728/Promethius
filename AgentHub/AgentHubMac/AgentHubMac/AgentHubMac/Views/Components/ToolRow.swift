import SwiftUI
import AgentKit

/// One grantable permission scope in the create form: what it is, what it will
/// ask for, and whether using it interrupts a run for approval.
struct ToolRow: View {
    let scope: PermissionScope
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: scope.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(scope.displayName).font(.callout.weight(.medium))
                    Text("Requests: \(scope.requestSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if scope.needsApproval {
                    Text("Needs approval")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.teal.opacity(0.15), in: Capsule())
                        .foregroundStyle(.teal)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.checkbox)
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityHint: String {
        let base = "Requests \(scope.requestSummary.lowercased())."
        return scope.needsApproval ? base + " Runs pause for your approval." : base
    }
}

#Preview {
    @Previewable @State var mail = true
    @Previewable @State var web = false

    VStack(spacing: 8) {
        ToolRow(scope: .composioGmail, isOn: $mail)
        ToolRow(scope: .webFetch, isOn: $web)
    }
    .padding()
    .frame(width: 460)
}
