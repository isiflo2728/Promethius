import SwiftUI
import AgentKit

/// A single agent tile in the Mission Control grid.
struct AgentCard: View {
    let agent: Agent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(agent.name).font(.headline)
                Spacer()
                StatusPill(status: agent.status)
            }
            Text(agent.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            ActivitySparkline(values: sampleActivity)
                .frame(height: 28)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary))
    }

    // Placeholder until run history feeds the sparkline.
    private var sampleActivity: [Double] { [2, 5, 3, 8, 6, 9, 4] }
}

#Preview {
    AgentCard(agent: .sample)
        .padding()
        .frame(width: 300)
}
