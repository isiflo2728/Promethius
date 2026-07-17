import SwiftUI
import SwiftData
import AgentKit

/// Sheet for putting an agent on a schedule ("daily at 9:00" / "every 30m").
/// Writes a `.schedule` trigger the `AgentScheduler` fires while the app is
/// open; one schedule per agent (saving replaces any existing one).
struct ScheduleAgentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Agent.name) private var agents: [Agent]

    @State private var selectedAgentID: UUID?
    @State private var mode: Mode = .daily
    @State private var dailyTime = Calendar.current.date(
        bySettingHour: 9, minute: 0, second: 0, of: .now
    ) ?? .now
    @State private var intervalMinutes = 60

    private let intervalChoices = [15, 30, 60, 120, 240, 480]

    private enum Mode: String, CaseIterable, Identifiable {
        case daily = "Daily at a time"
        case interval = "Every interval"
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Schedule Agent").font(.title2.bold())
                Text("Runs happen while AgentHub is open; a missed time fires on the next launch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Picker("Agent", selection: $selectedAgentID) {
                Text("Choose an agent…").tag(UUID?.none)
                ForEach(agents) { agent in
                    Text(agent.name).tag(UUID?.some(agent.id))
                }
            }

            Picker("Repeat", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .daily:
                DatePicker("Time", selection: $dailyTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
            case .interval:
                Picker("Every", selection: $intervalMinutes) {
                    ForEach(intervalChoices, id: \.self) { minutes in
                        Text(minutes < 60 ? "\(minutes) minutes" : "\(minutes / 60) hour\(minutes == 60 ? "" : "s")")
                            .tag(minutes)
                    }
                }
            }

            if let agent = selectedAgent, let existing = existingSchedule(for: agent) {
                Label("Currently: \(existing.displayText). Saving replaces it.", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                if let agent = selectedAgent, existingSchedule(for: agent) != nil {
                    Button("Remove Schedule", role: .destructive) {
                        removeSchedule(from: agent)
                        dismiss()
                    }
                }

                Spacer()

                Button("Save Schedule") {
                    if let agent = selectedAgent {
                        save(to: agent)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedAgent == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 440, minHeight: 320)
        .onChange(of: selectedAgentID) { _, _ in prefillFromExisting() }
    }

    private var selectedAgent: Agent? {
        agents.first { $0.id == selectedAgentID }
    }

    private func existingSchedule(for agent: Agent) -> Schedule? {
        (agent.triggers ?? [])
            .first { $0.kind == .schedule }
            .flatMap { Schedule($0.configuration) }
    }

    /// Editing an already-scheduled agent starts from its current schedule.
    private func prefillFromExisting() {
        guard let agent = selectedAgent, let existing = existingSchedule(for: agent) else { return }
        switch existing.kind {
        case .daily(let hour, let minute):
            mode = .daily
            dailyTime = Calendar.current.date(
                bySettingHour: hour, minute: minute, second: 0, of: .now
            ) ?? dailyTime
        case .interval(let seconds):
            mode = .interval
            let minutes = Int(seconds / 60)
            intervalMinutes = intervalChoices.contains(minutes) ? minutes : 60
        }
    }

    private var configuration: String {
        switch mode {
        case .daily:
            let parts = Calendar.current.dateComponents([.hour, .minute], from: dailyTime)
            return String(format: "daily %02d:%02d", parts.hour ?? 9, parts.minute ?? 0)
        case .interval:
            return "every \(intervalMinutes)m"
        }
    }

    private func save(to agent: Agent) {
        try? AgentRepository(context: modelContext).update(agent) { agent in
            var triggers = (agent.triggers ?? []).filter { $0.kind != .schedule }
            triggers.append(Trigger(kind: .schedule, configuration: configuration))
            agent.triggers = triggers
        }
    }

    private func removeSchedule(from agent: Agent) {
        try? AgentRepository(context: modelContext).update(agent) { agent in
            agent.triggers = (agent.triggers ?? []).filter { $0.kind != .schedule }
        }
    }
}

#Preview {
    ScheduleAgentView()
        .modelContainer(PreviewData.container)
}
