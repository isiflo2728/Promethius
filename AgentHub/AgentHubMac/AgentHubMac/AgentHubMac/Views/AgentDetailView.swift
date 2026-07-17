import SwiftUI
import SwiftData
import AgentKit

/// A single agent's detail: an identity/controls/activity-log card on the left,
/// and a live-activity chart + permission toggles on the right.
struct AgentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State var viewModel: AgentDetailViewModel

    /// Reply tone. A visual affordance for now — not yet persisted on the agent.
    @State private var tone: Tone = .neutral
    @State private var showingOrchestration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                HStack(alignment: .top, spacing: 20) {
                    identityCard
                    activityCard
                        .frame(width: 320)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(viewModel.agent.name)
        .sheet(isPresented: $showingOrchestration) {
            NavigationStack {
                OrchestrationCanvasView(
                    viewModel: OrchestrationViewModel(
                        agent: viewModel.agent,
                        repository: AgentRepository(context: modelContext)
                    )
                )
                .navigationTitle("Orchestration")
                .toolbar {
                    Button("Done") { showingOrchestration = false }
                }
            }
            .frame(minWidth: 640, minHeight: 480)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(viewModel.agent.name)
                .font(.title).bold()
            Spacer()
            Picker("Tone", selection: $tone) {
                ForEach(Tone.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    // MARK: - Left: identity + controls + activity log

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                iconTile
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.agent.name)
                        .font(.title2).bold()
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                StatusPill(status: viewModel.agent.status)
            }

            if !viewModel.agent.summary.isEmpty {
                Text(viewModel.agent.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            controls

            activityLog
        }
        .cardSurface()
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.background.tertiary)
            .frame(width: 56, height: 56)
            .overlay(
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.primary)
            )
            .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            // The runner drives the agent-harness backend and appends run-log
            // rows as events stream in; the SwiftData @Model updates keep this
            // view live for the whole run. Constructed per run — it holds no
            // state between runs (the harness keys sessions per run).
            Button(viewModel.agent.status == .running ? "Running…" : "Run Now") {
                // Not viewModel.run() — that pre-sets status to .running,
                // which would trip the runner's own double-run guard. The
                // runner owns the status for the whole run lifecycle.
                let runner = AgentRunner(repository: AgentRepository(context: modelContext))
                Task { await runner.run(viewModel.agent) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.agent.status == .running)
            Button("Pause") { viewModel.pause() }
                .buttonStyle(.bordered)
            Button {
                showingOrchestration = true
            } label: {
                HStack(spacing: 4) {
                    Text("Orchestration")
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
        }
    }

    private var activityLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Activity Log")

            if viewModel.runLog.isEmpty {
                Text("No activity yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.runLog.reversed().prefix(6))) { entry in
                    logRow(entry)
                }
            }
        }
    }

    private func logRow(_ entry: RunLogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(entry.kind == .error ? Color.red : Color.accentColor)
                .frame(width: 7, height: 7)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.timestamp.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Right: live activity + permissions

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Live Activity")
                // Re-render every second so the run clock ticks and the
                // machine readings stay current during a run.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    liveStats(at: context.date)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                sectionLabel("Permissions")
                if viewModel.permissions.isEmpty {
                    Text("No permissions granted.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.permissions) { permission in
                        permissionRow(permission)
                    }
                }
            }
        }
        .cardSurface()
    }

    // MARK: - Live stats

    @ViewBuilder
    private func liveStats(at now: Date) -> some View {
        let isRunning = viewModel.agent.status == .running

        VStack(alignment: .leading, spacing: 14) {
            statRow(
                icon: "stopwatch",
                title: isRunning ? "Run time" : "Last run",
                value: runDurationLabel(at: now),
                valueColor: isRunning ? .green : .primary
            )

            statRow(
                icon: "thermometer.medium",
                title: "Thermal state",
                value: thermalLabel.text,
                valueColor: thermalLabel.color
            )

            VStack(alignment: .leading, spacing: 6) {
                statRow(
                    icon: "memorychip",
                    title: "Memory in use",
                    value: memoryLabel,
                    valueColor: .primary
                )
                ProgressView(value: memoryFraction)
                    .tint(memoryFraction > 0.85 ? .orange : .accentColor)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func statRow(icon: String, title: String, value: String, valueColor: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(valueColor)
        }
    }

    /// Start of the most recent run, from the log the runner writes.
    private var lastRunStart: Date? {
        viewModel.runLog.last { $0.kind == .system && $0.message == "Run started" }?.timestamp
    }

    /// Ticking elapsed time while running; the last run's total once idle.
    private func runDurationLabel(at now: Date) -> String {
        guard let start = lastRunStart else { return "—" }
        let end = viewModel.agent.status == .running
            ? now
            : (viewModel.runLog.last?.timestamp ?? start)
        let seconds = max(0, end.timeIntervalSince(start))
        return Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    private var thermalLabel: (text: String, color: Color) {
        switch SystemStats.thermalState {
        case .nominal: ("Nominal", .green)
        case .fair: ("Fair", .yellow)
        case .serious: ("Serious", .orange)
        case .critical: ("Critical", .red)
        @unknown default: ("Unknown", .secondary)
        }
    }

    private var memoryUsed: UInt64 { SystemStats.memoryUsedBytes() ?? 0 }

    private var memoryFraction: Double {
        Double(memoryUsed) / Double(SystemStats.memoryTotalBytes)
    }

    private var memoryLabel: String {
        let format = ByteCountFormatStyle(style: .memory)
        let total = SystemStats.memoryTotalBytes
        return "\(Int64(memoryUsed).formatted(format)) of \(Int64(total).formatted(format))"
    }

    private func permissionRow(_ permission: Permission) -> some View {
        Toggle(isOn: Binding(
            get: { permission.isEnabled },
            set: { viewModel.setPermission(permission, enabled: $0) }
        )) {
            Text(permission.scope.displayName)
                .font(.body)
        }
        .toggleStyle(.switch)
        .tint(.accentColor)
    }

    // MARK: - Helpers

    /// "On git commit · DeepSeek Coder 6.7B" — trigger, then model, whichever
    /// are present.
    private var subtitle: String {
        var parts: [String] = []
        if let trigger = viewModel.primaryTrigger {
            parts.append(triggerText(trigger))
        }
        if !viewModel.agent.modelName.isEmpty {
            parts.append(viewModel.agent.modelName)
        }
        return parts.isEmpty ? "Manual" : parts.joined(separator: " · ")
    }

    private func triggerText(_ trigger: Trigger) -> String {
        let config = trigger.configuration.trimmingCharacters(in: .whitespaces)
        switch trigger.kind {
        case .manual: return "Manual"
        case .schedule:
            // "daily 09:00" / "every 30m" configs render as "Daily at 09:00".
            return Schedule(config)?.displayText ?? (config.isEmpty ? "On schedule" : "On \(config)")
        case .fileChange: return config.isEmpty ? "On file change" : "On \(config)"
        case .composioEvent: return config.isEmpty ? "On event" : "On \(config)"
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Tone

private enum Tone: String, CaseIterable, Identifiable {
    case technical, neutral, light
    var id: Self { self }
    var label: String { rawValue.capitalized }
}

// MARK: - Card surface

private struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.quaternary))
    }
}

private extension View {
    func cardSurface() -> some View { modifier(CardSurface()) }
}

#Preview {
    AgentDetailView(
        viewModel: AgentDetailViewModel(
            agent: PreviewData.detailedAgent,
            repository: PreviewData.repository
        )
    )
    .frame(width: 900, height: 640)
    .modelContainer(PreviewData.container)
}
