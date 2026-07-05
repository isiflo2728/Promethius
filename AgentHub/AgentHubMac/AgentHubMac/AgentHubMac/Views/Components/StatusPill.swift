import SwiftUI
import AgentKit

/// Small colored capsule reflecting an agent's status. Shared visual language
/// across Mac and (conceptually) the iPhone.
struct StatusPill: View {
    let status: AgentStatus

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch status {
        case .idle: "Idle"
        case .running: "Running"
        case .waitingApproval: "Waiting"
        case .paused: "Paused"
        case .failed: "Failed"
        }
    }

    private var color: Color {
        switch status {
        case .idle: .secondary
        case .running: .green
        case .waitingApproval: .orange
        case .paused: .blue
        case .failed: .red
        }
    }
}
