import AppKit
import SwiftUI
import SwiftData
import AgentKit

/// The Mac's primary screen: a live grid of the agents that are currently
/// running. Pending approvals and insights live in Pulse (`GlanceView`), not
/// here. Fully interactive on the Mac (the iPhone version is read-only +
/// Intent-driven).
struct MissionControlView: View {
    @Environment(\.modelContext) private var modelContext
    @State var viewModel: MissionControlViewModel

    /// The window's nav selection, so creating an agent can jump straight to
    /// its detail — the grid below shows running agents only, and a fresh
    /// agent is idle, so it would otherwise appear nowhere on this screen.
    @Binding var navSelection: NavSelection

    /// Whether the grid is in selection mode. Outside it, cards don't respond
    /// to clicks; inside it, every click toggles membership.
    @State private var isSelecting = false
    /// IDs, not `Agent` objects — a deleted model is invalidated by SwiftData
    /// and holding one in a `Set` outlives the row it points at.
    @State private var selection: Set<UUID> = []
    /// Where the last plain or command click landed; shift-click extends from here.
    @State private var anchorID: UUID?
    /// Agents staged for deletion, awaiting confirmation.
    @State private var agentsPendingDeletion: [Agent] = []
    @State private var showingScheduleSheet = false

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 16)]

    /// Drives the confirmation dialog off whether anything is staged for
    /// deletion, and clears the staging when it's dismissed.
    private var showingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { !agentsPendingDeletion.isEmpty },
            set: { if !$0 { agentsPendingDeletion = [] } }
        )
    }

    var body: some View {
        ScrollView {
            if viewModel.agents.isEmpty {
                ContentUnavailableView(
                    "No agents yet",
                    systemImage: "moon.zzz",
                    description: Text("Add an agent to get started. Anything that needs you lives in Pulse.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.agents) { agent in
                    let isSelected = selection.contains(agent.id)

                    AgentCard(agent: agent)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .opacity(isSelected ? 1 : 0)
                        }
                        .overlay(alignment: .topTrailing) {
                            if isSelecting {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, isSelected ? Color.accentColor : .secondary)
                                    .padding(8)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                        .onTapGesture { handleTap(on: agent) }
                        .contextMenu {
                            Button(deleteMenuTitle(for: agent), role: .destructive) {
                                stageDeletion(from: agent)
                            }
                        }
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityAction(named: "Delete") { stageDeletion(from: agent) }
                }
            }
        }
        .padding()
        .navigationTitle("Mission Control")
        .onDeleteCommand { stageDeletionOfSelection() }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: showingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) { confirmDeletion() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also removes run history, pending approvals, and permissions. It can't be undone.")
        }
        .toolbar {
            if isSelecting {
                Button(allSelected ? "Deselect All" : "Select All") {
                    selection = allSelected ? [] : Set(viewModel.agents.map(\.id))
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Delete\(selection.isEmpty ? "" : " (\(selection.count))")", role: .destructive) {
                    stageDeletionOfSelection()
                }
                .disabled(selection.isEmpty)

                Button("Done") { exitSelectionMode() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Select") { isSelecting = true }
                    .disabled(viewModel.agents.isEmpty)

                Button("Schedule") { showingScheduleSheet = true }
                    .disabled(viewModel.agents.isEmpty)

                AddAgentButton(onDismiss: viewModel.load) {
                    CreateAgentView(
                        viewModel: CreateAgentViewModel(
                            repository: AgentRepository(context: modelContext)
                        ),
                        onCreated: { navSelection = .agent($0.id) }
                    )
                }
            }
        }
        .onAppear { viewModel.load() }
        .sheet(isPresented: $showingScheduleSheet, onDismiss: viewModel.load) {
            ScheduleAgentView()
        }
    }

    private var allSelected: Bool {
        !viewModel.agents.isEmpty && selection.count == viewModel.agents.count
    }

    private func exitSelectionMode() {
        isSelecting = false
        selection = []
        anchorID = nil
    }

    // MARK: - Selection

    /// In selection mode a plain click toggles the card, so many can be picked
    /// without holding anything down. Shift still extends from the anchor, for
    /// grabbing a run at once. Outside selection mode, clicks do nothing.
    ///
    /// Reads `NSEvent.modifierFlags` at tap time rather than stacking
    /// modifier-scoped `TapGesture`s, which have unreliable precedence.
    private func handleTap(on agent: Agent) {
        guard isSelecting else { return }

        if NSEvent.modifierFlags.contains(.shift), let anchorID {
            extendSelection(from: anchorID, to: agent.id)
        } else {
            selection.formSymmetricDifference([agent.id])
            anchorID = agent.id
        }
    }

    /// Unions the run of agents between the anchor and the tapped card. Leaves
    /// the anchor where it was, so repeated shift-clicks pivot on one point.
    private func extendSelection(from anchor: UUID, to target: UUID) {
        let ids = viewModel.agents.map(\.id)
        guard let start = ids.firstIndex(of: anchor),
              let end = ids.firstIndex(of: target) else { return }
        let range = start <= end ? start ... end : end ... start
        selection.formUnion(ids[range])
    }

    // MARK: - Deletion

    /// Right-clicking inside the selection acts on all of it; right-clicking
    /// outside it acts on that one card, as the Finder does.
    private func agentsAffected(by agent: Agent) -> [Agent] {
        guard selection.contains(agent.id), selection.count > 1 else { return [agent] }
        return viewModel.agents.filter { selection.contains($0.id) }
    }

    private func deleteMenuTitle(for agent: Agent) -> String {
        let count = agentsAffected(by: agent).count
        return count > 1 ? "Delete \(count) Agents…" : "Delete…"
    }

    private var deleteConfirmationTitle: String {
        guard let first = agentsPendingDeletion.first else { return "" }
        return agentsPendingDeletion.count == 1
            ? "Delete “\(first.name)”?"
            : "Delete \(agentsPendingDeletion.count) agents?"
    }

    private func stageDeletion(from agent: Agent) {
        agentsPendingDeletion = agentsAffected(by: agent)
    }

    /// The Delete key. A no-op when nothing is selected.
    private func stageDeletionOfSelection() {
        guard !selection.isEmpty else { return }
        agentsPendingDeletion = viewModel.agents.filter { selection.contains($0.id) }
    }

    private func confirmDeletion() {
        let deletedIDs = Set(agentsPendingDeletion.map(\.id))
        viewModel.delete(agentsPendingDeletion)

        // Prune, or the selection accumulates IDs pointing at deleted rows.
        selection.subtract(deletedIDs)
        if let anchorID, deletedIDs.contains(anchorID) { self.anchorID = nil }
        agentsPendingDeletion = []

        // Nothing left to act on, so don't strand the user in selection mode.
        if selection.isEmpty { isSelecting = false }
    }
}
