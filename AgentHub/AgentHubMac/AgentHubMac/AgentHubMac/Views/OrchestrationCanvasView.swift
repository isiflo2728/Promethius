import SwiftUI
import AgentKit

/// Drag-to-arrange canvas for wiring an agent's sub-agents into a chain.
/// Node positions are local view state (`OrchestrationViewModel.nodePositions`);
/// only the resulting order is persisted.
struct OrchestrationCanvasView: View {
    @State var viewModel: OrchestrationViewModel

    var body: some View {
        GeometryReader { _ in
            ZStack {
                ForEach(viewModel.subAgents) { sub in
                    nodeView(sub)
                        .position(viewModel.nodePositions[sub.id] ?? .init(x: 120, y: 120))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    viewModel.nodePositions[sub.id] = value.location
                                }
                        )
                }
            }
        }
        .navigationTitle("Orchestration")
    }

    private func nodeView(_ sub: SubAgent) -> some View {
        VStack(spacing: 4) {
            Text(sub.name).bold()
            Text(sub.role).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }
}
