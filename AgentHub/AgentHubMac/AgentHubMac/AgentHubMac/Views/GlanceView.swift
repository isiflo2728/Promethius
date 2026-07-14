import SwiftUI
import AgentKit

/// Compact status summary reused as a menu-bar / at-a-glance panel on the Mac.
struct GlanceView: View {
    @State var viewModel: GlanceViewModel
    @State private var hoveredCard: String?

    /// Two equal columns, matching the Glance mockup's card grid.
    private let columns = [GridItem(.flexible(), spacing: 16),
                           GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // MARK: Status
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Status")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            stat("Running", value: viewModel.runningCount, color: .green)
                            stat("Waiting", value: viewModel.waitingApprovalCount, color: .orange)
                            stat("Failed", value: viewModel.failedCount, color: .red)
                            Spacer()
                        }
                    }
                    .padding(20)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))

                    // MARK: Needs you
                    if !viewModel.pendingApprovals.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Needs you")
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                                ForEach(viewModel.pendingApprovals) { approval in
                                    ApprovalCard(approval: approval)
                                }
                            }
                        }
                    }

                    // MARK: Recent insights
                    if !viewModel.insights.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Recent insights")
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                                ForEach(viewModel.insights) { insight in
                                    InsightCard(insight: insight)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .onAppear { viewModel.refresh() }
        }
        .navigationTitle("At a Glance")
        .navigationSubtitle("What your agents found while you were away!")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    private func stat(_ title: String, value: Int, color: Color) -> some View {
        VStack {
            Text("\(value)").font(.title.bold()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: 96, minHeight: 96)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary))
        .shadow(color: hoveredCard == title ? color.opacity(0.6) : .clear,
                radius: hoveredCard == title ? 12 : 0)
        .animation(.easeOut(duration: 0.2), value: hoveredCard)
        .onHover { hovering in
            hoveredCard = hovering ? title : nil
        }
    }
}

#Preview {
    GlanceView(viewModel: GlanceViewModel(repository: PreviewData.repository))
}
